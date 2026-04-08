// gen_palette.prg - Generate palette icons
// Compile: build_cpp.bat gen_palette
// Run: gen_palette.exe

#include "../include/hbbuilder.ch"

REQUEST HB_GT_GUI_DEFAULT

function Main()
   GenPaletteIcons()
return nil

#pragma BEGINDUMP

#include <hbapi.h>
#include <windows.h>
#include <stdio.h>

#define ICON_SIZE 32
#define N_ICONS 109

HB_FUNC( GENPALETTEICONS )
{
   static const char * abbrs[] = {
      "A","ab","M","Btn","Ck","Rd","Ls","Cb","Gp","Pn","SB",
      "BB","Sp","Im","Sh","Bv","Mk","SG","SB","ST","LE",
      "Tb","TV","LV","PB","RE","TK","UD","DT","MC",
      "Tm","Px",
      "Op","Sv","Ft","Cl","Fn","Rp",
      "DB","My","Mr","Pg","SL","Fb","MS","Or","Mg",
      "Bw","DG","DN","DT","DE","DC","DK","DI",
      "Pr","Rp","Lb","PP","PS","PD","RV","BP",
      "Wb","WS","Wk","HT","FT","SM","TS","TC","UD",
      "PP","Sc","Rp","BC","PD","XL","Au","Pm","Cu","Tx","Ds","Sh",
      "Th","Mx","Se","CS","TP","At","CV","Ch",
      "OA","Gm","Cl","DS","Gk","Ol","Tf"
   };
   static COLORREF colors[] = {
      0xDB9834,0xDB9834,0xDB9834,0xDB9834,0xDB9834,0xDB9834,0xDB9834,0xDB9834,0xDB9834,0xDB9834,0xDB9834,
      0xB6599B,0xB6599B,0xB6599B,0xB6599B,0xB6599B,0xB6599B,0xB6599B,0xB6599B,0xB6599B,0xB6599B,
      0x71CC2E,0x71CC2E,0x71CC2E,0x71CC2E,0x71CC2E,0x71CC2E,0x71CC2E,0x71CC2E,0x71CC2E,
      0x0FC4F1,0x0FC4F1,
      0x227EE6,0x227EE6,0x227EE6,0x227EE6,0x227EE6,0x227EE6,
      0x3C4CE7,0x3C4CE7,0x3C4CE7,0x3C4CE7,0x3C4CE7,0x3C4CE7,0x3C4CE7,0x3C4CE7,0x3C4CE7,
      0x2B39C0,0x2B39C0,0x2B39C0,0x2B39C0,0x2B39C0,0x2B39C0,0x2B39C0,0x2B39C0,
      0x8D8C7F,0x8D8C7F,0x8D8C7F,0x8D8C7F,0x8D8C7F,0x8D8C7F,0x8D8C7F,0x8D8C7F,
      0x9CBC1A,0x9CBC1A,0x9CBC1A,0x9CBC1A,0x9CBC1A,0x9CBC1A,0x9CBC1A,0x9CBC1A,0x9CBC1A,
      0xAD448E,0xAD448E,0xAD448E,0xAD448E,0xAD448E,0xAD448E,0xAD448E,0xAD448E,0xAD448E,0xAD448E,0xAD448E,0xAD448E,
      0x503E2C,0x503E2C,0x503E2C,0x503E2C,0x503E2C,0x503E2C,0x503E2C,0x503E2C,
      0x129CF3,0x129CF3,0x129CF3,0x129CF3,0x129CF3,0x129CF3,0x129CF3
   };

   int totalW = N_ICONS * ICON_SIZE;
   HDC hScreenDC, hMemDC;
   HBITMAP hBmp, hOldBmp;
   BITMAPFILEHEADER bf;
   BITMAPINFOHEADER bi;
   int i, dataSize, rowBytes;
   void * pBits;
   FILE * fp;
   HFONT hFont, hOldFont;
   LOGFONTA lf;

   hScreenDC = GetDC(NULL);
   hMemDC = CreateCompatibleDC(hScreenDC);

   memset(&bi,0,sizeof(bi));
   bi.biSize = sizeof(bi);
   bi.biWidth = totalW;
   bi.biHeight = ICON_SIZE;
   bi.biPlanes = 1;
   bi.biBitCount = 24;

   hBmp = CreateDIBSection(hMemDC,(BITMAPINFO*)&bi,DIB_RGB_COLORS,&pBits,NULL,0);
   hOldBmp = (HBITMAP)SelectObject(hMemDC,hBmp);

   { RECT rc; HBRUSH hBr;
     rc.left=0; rc.top=0; rc.right=totalW; rc.bottom=ICON_SIZE;
     hBr = CreateSolidBrush(RGB(255,0,255));
     FillRect(hMemDC,&rc,hBr); DeleteObject(hBr); }

   memset(&lf,0,sizeof(lf));
   lf.lfHeight = -11; lf.lfWeight = FW_BOLD;
   lf.lfCharSet = DEFAULT_CHARSET;
   lstrcpyA(lf.lfFaceName,"Segoe UI");
   hFont = CreateFontIndirectA(&lf);
   hOldFont = (HFONT)SelectObject(hMemDC,hFont);
   SetBkMode(hMemDC,TRANSPARENT);
   SetTextColor(hMemDC,RGB(255,255,255));

   for(i = 0; i < N_ICONS; i++)
   {
      int x = i * ICON_SIZE;
      RECT rcI, rcT;
      HBRUSH hBr; HPEN hPen;
      COLORREF bg = colors[i];
      int r,g,b;

      rcI.left=x+1; rcI.top=1; rcI.right=x+ICON_SIZE-1; rcI.bottom=ICON_SIZE-1;
      rcT.left=x+2; rcT.top=7; rcT.right=x+ICON_SIZE-2; rcT.bottom=ICON_SIZE-4;

      r=GetRValue(bg); g=GetGValue(bg); b=GetBValue(bg);
      if(r>40) r-=40; else r=0;
      if(g>40) g-=40; else g=0;
      if(b>40) b-=40; else b=0;

      hBr = CreateSolidBrush(bg);
      hPen = CreatePen(PS_SOLID,1,RGB(r,g,b));
      SelectObject(hMemDC,hBr); SelectObject(hMemDC,hPen);
      RoundRect(hMemDC, rcI.left, rcI.top, rcI.right, rcI.bottom, 6, 6);
      DeleteObject(hBr); DeleteObject(hPen);

      DrawTextA(hMemDC, abbrs[i], -1, &rcT, DT_CENTER|DT_VCENTER|DT_SINGLELINE);
   }

   SelectObject(hMemDC,hOldFont); DeleteObject(hFont);

   rowBytes = ((totalW * 3 + 3) & ~3);
   dataSize = rowBytes * ICON_SIZE;

   memset(&bf,0,sizeof(bf));
   bf.bfType = 0x4D42;
   bf.bfSize = sizeof(bf) + sizeof(bi) + dataSize;
   bf.bfOffBits = sizeof(bf) + sizeof(bi);

   { char szPath[MAX_PATH];
     GetModuleFileNameA(NULL, szPath, MAX_PATH);
     { char * p = strrchr(szPath, '\\'); if(p) *p = 0; }
     lstrcatA(szPath, "\\palette_new.bmp");
     fp = fopen(szPath,"wb");
     if(fp) {
        fwrite(&bf,sizeof(bf),1,fp);
        fwrite(&bi,sizeof(bi),1,fp);
        fwrite(pBits,dataSize,1,fp);
        fclose(fp);
        { char msg[300]; sprintf(msg, "Generated: %s\n109 icons, 32x32", szPath);
          MessageBoxA(NULL, msg, "Palette Icons", MB_OK|MB_ICONINFORMATION); }
     } else {
        MessageBoxA(NULL,"Error creating file!","Error",MB_OK|MB_ICONERROR);
     }
   }

   SelectObject(hMemDC,hOldBmp); DeleteObject(hBmp);
   DeleteDC(hMemDC); ReleaseDC(NULL,hScreenDC);
}

#pragma ENDDUMP
