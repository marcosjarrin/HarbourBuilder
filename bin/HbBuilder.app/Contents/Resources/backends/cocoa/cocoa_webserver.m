/*
 * cocoa_webserver.m — HIX-compatible HTTP server for HarbourBuilder/macOS
 *
 * Architecture:
 *   - BSD socket listener on GCD global queue (background accept loop)
 *   - Each accepted connection → GCD concurrent queue (parse HTTP)
 *   - Harbour dispatch → dispatch_sync(main_queue) to call TWebServer:Dispatch()
 *   - s_current_ctx global pointer is valid only while Harbour handler runs
 *     (safe: all Harbour runs serialized on main thread)
 */

#import <Foundation/Foundation.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <pthread.h>

#include "hbapi.h"
#include "hbvm.h"
#include "hbapiitm.h"
#include "hbapicls.h"

/* ── HixCtx ─────────────────────────────────────────────────── */

typedef struct {
    char   *method;
    char   *path;
    char   *query;
    char   *body;
    char   *ip;
    char   *out_buf;
    size_t  out_len;
    size_t  out_cap;
    int     status;
    char   *content_type;
} HixCtx;

static HixCtx *hix_ctx_new(const char *method, const char *path,
                             const char *query,  const char *body,
                             const char *ip)
{
    HixCtx *ctx   = calloc(1, sizeof(HixCtx));
    ctx->method   = strdup(method ? method : "GET");
    ctx->path     = strdup(path   ? path   : "/");
    ctx->query    = strdup(query  ? query  : "");
    ctx->body     = strdup(body   ? body   : "");
    ctx->ip       = strdup(ip     ? ip     : "");
    ctx->status   = 200;
    ctx->out_cap  = 8192;
    ctx->out_buf  = malloc(ctx->out_cap);
    ctx->out_buf[0] = '\0';
    ctx->content_type = strdup("text/html; charset=utf-8");
    return ctx;
}

static void hix_ctx_write(HixCtx *ctx, const char *text, size_t len)
{
    if (!text || len == 0) return;
    if (ctx->out_len + len + 1 > ctx->out_cap) {
        ctx->out_cap = (ctx->out_len + len + 1) * 2 + 4096;
        char *new_buf = realloc(ctx->out_buf, ctx->out_cap);
        if (!new_buf) { ctx->out_cap = ctx->out_len; return; }
        ctx->out_buf = new_buf;
    }
    memcpy(ctx->out_buf + ctx->out_len, text, len);
    ctx->out_len += len;
    ctx->out_buf[ctx->out_len] = '\0';
}

static void hix_ctx_free(HixCtx *ctx)
{
    if (!ctx) return;
    free(ctx->method); free(ctx->path); free(ctx->query);
    free(ctx->body);   free(ctx->ip);   free(ctx->out_buf);
    free(ctx->content_type);
    free(ctx);
}

/* ── Global context pointer (main-thread only) ──────────────── */

static HixCtx  *s_current_ctx = NULL;
static PHB_ITEM s_pServer     = NULL;
static _Atomic int s_running = 0;
static int      s_listen_fd   = -1;

/* ── HTTP parser ─────────────────────────────────────────────── */

typedef struct {
    char method[16];
    char path[1024];
    char query[4096];
    char body[65536];
    char ip[64];
} ParsedRequest;

static int parse_http(int fd, const char *ip, ParsedRequest *req)
{
    char buf[16384];
    ssize_t n = recv(fd, buf, sizeof(buf)-1, 0);
    if (n <= 0) return -1;
    buf[n] = '\0';

    /* Request line: METHOD SP path SP HTTP/x.x */
    char *p = buf;
    char *sp = memchr(p, ' ', 16);
    if (!sp) return -1;
    int mlen = (int)(sp - p);
    if (mlen >= 16) mlen = 15;
    memcpy(req->method, p, mlen); req->method[mlen] = '\0';

    p = sp + 1;
    sp = memchr(p, ' ', 1100);
    if (!sp) return -1;
    char rawpath[1100];
    int rlen = (int)(sp - p);
    if (rlen >= 1024) rlen = 1023;
    memcpy(rawpath, p, rlen); rawpath[rlen] = '\0';

    char *qp = strchr(rawpath, '?');
    if (qp) {
        strncpy(req->query, qp+1, sizeof(req->query)-1);
        req->query[sizeof(req->query)-1] = '\0';
        *qp = '\0';
    } else {
        req->query[0] = '\0';
    }
    strncpy(req->path, rawpath, sizeof(req->path)-1);
    req->path[sizeof(req->path)-1] = '\0';
    strncpy(req->ip,   ip,      sizeof(req->ip)-1);
    req->ip[sizeof(req->ip)-1] = '\0';

    /* Body (after \r\n\r\n) */
    req->body[0] = '\0';
    char *bstart = strstr(buf, "\r\n\r\n");
    if (bstart) {
        bstart += 4;
        int blen = (int)(n - (bstart - buf));
        if (blen > 0 && blen < (int)sizeof(req->body)) {
            memcpy(req->body, bstart, blen);
            req->body[blen] = '\0';
        }
    }
    return 0;
}

/* ── HTTP response sender ────────────────────────────────────── */

static const char *hix_status_text(int status)
{
    switch (status) {
        case 200: return "OK";
        case 201: return "Created";
        case 204: return "No Content";
        case 301: return "Moved Permanently";
        case 302: return "Found";
        case 304: return "Not Modified";
        case 400: return "Bad Request";
        case 401: return "Unauthorized";
        case 403: return "Forbidden";
        case 404: return "Not Found";
        case 405: return "Method Not Allowed";
        case 500: return "Internal Server Error";
        default:  return "OK";
    }
}

static void send_response(int fd, HixCtx *ctx)
{
    char hdr[512];
    int hlen = snprintf(hdr, sizeof(hdr),
        "HTTP/1.1 %d %s\r\n"
        "Content-Type: %s\r\n"
        "Content-Length: %zu\r\n"
        "Connection: close\r\n"
        "\r\n",
        ctx->status, hix_status_text(ctx->status), ctx->content_type, ctx->out_len);
    send(fd, hdr, hlen, 0);
    if (ctx->out_len > 0)
        send(fd, ctx->out_buf, ctx->out_len, 0);
}

/* ── Harbour dispatch (runs on main thread via dispatch_sync) ── */

static void harbour_dispatch(int client_fd, ParsedRequest *req)
{
    HixCtx *ctx = hix_ctx_new(req->method, req->path, req->query, req->body, req->ip);

    dispatch_sync(dispatch_get_main_queue(), ^{
        s_current_ctx = ctx;
        PHB_DYNS pDynDisp = hb_dynsymFindName("DISPATCH");
        if (s_pServer && pDynDisp) {
            hb_vmPushSymbol( hb_dynsymSymbol(pDynDisp) );
            hb_vmPush( s_pServer );
            hb_vmPushString( req->method, strlen(req->method) );
            hb_vmPushString( req->path,   strlen(req->path)   );
            hb_vmPushString( req->query,  strlen(req->query)  );
            hb_vmPushString( req->body,   strlen(req->body)   );
            hb_vmPushString( req->ip,     strlen(req->ip)     );
            hb_vmSend(5);
        }
        s_current_ctx = NULL;
    });

    send_response(client_fd, ctx);
    hix_ctx_free(ctx);
    close(client_fd);
}

/* ── HB_FUNCs ────────────────────────────────────────────────── */

HB_FUNC( UI_WEBSERVERSTART )
{
    int nPort = hb_parni(1);
    /* param 2: nPortSSL (future HTTPS)  */
    /* param 3: cRoot   (handled in Harbour Dispatch) */
    /* param 4: lTrace  */
    /* param 5: Self (TWebServer object) */

    if (s_pServer) { hb_itemRelease(s_pServer); s_pServer = NULL; }
    PHB_ITEM pSelf = hb_param(5, HB_IT_OBJECT);
    if (pSelf) s_pServer = hb_itemNew(pSelf);

    int lsock = socket(AF_INET, SOCK_STREAM, 0);
    if (lsock < 0) { hb_retl(HB_FALSE); return; }

    int opt = 1;
    setsockopt(lsock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port        = htons(nPort);

    if (bind(lsock, (struct sockaddr*)&addr, sizeof(addr)) < 0 ||
        listen(lsock, 32) < 0) {
        close(lsock);
        hb_retl(HB_FALSE);
        return;
    }

    s_listen_fd = lsock;
    s_running   = 1;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (s_running) {
            struct sockaddr_in caddr;
            socklen_t clen = sizeof(caddr);
            int cfd = accept(s_listen_fd, (struct sockaddr*)&caddr, &clen);
            if (cfd < 0) { if (s_running) continue; break; }

            char ip[64] = "0.0.0.0";
            inet_ntop(AF_INET, &caddr.sin_addr, ip, sizeof(ip));

            __block int  bfd = cfd;
            char *bip = strdup(ip);

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                ParsedRequest req;
                memset(&req, 0, sizeof(req));
                if (parse_http(bfd, bip, &req) == 0) {
                    harbour_dispatch(bfd, &req);
                } else {
                    close(bfd);
                }
                free(bip);
            });
        }
        close(s_listen_fd);
        s_listen_fd = -1;
    });

    if (hb_parl(4)) NSLog(@"[HIX] HTTP server listening on port %d", nPort);
    hb_retl(HB_TRUE);
}

HB_FUNC( UI_WEBSERVERSTOP )
{
    s_running = 0;
    if (s_listen_fd >= 0) { shutdown(s_listen_fd, SHUT_RDWR); }
    if (s_pServer) { hb_itemRelease(s_pServer); s_pServer = NULL; }
    hb_ret();
}

HB_FUNC( UI_WEBSERVERRUNNING )
{
    hb_retl(s_running ? HB_TRUE : HB_FALSE);
}

/* Context readers — called from hix_runtime.prg U* functions */

HB_FUNC( UI_HIX_METHOD ) { hb_retc(s_current_ctx ? s_current_ctx->method : ""); }
HB_FUNC( UI_HIX_PATH   ) { hb_retc(s_current_ctx ? s_current_ctx->path   : ""); }
HB_FUNC( UI_HIX_QUERY  ) { hb_retc(s_current_ctx ? s_current_ctx->query  : ""); }
HB_FUNC( UI_HIX_BODY   ) { hb_retc(s_current_ctx ? s_current_ctx->body   : ""); }
HB_FUNC( UI_HIX_IP     ) { hb_retc(s_current_ctx ? s_current_ctx->ip     : ""); }

HB_FUNC( UI_HIX_WRITE )
{
    if (s_current_ctx && hb_parclen(1) > 0)
        hix_ctx_write(s_current_ctx, hb_parc(1), hb_parclen(1));
    hb_ret();
}

HB_FUNC( UI_HIX_SETSTATUS )
{
    if (s_current_ctx) s_current_ctx->status = hb_parni(1);
    hb_ret();
}

HB_FUNC( UI_HIX_SETCONTENTTYPE )
{
    if (s_current_ctx && hb_parclen(1) > 0) {
        free(s_current_ctx->content_type);
        s_current_ctx->content_type = strdup(hb_parc(1));
    }
    hb_ret();
}

HB_FUNC( UI_HIX_STATUS )
{
    hb_retni(s_current_ctx ? s_current_ctx->status : 200);
}
