/* ======================================================================
 * cocoa_editor.mm — Scintilla-based Code Editor for HbBuilder (macOS)
 *
 * Replaces the previous NSTextView-based editor with Scintilla 5.5.3 +
 * Lexilla (C++ lexer) — the same editing component used by Notepad++,
 * SciTE, Code::Blocks, and many professional IDEs.
 *
 * FEATURES (automatic via Scintilla):
 *   - Syntax highlighting (C++ lexer with Harbour keywords)
 *   - Line numbers with dark gutter
 *   - Code folding with box-style markers
 *   - Indentation guides
 *   - UTF-8 support
 *   - Auto-complete popup (Harbour keywords + functions)
 *   - Built-in find/replace
 *   - Undo/redo
 * ====================================================================== */

#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"
#include "Scintilla.h"
#include "SciLexer.h"
#include "ILexer.h"

/* Harbour VM headers */
#include "hbapi.h"
#include "hbapiitm.h"
#include "hbvm.h"

/* Lexilla CreateLexer (linked statically from liblexilla.a) */
extern "C" Scintilla::ILexer5 * CreateLexer(const char *name);

/* -----------------------------------------------------------------------
 * Helpers
 * ----------------------------------------------------------------------- */

static sptr_t SciMsg( ScintillaView * sv, unsigned int msg, uptr_t wParam, sptr_t lParam )
{
   return [sv message:msg wParam:wParam lParam:lParam];
}

static sptr_t SciMsg0( ScintillaView * sv, unsigned int msg )
{
   return [sv message:msg wParam:0 lParam:0];
}

static sptr_t SCIRGB( int r, int g, int b )
{
   return r | (g << 8) | (b << 16);
}

/* -----------------------------------------------------------------------
 * CODEEDITOR struct
 * ----------------------------------------------------------------------- */

#define CE_MAX_TABS 16

typedef struct {
   NSWindow *       window;
   ScintillaView *  sciView;
   NSSegmentedControl * tabBar;
   NSTextField *    statusBar;        /* Ln/Col/INS status label */
   char           tabNames[CE_MAX_TABS][64];
   char *         tabTexts[CE_MAX_TABS];
   int            nTabs;
   int            nActiveTab;
   PHB_ITEM       pOnTabChange;
} CODEEDITOR;

/* -----------------------------------------------------------------------
 * Harbour-aware code folding
 * Sets fold levels for function/procedure/method/class/if/for/while/switch
 * ----------------------------------------------------------------------- */

static int CE_LineStartsWithCI( const char * line, int lineLen, const char * word )
{
   int i = 0;
   int wLen = (int)strlen(word);
   /* Skip leading whitespace */
   while( i < lineLen && (line[i] == ' ' || line[i] == '\t') ) i++;
   if( i + wLen > lineLen ) return 0;
   if( strncasecmp( line + i, word, wLen ) != 0 ) return 0;
   /* Must be followed by non-identifier char */
   if( i + wLen < lineLen ) {
      char c = line[i + wLen];
      if( (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' || (c >= '0' && c <= '9') )
         return 0;
   }
   return 1;
}

static void CE_UpdateHarbourFolding( ScintillaView * sv )
{
   sptr_t lineCount = SciMsg0( sv, SCI_GETLINECOUNT );
   int level = SC_FOLDLEVELBASE;

   for( sptr_t i = 0; i < lineCount; i++ )
   {
      sptr_t lineLen = SciMsg( sv, SCI_LINELENGTH, (uptr_t)i, 0 );
      int curLevel = level;
      int nextLevel = level;
      int isHeader = 0;

      if( lineLen > 0 && lineLen < 4096 )
      {
         char * buf = (char *) malloc( (size_t)lineLen + 1 );
         SciMsg( sv, SCI_GETLINE, (uptr_t)i, (sptr_t) buf );
         buf[lineLen] = 0;

         /* Trim trailing CR/LF */
         while( lineLen > 0 && (buf[lineLen-1] == '\r' || buf[lineLen-1] == '\n') )
            buf[--lineLen] = 0;

         int ll = (int)lineLen;

         /* Fold openers */
         if( CE_LineStartsWithCI(buf, ll, "function") ||
             CE_LineStartsWithCI(buf, ll, "procedure") ||
             CE_LineStartsWithCI(buf, ll, "method") )
         { isHeader = 1; nextLevel = level + 1; }
         else if( CE_LineStartsWithCI(buf, ll, "class") &&
                  !CE_LineStartsWithCI(buf, ll, "endclass") )
         { isHeader = 1; nextLevel = level + 1; }
         else if( CE_LineStartsWithCI(buf, ll, "if") &&
                  !CE_LineStartsWithCI(buf, ll, "endif") )
         { isHeader = 1; nextLevel = level + 1; }
         else if( CE_LineStartsWithCI(buf, ll, "do") )
         { isHeader = 1; nextLevel = level + 1; }
         else if( CE_LineStartsWithCI(buf, ll, "for") )
         { isHeader = 1; nextLevel = level + 1; }
         else if( CE_LineStartsWithCI(buf, ll, "switch") &&
                  !CE_LineStartsWithCI(buf, ll, "endswitch") )
         { isHeader = 1; nextLevel = level + 1; }
         else if( CE_LineStartsWithCI(buf, ll, "begin") )
         { isHeader = 1; nextLevel = level + 1; }
         else if( CE_LineStartsWithCI(buf, ll, "while") &&
                  !CE_LineStartsWithCI(buf, ll, "enddo") )
         { isHeader = 1; nextLevel = level + 1; }
         else if( CE_LineStartsWithCI(buf, ll, "#pragma begindump") )
         { isHeader = 1; nextLevel = level + 1; }

         /* Fold closers */
         else if( CE_LineStartsWithCI(buf, ll, "return") ||
                  CE_LineStartsWithCI(buf, ll, "endclass") ||
                  CE_LineStartsWithCI(buf, ll, "endif") ||
                  CE_LineStartsWithCI(buf, ll, "enddo") ||
                  CE_LineStartsWithCI(buf, ll, "next") ||
                  CE_LineStartsWithCI(buf, ll, "endswitch") ||
                  CE_LineStartsWithCI(buf, ll, "endcase") ||
                  CE_LineStartsWithCI(buf, ll, "end") ||
                  CE_LineStartsWithCI(buf, ll, "#pragma enddump") )
         {
            if( level > SC_FOLDLEVELBASE )
            { curLevel = level - 1; nextLevel = level - 1; }
         }

         free( buf );
      }

      SciMsg( sv, SCI_SETFOLDLEVEL, (uptr_t)i,
         curLevel | (isHeader ? SC_FOLDLEVELHEADERFLAG : 0) );
      level = nextLevel;
   }
}

/* -----------------------------------------------------------------------
 * Status bar update — Ln X, Col Y | INS | Lines: N | UTF-8
 * ----------------------------------------------------------------------- */

static void CE_UpdateStatusBar( CODEEDITOR * ed )
{
   if( !ed || !ed->sciView || !ed->statusBar ) return;

   sptr_t pos  = SciMsg0( ed->sciView, SCI_GETCURRENTPOS );
   sptr_t line = SciMsg( ed->sciView, SCI_LINEFROMPOSITION, (uptr_t)pos, 0 ) + 1;
   sptr_t col  = SciMsg( ed->sciView, SCI_GETCOLUMN, (uptr_t)pos, 0 ) + 1;
   sptr_t lines = SciMsg0( ed->sciView, SCI_GETLINECOUNT );
   sptr_t chars = SciMsg0( ed->sciView, SCI_GETLENGTH );
   BOOL ovr = SciMsg0( ed->sciView, SCI_GETOVERTYPE ) != 0;

   NSString * text = [NSString stringWithFormat:@"  Ln %ld, Col %ld  |  %s  |  Lines: %ld  |  Chars: %ld  |  UTF-8",
      (long)line, (long)col, ovr ? "OVR" : "INS", (long)lines, (long)chars];
   [ed->statusBar setStringValue:text];
}

/* -----------------------------------------------------------------------
 * Configure Scintilla: lexer, keywords, colours, margins, folding
 * ----------------------------------------------------------------------- */

static void CE_ConfigureScintilla( ScintillaView * sv )
{
   /* UTF-8 */
   SciMsg( sv, SCI_SETCODEPAGE, SC_CP_UTF8, 0 );

   /* Tab width */
   SciMsg( sv, SCI_SETTABWIDTH, 3, 0 );

   /* Set C/C++ lexer via Lexilla (works for Harbour) */
   Scintilla::ILexer5 * pLexer = CreateLexer( "cpp" );
   if( pLexer )
      SciMsg( sv, SCI_SETILEXER, 0, (sptr_t) pLexer );

   /* Default style: Menlo 15pt, light gray on dark */
   SciMsg( sv, SCI_STYLESETFONT, STYLE_DEFAULT, (sptr_t) "Menlo" );
   SciMsg( sv, SCI_STYLESETSIZE, STYLE_DEFAULT, 15 );
   SciMsg( sv, SCI_STYLESETFORE, STYLE_DEFAULT, SCIRGB(212,212,212) );
   SciMsg( sv, SCI_STYLESETBACK, STYLE_DEFAULT, SCIRGB(30,30,30) );
   SciMsg( sv, SCI_STYLECLEARALL, 0, 0 );

   /* Line number margin */
   SciMsg( sv, SCI_SETMARGINTYPEN, 0, SC_MARGIN_NUMBER );
   SciMsg( sv, SCI_SETMARGINWIDTHN, 0, 48 );
   SciMsg( sv, SCI_STYLESETFORE, STYLE_LINENUMBER, SCIRGB(133,133,133) );
   SciMsg( sv, SCI_STYLESETBACK, STYLE_LINENUMBER, SCIRGB(37,37,38) );

   /* Folding margin */
   SciMsg( sv, SCI_SETMARGINTYPEN, 2, SC_MARGIN_SYMBOL );
   SciMsg( sv, SCI_SETMARGINMASKN, 2, SC_MASK_FOLDERS );
   SciMsg( sv, SCI_SETMARGINWIDTHN, 2, 16 );
   SciMsg( sv, SCI_SETMARGINSENSITIVEN, 2, 1 );
   SciMsg( sv, SCI_SETAUTOMATICFOLD,
           SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE, 0 );

   /* Fold markers — box style */
   SciMsg( sv, SCI_MARKERDEFINE, SC_MARKNUM_FOLDER,        SC_MARK_BOXPLUS );
   SciMsg( sv, SCI_MARKERDEFINE, SC_MARKNUM_FOLDEROPEN,    SC_MARK_BOXMINUS );
   SciMsg( sv, SCI_MARKERDEFINE, SC_MARKNUM_FOLDERSUB,     SC_MARK_VLINE );
   SciMsg( sv, SCI_MARKERDEFINE, SC_MARKNUM_FOLDERTAIL,    SC_MARK_LCORNER );
   SciMsg( sv, SCI_MARKERDEFINE, SC_MARKNUM_FOLDEREND,     SC_MARK_BOXPLUSCONNECTED );
   SciMsg( sv, SCI_MARKERDEFINE, SC_MARKNUM_FOLDEROPENMID, SC_MARK_BOXMINUSCONNECTED );
   SciMsg( sv, SCI_MARKERDEFINE, SC_MARKNUM_FOLDERMIDTAIL, SC_MARK_TCORNER );

   for( int m = 25; m <= 31; m++ ) {
      SciMsg( sv, 2041, m, SCIRGB(160,160,160) );  /* SCI_MARKERSETFORE */
      SciMsg( sv, 2042, m, SCIRGB(37,37,38) );     /* SCI_MARKERSETBACK */
   }

   /* Enable folding */
   SciMsg( sv, SCI_SETPROPERTY, (uptr_t) "fold",              (sptr_t) "1" );
   SciMsg( sv, SCI_SETPROPERTY, (uptr_t) "fold.compact",      (sptr_t) "0" );
   SciMsg( sv, SCI_SETPROPERTY, (uptr_t) "fold.comment",      (sptr_t) "1" );
   SciMsg( sv, SCI_SETPROPERTY, (uptr_t) "fold.preprocessor", (sptr_t) "1" );

   /* ===== Harbour keyword lists ===== */
   SciMsg( sv, SCI_SETKEYWORDS, 0, (sptr_t)
      "function procedure return local static private public "
      "if else elseif endif do while enddo for next to step in "
      "switch case otherwise endswitch endcase default "
      "class endclass method data access assign inherit inline "
      "nil self super begin end exit loop with sequence recover "
      "try catch finally true false and or not "
      "init announce request external memvar field parameters "
      "break continue optional redefine "
      "FUNCTION PROCEDURE RETURN LOCAL STATIC PRIVATE PUBLIC "
      "IF ELSE ELSEIF ENDIF DO WHILE ENDDO FOR NEXT TO STEP IN "
      "SWITCH CASE OTHERWISE ENDSWITCH ENDCASE DEFAULT "
      "CLASS ENDCLASS METHOD DATA ACCESS ASSIGN INHERIT INLINE "
      "NIL SELF SUPER BEGIN END EXIT LOOP WITH SEQUENCE RECOVER "
      "TRY CATCH FINALLY TRUE FALSE AND OR NOT "
      "INIT ANNOUNCE REQUEST EXTERNAL MEMVAR FIELD PARAMETERS "
      "BREAK CONTINUE OPTIONAL REDEFINE "
      "Function Procedure Return Local Static Private Public "
      "If Else ElseIf EndIf Do While EndDo For Next To Step In "
      "Switch Case Otherwise EndSwitch EndCase Default "
      "Class EndClass Method Data Access Assign Inherit Inline "
      "Nil Self Super Begin End Exit Loop With Sequence Recover "
      "Try Catch Finally True False And Or Not " );

   SciMsg( sv, SCI_SETKEYWORDS, 1, (sptr_t)
      "DEFINE ACTIVATE FORM TITLE SIZE FONT SIZABLE APPBAR TOOLWINDOW "
      "CENTERED SAY GET BUTTON PROMPT CHECKBOX COMBOBOX GROUPBOX "
      "ITEMS CHECKED DEFAULT CANCEL OF VAR ACTION ON VALID WHEN FROM "
      "TOOLBAR SEPARATOR TOOLTIP MENUBAR POPUP MENUITEM MENUSEPARATOR "
      "PALETTE REQUEST ACCEL BITMAP ICON BROWSE DIALOG "
      "LISTBOX RADIOBUTTON SCROLLBAR PANEL IMAGE SHAPE BEVEL "
      "TREEVIEW LISTVIEW PROGRESSBAR RICHEDIT STATUSBAR SPLITTER "
      "TABS TAB MEMO DATEPICKER SPINNER GAUGE HEADER "
      "REPORT BAND COLUMN PRINTER PREVIEW "
      "WEBVIEW WEBSERVER SOCKET WEBSOCKET HTTPGET HTTPPOST "
      "THREAD MUTEX SEMAPHORE CRITICALSECTION ATOMICOP "
      "OLLAMA OPENAI GEMINI CLAUDE DEEPSEEK TRANSFORMER " );

   /* ===== Syntax highlighting colours ===== */
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_WORD,  SCIRGB(86,156,214) );
   SciMsg( sv, SCI_STYLESETBOLD, SCE_C_WORD,  1 );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_WORD2, SCIRGB(78,201,176) );

   SciMsg( sv, SCI_STYLESETFORE,   SCE_C_COMMENT,     SCIRGB(106,153,85) );
   SciMsg( sv, SCI_STYLESETFORE,   SCE_C_COMMENTLINE,  SCIRGB(106,153,85) );
   SciMsg( sv, SCI_STYLESETFORE,   SCE_C_COMMENTDOC,   SCIRGB(106,153,85) );
   SciMsg( sv, SCI_STYLESETITALIC, SCE_C_COMMENT,     1 );
   SciMsg( sv, SCI_STYLESETITALIC, SCE_C_COMMENTLINE,  1 );

   SciMsg( sv, SCI_STYLESETFORE, SCE_C_STRING,    SCIRGB(206,145,120) );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_CHARACTER,  SCIRGB(206,145,120) );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_NUMBER,     SCIRGB(181,206,168) );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_PREPROCESSOR, SCIRGB(197,134,192) );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_OPERATOR,   SCIRGB(212,212,212) );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_IDENTIFIER, SCIRGB(220,220,220) );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_GLOBALCLASS, SCIRGB(78,201,176) );

   /* Caret and selection */
   SciMsg( sv, SCI_SETCARETFORE, SCIRGB(255,255,255), 0 );
   SciMsg( sv, SCI_SETSELBACK, 1, SCIRGB(38,79,120) );

   /* Line spacing */
   SciMsg( sv, SCI_SETEXTRAASCENT, 1, 0 );
   SciMsg( sv, SCI_SETEXTRADESCENT, 1, 0 );

   /* Indentation guides */
   SciMsg( sv, SCI_SETINDENTATIONGUIDES, SC_IV_LOOKBOTH, 0 );

   /* Bracket matching style */
   SciMsg( sv, SCI_STYLESETFORE, STYLE_BRACELIGHT, SCIRGB(255,255,0) );
   SciMsg( sv, SCI_STYLESETBACK, STYLE_BRACELIGHT, SCIRGB(60,60,60) );
   SciMsg( sv, SCI_STYLESETBOLD, STYLE_BRACELIGHT, 1 );
   SciMsg( sv, SCI_STYLESETFORE, STYLE_BRACEBAD, SCIRGB(255,0,0) );
   SciMsg( sv, SCI_STYLESETBACK, STYLE_BRACEBAD, SCIRGB(60,30,30) );
   SciMsg( sv, SCI_STYLESETBOLD, STYLE_BRACEBAD, 1 );

   /* Bookmarks: markers 0-9 using circles in margin 1 */
   SciMsg( sv, SCI_SETMARGINTYPEN, 1, SC_MARGIN_SYMBOL );
   SciMsg( sv, SCI_SETMARGINWIDTHN, 1, 16 );
   SciMsg( sv, SCI_SETMARGINMASKN, 1, 0x3FF );  /* bits 0-9 */
   SciMsg( sv, SCI_SETMARGINSENSITIVEN, 1, 1 );
   for( int m = 0; m <= 9; m++ ) {
      SciMsg( sv, SCI_MARKERDEFINE, m, SC_MARK_SHORTARROW );
      SciMsg( sv, 2041, m, SCIRGB(80,180,255) );  /* SCI_MARKERSETFORE */
      SciMsg( sv, 2042, m, SCIRGB(40,40,50) );    /* SCI_MARKERSETBACK */
   }
}

/* -----------------------------------------------------------------------
 * Tab bar target
 * ----------------------------------------------------------------------- */

@interface HBSciTabTarget : NSObject
{
@public
   CODEEDITOR * ed;
}
- (void)tabChanged:(id)sender;
@end

@implementation HBSciTabTarget

- (void)tabChanged:(id)sender
{
   if( !ed || !ed->tabBar ) return;
   int newTab = (int)[ed->tabBar selectedSegment];
   if( newTab == ed->nActiveTab ) return;

   /* Save current tab */
   if( ed->nActiveTab >= 0 && ed->nActiveTab < ed->nTabs )
   {
      sptr_t len = SciMsg0( ed->sciView, SCI_GETLENGTH );
      char * buf = (char *) malloc( (size_t)len + 1 );
      SciMsg( ed->sciView, SCI_GETTEXT, (uptr_t)(len + 1), (sptr_t) buf );
      if( ed->tabTexts[ed->nActiveTab] ) free( ed->tabTexts[ed->nActiveTab] );
      ed->tabTexts[ed->nActiveTab] = buf;
   }

   ed->nActiveTab = newTab;

   const char * newText = ed->tabTexts[newTab] ? ed->tabTexts[newTab] : "";
   SciMsg( ed->sciView, SCI_SETTEXT, 0, (sptr_t) newText );
   SciMsg( ed->sciView, SCI_EMPTYUNDOBUFFER, 0, 0 );
   CE_UpdateHarbourFolding( ed->sciView );
   CE_UpdateStatusBar( ed );

   if( ed->pOnTabChange && HB_IS_BLOCK( ed->pOnTabChange ) )
   {
      hb_vmPushEvalSym();
      hb_vmPush( ed->pOnTabChange );
      hb_vmPushNumInt( (HB_PTRUINT) ed );
      hb_vmPushInteger( newTab + 1 );
      hb_vmSend( 2 );
   }
}

@end

static HBSciTabTarget * s_sciTabTarget = nil;

/* -----------------------------------------------------------------------
 * Scintilla notification delegate — auto-indent, fold click
 * ----------------------------------------------------------------------- */

@interface HBSciDelegate : NSObject <ScintillaNotificationProtocol>
{
@public
   CODEEDITOR * ed;
}
@end

@implementation HBSciDelegate

- (void)notification:(SCNotification *)scn
{
   if( !ed || !ed->sciView ) return;

   switch( scn->nmhdr.code )
   {
      case SCN_CHARADDED:
      {
         /* Auto-indent on Enter: copy previous line's indentation */
         if( scn->ch == '\n' || scn->ch == '\r' )
         {
            sptr_t pos = SciMsg0( ed->sciView, SCI_GETCURRENTPOS );
            sptr_t curLine = SciMsg( ed->sciView, SCI_LINEFROMPOSITION, (uptr_t)pos, 0 );
            if( curLine > 0 )
            {
               sptr_t prevIndent = SciMsg( ed->sciView, SCI_GETLINEINDENTATION,
                                           (uptr_t)(curLine - 1), 0 );
               SciMsg( ed->sciView, SCI_SETLINEINDENTATION, (uptr_t)curLine, prevIndent );
               sptr_t indentPos = SciMsg( ed->sciView, SCI_GETLINEINDENTPOSITION,
                                          (uptr_t)curLine, 0 );
               SciMsg( ed->sciView, SCI_GOTOPOS, (uptr_t)indentPos, 0 );
            }
         }
         break;
      }

      case SCN_MARGINCLICK:
      {
         /* Fold/unfold on margin click */
         if( scn->margin == 2 )
         {
            sptr_t line = SciMsg( ed->sciView, SCI_LINEFROMPOSITION,
                                  (uptr_t)scn->position, 0 );
            SciMsg( ed->sciView, SCI_TOGGLEFOLD, (uptr_t)line, 0 );
         }
         break;
      }

      case SCN_UPDATEUI:
      {
         /* Update status bar */
         CE_UpdateStatusBar( ed );

         /* Bracket matching */
         sptr_t pos = SciMsg0( ed->sciView, SCI_GETCURRENTPOS );
         char ch = (char) SciMsg( ed->sciView, SCI_GETCHARAT, (uptr_t)pos, 0 );
         char chPrev = pos > 0 ? (char) SciMsg( ed->sciView, SCI_GETCHARAT, (uptr_t)(pos-1), 0 ) : 0;

         sptr_t bracePos = -1;
         if( ch == '(' || ch == ')' || ch == '[' || ch == ']' || ch == '{' || ch == '}' )
            bracePos = pos;
         else if( chPrev == '(' || chPrev == ')' || chPrev == '[' || chPrev == ']' || chPrev == '{' || chPrev == '}' )
            bracePos = pos - 1;

         if( bracePos >= 0 )
         {
            sptr_t match = SciMsg( ed->sciView, SCI_BRACEMATCH, (uptr_t)bracePos, 0 );
            if( match >= 0 )
               SciMsg( ed->sciView, SCI_BRACEHIGHLIGHT, (uptr_t)bracePos, match );
            else
               SciMsg( ed->sciView, SCI_BRACEBADLIGHT, (uptr_t)bracePos, 0 );
         }
         else
         {
            SciMsg( ed->sciView, SCI_BRACEHIGHLIGHT, (uptr_t)-1, -1 );
         }
         break;
      }

      case SCN_MODIFIED:
      {
         /* Update Harbour folding when text changes */
         if( scn->modificationType & (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT) )
            CE_UpdateHarbourFolding( ed->sciView );
         break;
      }
   }
}

@end

static HBSciDelegate * s_sciDelegate = nil;

/* -----------------------------------------------------------------------
 * Keyboard shortcut subclass — intercepts Cmd+/ Cmd+Shift+D/K Cmd+L Cmd+G
 * ----------------------------------------------------------------------- */

@interface HBSciKeyView : SCIContentView
@end

/* We can't subclass SCIContentView easily (it's internal).
 * Instead, use an NSEvent monitor installed when editor is created. */

/* Auto-complete word list (must be before key monitor that references it) */
static const char * s_harbourAutoComplete =
   "AAdd Access ACopy AClone ADel AEval AFill AIns Alert AllTrim Array "
   "AScan ASize ASort Assign ATail "
   "Begin Break Button "
   "Cancel Case Catch Chr Class ComboBox Continue CToD CurDir "
   "Data Date DateTime Default Define DToC DToS "
   "Else ElseIf Empty End EndCase EndClass EndDo EndIf EndSwitch "
   "Exit External "
   "Field File For Form Function "
   "GroupBox "
   "hb_HGet hb_HHasKey hb_HKeys hb_HNew hb_HSet hb_HValues "
   "hb_MemoRead hb_MemoWrit hb_MilliSeconds hb_ntos hb_NumToHex "
   "hb_threadStart hb_UTF8ToStr hb_ValToStr "
   "HB_ISARRAY HB_ISBLOCK HB_ISDATE HB_ISLOGICAL HB_ISNIL HB_ISNUMERIC HB_ISOBJECT HB_ISSTRING "
   "If In Init Inherit Inline Int "
   "Left Len Local Loop Lower LTrim "
   "Max MenuBar MenuItem MenuSeparator Method Min Mod Month MsgInfo MsgStop MsgYesNo "
   "Next Nil Not "
   "Of Or Otherwise "
   "PadC PadL PadR Palette Private Procedure Prompt Public "
   "Recover Redefine Replicate Request Return Right Round RTrim "
   "Say Self Separator Sequence Size Space Static Step Str SubStr Super Switch "
   "TApplication TButton TCheckBox TComboBox TEdit TForm TGroupBox "
   "Title TLabel TListBox TListView TMemo TPanel TProgressBar "
   "TRadioButton TTabControl TTimer TToolBar TTreeView "
   "To ToolBar Tooltip Transform Trim True Try "
   "Upper "
   "Val ValType Var "
   "While With "
   "Year";

static CODEEDITOR * s_keyMonitorEd = nil;
static id s_keyMonitor = nil;

static void CE_ToggleLineComment( ScintillaView * sv )
{
   sptr_t pos = SciMsg0( sv, SCI_GETCURRENTPOS );
   sptr_t line = SciMsg( sv, SCI_LINEFROMPOSITION, (uptr_t)pos, 0 );
   sptr_t lineStart = SciMsg( sv, SCI_POSITIONFROMLINE, (uptr_t)line, 0 );

   /* Get line text to check if already commented */
   sptr_t lineLen = SciMsg( sv, SCI_LINELENGTH, (uptr_t)line, 0 );
   char * buf = (char *) malloc( (size_t)lineLen + 1 );
   SciMsg( sv, SCI_GETLINE, (uptr_t)line, (sptr_t) buf );
   buf[lineLen] = 0;

   /* Skip leading whitespace */
   int ws = 0;
   while( buf[ws] == ' ' || buf[ws] == '\t' ) ws++;

   if( buf[ws] == '/' && buf[ws+1] == '/' && buf[ws+2] == ' ' )
   {
      /* Remove "// " */
      SciMsg( sv, SCI_SETTARGETSTART, (uptr_t)(lineStart + ws), 0 );
      SciMsg( sv, SCI_SETTARGETEND, (uptr_t)(lineStart + ws + 3), 0 );
      SciMsg( sv, SCI_REPLACETARGET, 0, (sptr_t) "" );
   }
   else if( buf[ws] == '/' && buf[ws+1] == '/' )
   {
      /* Remove "//" (no space) */
      SciMsg( sv, SCI_SETTARGETSTART, (uptr_t)(lineStart + ws), 0 );
      SciMsg( sv, SCI_SETTARGETEND, (uptr_t)(lineStart + ws + 2), 0 );
      SciMsg( sv, SCI_REPLACETARGET, 0, (sptr_t) "" );
   }
   else
   {
      /* Add "// " at start of content */
      SciMsg( sv, SCI_INSERTTEXT, (uptr_t)(lineStart + ws), (sptr_t) "// " );
   }

   free( buf );
}

static void CE_SelectLine( ScintillaView * sv )
{
   sptr_t pos = SciMsg0( sv, SCI_GETCURRENTPOS );
   sptr_t line = SciMsg( sv, SCI_LINEFROMPOSITION, (uptr_t)pos, 0 );
   sptr_t lineStart = SciMsg( sv, SCI_POSITIONFROMLINE, (uptr_t)line, 0 );
   sptr_t lineEnd = SciMsg( sv, SCI_GETLINEENDPOSITION, (uptr_t)line, 0 );
   SciMsg( sv, SCI_SETSEL, (uptr_t)lineStart, lineEnd );
}

static void CE_InstallKeyMonitor( CODEEDITOR * ed )
{
   s_keyMonitorEd = ed;
   if( s_keyMonitor ) return;  /* Already installed */

   s_keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
      handler:^NSEvent *(NSEvent * event)
   {
      if( !s_keyMonitorEd || !s_keyMonitorEd->sciView ) return event;

      /* Only handle when our editor window is key */
      if( [event window] != s_keyMonitorEd->window ) return event;

      NSUInteger flags = [event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
      BOOL cmd   = (flags & NSEventModifierFlagCommand) != 0;
      BOOL shift = (flags & NSEventModifierFlagShift) != 0;
      unsigned short keyCode = [event keyCode];
      ScintillaView * sv = s_keyMonitorEd->sciView;

      /* Cmd+/ (keyCode 44 = /) — Toggle line comment */
      if( cmd && !shift && keyCode == 44 )
      {
         CE_ToggleLineComment( sv );
         return nil;  /* Consumed */
      }

      /* Cmd+Shift+D (keyCode 2 = D) — Duplicate line */
      if( cmd && shift && keyCode == 2 )
      {
         SciMsg( sv, SCI_LINEDUPLICATE, 0, 0 );
         return nil;
      }

      /* Cmd+Shift+K (keyCode 40 = K) — Delete line */
      if( cmd && shift && keyCode == 40 )
      {
         SciMsg( sv, SCI_LINEDELETE, 0, 0 );
         return nil;
      }

      /* Cmd+L (keyCode 37 = L) — Select line */
      if( cmd && !shift && keyCode == 37 )
      {
         CE_SelectLine( sv );
         return nil;
      }

      /* Cmd+G (keyCode 5 = G) — Go to line (prompt via panel) */
      if( cmd && !shift && keyCode == 5 )
      {
         /* Simple goto: use Scintilla's goto line */
         sptr_t lineCount = SciMsg0( sv, SCI_GETLINECOUNT );

         /* Show input dialog */
         NSAlert * alert = [[NSAlert alloc] init];
         [alert setMessageText:@"Go to Line"];
         [alert setInformativeText:[NSString stringWithFormat:@"Line number (1-%ld):",
                                    (long)lineCount]];
         [alert addButtonWithTitle:@"Go"];
         [alert addButtonWithTitle:@"Cancel"];

         NSTextField * input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
         [input setStringValue:@"1"];
         [alert setAccessoryView:input];

         if( [alert runModal] == NSAlertFirstButtonReturn )
         {
            int lineNum = [[input stringValue] intValue];
            if( lineNum >= 1 && lineNum <= (int)lineCount )
            {
               sptr_t pos = SciMsg( sv, SCI_POSITIONFROMLINE, (uptr_t)(lineNum - 1), 0 );
               SciMsg( sv, SCI_GOTOPOS, (uptr_t)pos, 0 );
               SciMsg( sv, SCI_SCROLLCARET, 0, 0 );
            }
         }
         return nil;
      }

      /* Cmd+Space — Auto-complete */
      if( cmd && !shift && keyCode == 49 )
      {
         sptr_t pos = SciMsg0( sv, SCI_GETCURRENTPOS );
         sptr_t wordStart = SciMsg( sv, SCI_WORDSTARTPOSITION, (uptr_t)pos, 1 );
         SciMsg( sv, SCI_AUTOCSETIGNORECASE, 1, 0 );
         SciMsg( sv, SCI_AUTOCSETSEPARATOR, ' ', 0 );
         SciMsg( sv, SCI_AUTOCSHOW, (uptr_t)(pos - wordStart),
                 (sptr_t) s_harbourAutoComplete );
         return nil;
      }

      /* Cmd+0..9 — Toggle bookmark / Cmd+Shift+0..9 — Go to bookmark */
      /* macOS keyCodes: 0=29, 1=18, 2=19, 3=20, 4=21, 5=23, 6=22, 7=26, 8=28, 9=25 */
      {
         static const unsigned short numKeyCodes[] = {29,18,19,20,21,23,22,26,28,25};
         for( int bm = 0; bm <= 9; bm++ )
         {
            if( cmd && keyCode == numKeyCodes[bm] )
            {
               sptr_t curLine = SciMsg( sv, SCI_LINEFROMPOSITION,
                  (uptr_t)SciMsg0( sv, SCI_GETCURRENTPOS ), 0 );

               if( shift )
               {
                  /* Cmd+Shift+N: go to bookmark N */
                  sptr_t found = SciMsg( sv, SCI_MARKERNEXT, 0, 1 << bm );
                  if( found >= 0 )
                  {
                     sptr_t pos = SciMsg( sv, SCI_POSITIONFROMLINE, (uptr_t)found, 0 );
                     SciMsg( sv, SCI_GOTOPOS, (uptr_t)pos, 0 );
                     SciMsg( sv, SCI_SCROLLCARET, 0, 0 );
                  }
               }
               else
               {
                  /* Cmd+N: toggle bookmark N on current line */
                  sptr_t mask = SciMsg( sv, SCI_MARKERGET, (uptr_t)curLine, 0 );
                  if( mask & (1 << bm) )
                     SciMsg( sv, SCI_MARKERDELETE, (uptr_t)curLine, bm );
                  else
                     SciMsg( sv, SCI_MARKERADD, (uptr_t)curLine, bm );
               }
               return nil;
            }
         }
      }

      return event;
   }];
}

/* -----------------------------------------------------------------------
 * HB_FUNC Bridge functions
 * ----------------------------------------------------------------------- */

extern "C" {

/* Ensure NSApp is initialised (defined in cocoa_core.m) */
extern void EnsureNSApp(void);

/* CodeEditorCreate( nLeft, nTop, nWidth, nHeight ) --> hEditor */
HB_FUNC( CODEEDITORCREATE )
{
   EnsureNSApp();

   int nLeft   = hb_parni(1);
   int nTop    = hb_parni(2);
   int nWidth  = hb_parni(3);
   int nHeight = hb_parni(4);

   CODEEDITOR * ed = (CODEEDITOR *) calloc( 1, sizeof(CODEEDITOR) );

   NSRect screenFrame = [[NSScreen mainScreen] frame];
   NSRect frame = NSMakeRect( nLeft, screenFrame.size.height - nTop - nHeight, nWidth, nHeight );
   ed->window = [[NSWindow alloc] initWithContentRect:frame
      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
      backing:NSBackingStoreBuffered defer:NO];
   [ed->window setTitle:@"Code Editor"];
   [ed->window setReleasedWhenClosed:NO];
   [ed->window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];

   NSView * content = [ed->window contentView];
   NSRect contentBounds = [content bounds];
   CGFloat tabBarH = 32;

   /* Tab bar */
   ed->nTabs = 0;
   ed->nActiveTab = 0;
   ed->pOnTabChange = NULL;
   memset( ed->tabTexts, 0, sizeof(ed->tabTexts) );
   ed->tabBar = [NSSegmentedControl segmentedControlWithLabels:@[@"Project1.prg"]
      trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
   [ed->tabBar setSelectedSegment:0];
   [ed->tabBar setFrame:NSMakeRect( 0, contentBounds.size.height - tabBarH,
      contentBounds.size.width, tabBarH )];
   [ed->tabBar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
   [ed->tabBar setFont:[NSFont boldSystemFontOfSize:13]];
   [ed->tabBar setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];
   strncpy( ed->tabNames[0], "Project1.prg", 63 );
   ed->tabTexts[0] = strdup( "" );
   ed->nTabs = 1;

   s_sciTabTarget = [[HBSciTabTarget alloc] init];
   s_sciTabTarget->ed = ed;
   [ed->tabBar setTarget:s_sciTabTarget];
   [ed->tabBar setAction:@selector(tabChanged:)];

   /* Status bar at bottom */
   CGFloat statusH = 22;
   ed->statusBar = [NSTextField labelWithString:@"  Ln 1, Col 1  |  INS  |  Lines: 0  |  UTF-8"];
   [ed->statusBar setFrame:NSMakeRect( 0, 0, contentBounds.size.width, statusH )];
   [ed->statusBar setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
   [ed->statusBar setFont:[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]];
   [ed->statusBar setBackgroundColor:[NSColor colorWithCalibratedRed:0.14 green:0.14 blue:0.15 alpha:1]];
   [ed->statusBar setTextColor:[NSColor colorWithCalibratedRed:0.6 green:0.6 blue:0.6 alpha:1]];
   [ed->statusBar setDrawsBackground:YES];

   /* Scintilla view (between tab bar and status bar) */
   NSRect sciFrame = NSMakeRect( 0, statusH, contentBounds.size.width,
                                 contentBounds.size.height - tabBarH - statusH );
   ed->sciView = [[ScintillaView alloc] initWithFrame:sciFrame];
   [ed->sciView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

   CE_ConfigureScintilla( ed->sciView );

   /* Notification delegate for auto-indent, fold click, status bar */
   s_sciDelegate = [[HBSciDelegate alloc] init];
   s_sciDelegate->ed = ed;
   [ed->sciView setDelegate:s_sciDelegate];

   /* Keyboard shortcut monitor (Cmd+/ Cmd+Shift+D/K Cmd+L Cmd+G Cmd+Space) */
   CE_InstallKeyMonitor( ed );

   [content addSubview:ed->statusBar];
   [content addSubview:ed->sciView];
   [content addSubview:ed->tabBar positioned:NSWindowAbove relativeTo:nil];

   [ed->window orderFront:nil];

   hb_retnint( (HB_PTRUINT) ed );
}

/* CodeEditorSetText( hEditor, cText ) */
HB_FUNC( CODEEDITORSETTEXT )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( ed && ed->sciView && HB_ISCHAR(2) )
   {
      SciMsg( ed->sciView, SCI_SETTEXT, 0, (sptr_t) hb_parc(2) );
      SciMsg( ed->sciView, SCI_EMPTYUNDOBUFFER, 0, 0 );
      CE_UpdateHarbourFolding( ed->sciView );
      CE_UpdateStatusBar( ed );
   }
}

/* CodeEditorGetText( hEditor ) --> cText */
HB_FUNC( CODEEDITORGETTEXT )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( ed && ed->sciView )
   {
      sptr_t len = SciMsg0( ed->sciView, SCI_GETLENGTH );
      char * buf = (char *) malloc( (size_t)len + 1 );
      SciMsg( ed->sciView, SCI_GETTEXT, (uptr_t)(len + 1), (sptr_t) buf );
      hb_retclen( buf, (HB_SIZE)len );
      free( buf );
   }
   else
      hb_retc( "" );
}

/* CodeEditorAppendText( hEditor, cText [, nCursorOffset] ) */
HB_FUNC( CODEEDITORAPPENDTEXT )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( ed && ed->sciView && HB_ISCHAR(2) )
   {
      const char * text = hb_parc(2);
      sptr_t len = SciMsg0( ed->sciView, SCI_GETLENGTH );
      SciMsg( ed->sciView, SCI_APPENDTEXT, (uptr_t)strlen(text), (sptr_t) text );

      sptr_t cursorPos = len + (sptr_t)strlen(text);
      if( HB_ISNUM(3) )
         cursorPos = len + (sptr_t)hb_parni(3);
      SciMsg( ed->sciView, SCI_GOTOPOS, (uptr_t)cursorPos, 0 );
      SciMsg( ed->sciView, SCI_SCROLLCARET, 0, 0 );
      [ed->window makeKeyAndOrderFront:nil];
   }
}

/* CodeEditorGetText2( hEditor ) --> cText (alias) */
HB_FUNC( CODEEDITORGETTEXT2 )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( ed && ed->sciView )
   {
      sptr_t len = SciMsg0( ed->sciView, SCI_GETLENGTH );
      char * buf = (char *) malloc( (size_t)len + 1 );
      SciMsg( ed->sciView, SCI_GETTEXT, (uptr_t)(len + 1), (sptr_t) buf );
      hb_retclen( buf, (HB_SIZE)len );
      free( buf );
   }
   else
      hb_retc( "" );
}

/* CodeEditorGotoFunction( hEditor, cFuncName ) */
HB_FUNC( CODEEDITORGOTOFUNCTION )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( !ed || !ed->sciView || !HB_ISCHAR(2) ) { hb_retl(0); return; }

   const char * funcName = hb_parc(2);
   sptr_t docLen = SciMsg0( ed->sciView, SCI_GETLENGTH );

   char patterns[4][128];
   snprintf( patterns[0], 128, "METHOD %s(", funcName );
   snprintf( patterns[1], 128, "function %s(", funcName );
   snprintf( patterns[2], 128, "METHOD %s (", funcName );
   snprintf( patterns[3], 128, "function %s (", funcName );

   sptr_t found = -1;
   for( int i = 0; i < 4 && found < 0; i++ )
   {
      SciMsg( ed->sciView, SCI_SETTARGETSTART, 0, 0 );
      SciMsg( ed->sciView, SCI_SETTARGETEND, (uptr_t)docLen, 0 );
      SciMsg( ed->sciView, SCI_SETSEARCHFLAGS, SCFIND_NONE, 0 );
      found = SciMsg( ed->sciView, SCI_SEARCHINTARGET,
                      (uptr_t)strlen(patterns[i]), (sptr_t) patterns[i] );
   }

   if( found >= 0 )
   {
      sptr_t line = SciMsg( ed->sciView, SCI_LINEFROMPOSITION, (uptr_t)found, 0 );
      sptr_t pos = SciMsg( ed->sciView, SCI_POSITIONFROMLINE, (uptr_t)(line + 2), 0 );
      SciMsg( ed->sciView, SCI_GOTOPOS, (uptr_t)pos, 0 );
      SciMsg( ed->sciView, SCI_SCROLLCARET, 0, 0 );
      [ed->window makeKeyAndOrderFront:nil];
   }
   hb_retl( found >= 0 );
}

/* CodeEditorInsertAfter( hEditor, cSearchLine, cTextToInsert ) */
HB_FUNC( CODEEDITORINSERTAFTER )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( !ed || !ed->sciView || !HB_ISCHAR(2) || !HB_ISCHAR(3) ) return;

   const char * search = hb_parc(2);
   const char * insert = hb_parc(3);
   sptr_t docLen = SciMsg0( ed->sciView, SCI_GETLENGTH );

   SciMsg( ed->sciView, SCI_SETTARGETSTART, 0, 0 );
   SciMsg( ed->sciView, SCI_SETTARGETEND, (uptr_t)docLen, 0 );
   SciMsg( ed->sciView, SCI_SETSEARCHFLAGS, SCFIND_NONE, 0 );
   sptr_t found = SciMsg( ed->sciView, SCI_SEARCHINTARGET,
                           (uptr_t)strlen(search), (sptr_t) search );

   if( found >= 0 )
   {
      sptr_t line = SciMsg( ed->sciView, SCI_LINEFROMPOSITION, (uptr_t)found, 0 );
      sptr_t nextLine = SciMsg( ed->sciView, SCI_POSITIONFROMLINE, (uptr_t)(line + 1), 0 );
      SciMsg( ed->sciView, SCI_INSERTTEXT, (uptr_t)nextLine, (sptr_t) insert );
   }
}

/* --- Tab management --- */

HB_FUNC( CODEEDITORADDTAB )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( !ed || !ed->tabBar || !HB_ISCHAR(2) || ed->nTabs >= CE_MAX_TABS )
   { hb_retni(0); return; }

   strncpy( ed->tabNames[ed->nTabs], hb_parc(2), 63 );
   ed->tabTexts[ed->nTabs] = strdup( "" );
   ed->nTabs++;

   [ed->tabBar setSegmentCount:ed->nTabs];
   for( int i = 0; i < ed->nTabs; i++ )
      [ed->tabBar setLabel:[NSString stringWithUTF8String:ed->tabNames[i]] forSegment:i];

   hb_retni( ed->nTabs );
}

HB_FUNC( CODEEDITORSETTABTEXT )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   int nTab = hb_parni(2) - 1;
   if( !ed || nTab < 0 || nTab >= ed->nTabs || !HB_ISCHAR(3) ) return;

   if( ed->tabTexts[nTab] ) free( ed->tabTexts[nTab] );
   ed->tabTexts[nTab] = strdup( hb_parc(3) );

   if( nTab == ed->nActiveTab && ed->sciView )
   {
      SciMsg( ed->sciView, SCI_SETTEXT, 0, (sptr_t) ed->tabTexts[nTab] );
      SciMsg( ed->sciView, SCI_EMPTYUNDOBUFFER, 0, 0 );
   }
}

HB_FUNC( CODEEDITORGETTABTEXT )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   int nTab = hb_parni(2) - 1;
   if( !ed || nTab < 0 || nTab >= ed->nTabs ) { hb_retc(""); return; }

   if( nTab == ed->nActiveTab && ed->sciView )
   {
      sptr_t len = SciMsg0( ed->sciView, SCI_GETLENGTH );
      char * buf = (char *) malloc( (size_t)len + 1 );
      SciMsg( ed->sciView, SCI_GETTEXT, (uptr_t)(len + 1), (sptr_t) buf );
      hb_retclen( buf, (HB_SIZE)len );
      free( buf );
   }
   else
      hb_retc( ed->tabTexts[nTab] ? ed->tabTexts[nTab] : "" );
}

HB_FUNC( CODEEDITORSELECTTAB )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   int nTab = hb_parni(2) - 1;
   if( !ed || !ed->tabBar || nTab < 0 || nTab >= ed->nTabs ) return;

   /* Save current tab */
   if( ed->nActiveTab >= 0 && ed->nActiveTab < ed->nTabs && ed->sciView )
   {
      sptr_t len = SciMsg0( ed->sciView, SCI_GETLENGTH );
      char * buf = (char *) malloc( (size_t)len + 1 );
      SciMsg( ed->sciView, SCI_GETTEXT, (uptr_t)(len + 1), (sptr_t) buf );
      if( ed->tabTexts[ed->nActiveTab] ) free( ed->tabTexts[ed->nActiveTab] );
      ed->tabTexts[ed->nActiveTab] = buf;
   }

   ed->nActiveTab = nTab;
   [ed->tabBar setSelectedSegment:nTab];

   const char * newText = ed->tabTexts[nTab] ? ed->tabTexts[nTab] : "";
   SciMsg( ed->sciView, SCI_SETTEXT, 0, (sptr_t) newText );
   SciMsg( ed->sciView, SCI_EMPTYUNDOBUFFER, 0, 0 );
   SciMsg( ed->sciView, SCI_GOTOPOS, 0, 0 );
}

HB_FUNC( CODEEDITORCLEARTABS )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( !ed ) return;

   for( int i = 1; i < ed->nTabs; i++ )
   {
      if( ed->tabTexts[i] ) { free( ed->tabTexts[i] ); ed->tabTexts[i] = NULL; }
      ed->tabNames[i][0] = 0;
   }
   ed->nTabs = 1;
   ed->nActiveTab = 0;
   [ed->tabBar setSegmentCount:1];
}

HB_FUNC( CODEEDITORONTABCHANGE )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   PHB_ITEM pBlock = hb_param(2, HB_IT_BLOCK);
   if( ed )
   {
      if( ed->pOnTabChange ) hb_itemRelease( ed->pOnTabChange );
      ed->pOnTabChange = pBlock ? hb_itemNew( pBlock ) : NULL;
   }
}

HB_FUNC( CODEEDITORBRINGTOFRONT )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( ed && ed->window ) {
      [ed->window makeKeyAndOrderFront:nil];
      [NSApp activateIgnoringOtherApps:YES];
   }
}

HB_FUNC( CODEEDITORDESTROY )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( ed )
   {
      if( ed->window ) [ed->window close];
      for( int i = 0; i < ed->nTabs; i++ )
         if( ed->tabTexts[i] ) free( ed->tabTexts[i] );
      free( ed );
   }
}

/* --- Find Bar --- */

HB_FUNC( CODEEDITORSHOWFINDBAR )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( !ed || !ed->sciView ) return;

   [ed->window makeKeyAndOrderFront:nil];

   /* Use ScintillaView's findAndHighlightText or NSTextFinder */
   BOOL showReplace = HB_ISLOG(2) ? hb_parl(2) : NO;
   NSInteger action = showReplace ? 12 : 1; /* NSTextFinderAction */
   NSMenuItem * item = [[NSMenuItem alloc] initWithTitle:@"Find"
      action:@selector(performTextFinderAction:) keyEquivalent:@""];
   [item setTag:action];

   /* Try the content view first (SCIContentView handles text input) */
   SCIContentView * contentView = [ed->sciView content];
   if( [contentView respondsToSelector:@selector(performTextFinderAction:)] )
      [contentView performTextFinderAction:item];
}

HB_FUNC( CODEEDITORFINDNEXT )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( ed && ed->window ) [ed->window makeKeyAndOrderFront:nil];
}

HB_FUNC( CODEEDITORFINDPREV )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( ed && ed->window ) [ed->window makeKeyAndOrderFront:nil];
}

/* --- Auto-Complete --- */

HB_FUNC( CODEEDITORAUTOCOMPLETE )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( !ed || !ed->sciView ) return;

   [ed->window makeKeyAndOrderFront:nil];

   sptr_t pos = SciMsg0( ed->sciView, SCI_GETCURRENTPOS );
   sptr_t wordStart = SciMsg( ed->sciView, SCI_WORDSTARTPOSITION, (uptr_t)pos, 1 );
   sptr_t wordLen = pos - wordStart;

   SciMsg( ed->sciView, SCI_AUTOCSETIGNORECASE, 1, 0 );
   SciMsg( ed->sciView, SCI_AUTOCSETSEPARATOR, ' ', 0 );
   SciMsg( ed->sciView, SCI_AUTOCSHOW, (uptr_t)wordLen, (sptr_t) s_harbourAutoComplete );
}

/* --- Dark Mode --- */

HB_FUNC( MAC_SETAPPDARKMODE )
{
   BOOL dark = HB_ISLOG(1) ? hb_parl(1) : YES;
   NSString * name = dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua;
   [NSApp setAppearance:[NSAppearance appearanceNamed:name]];
}

HB_FUNC( MAC_SETALLDARKMODE )
{
   BOOL dark = HB_ISLOG(1) ? hb_parl(1) : YES;
   NSString * name = dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua;
   for( NSWindow * win in [NSApp windows] )
      [win setAppearance:[NSAppearance appearanceNamed:name]];
}

HB_FUNC( MAC_SETDARKMODE )
{
   /* Not used with Scintilla editor — dark mode is set app-wide */
   (void) hb_parnint(1);
   (void) hb_parl(2);
}

/* -----------------------------------------------------------------------
 * Clipboard / Undo / Redo — Scintilla SCI_CUT/COPY/PASTE/UNDO/REDO
 * ----------------------------------------------------------------------- */

HB_FUNC( CODEEDITORUNDO )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( ed && ed->sciView ) SciMsg( ed->sciView, SCI_UNDO, 0, 0 );
}

HB_FUNC( CODEEDITORREDO )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( ed && ed->sciView ) SciMsg( ed->sciView, SCI_REDO, 0, 0 );
}

HB_FUNC( CODEEDITORCUT )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( ed && ed->sciView ) SciMsg( ed->sciView, SCI_CUT, 0, 0 );
}

HB_FUNC( CODEEDITORCOPY )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( ed && ed->sciView ) SciMsg( ed->sciView, SCI_COPY, 0, 0 );
}

HB_FUNC( CODEEDITORPASTE )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( ed && ed->sciView ) SciMsg( ed->sciView, SCI_PASTE, 0, 0 );
}

/* CodeEditorFind / CodeEditorReplace — aliases for ShowFindBar */
HB_FUNC( CODEEDITORFIND )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( !ed || !ed->sciView ) return;
   [ed->window makeKeyAndOrderFront:nil];
   NSMenuItem * item = [[NSMenuItem alloc] initWithTitle:@"Find"
      action:@selector(performTextFinderAction:) keyEquivalent:@""];
   [item setTag:1];
   SCIContentView * cv = [ed->sciView content];
   if( [cv respondsToSelector:@selector(performTextFinderAction:)] )
      [cv performTextFinderAction:item];
}

HB_FUNC( CODEEDITORREPLACE )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( !ed || !ed->sciView ) return;
   [ed->window makeKeyAndOrderFront:nil];
   NSMenuItem * item = [[NSMenuItem alloc] initWithTitle:@"Replace"
      action:@selector(performTextFinderAction:) keyEquivalent:@""];
   [item setTag:12];
   SCIContentView * cv = [ed->sciView content];
   if( [cv respondsToSelector:@selector(performTextFinderAction:)] )
      [cv performTextFinderAction:item];
}

/* -----------------------------------------------------------------------
 * Debugger Panel — singleton floating window with 5 tabs
 * ----------------------------------------------------------------------- */

static NSWindow * s_debugPanel = nil;

/* MAC_DebugPanel() — show/create debugger panel */
HB_FUNC( MAC_DEBUGPANEL )
{
   if( s_debugPanel )
   {
      [s_debugPanel makeKeyAndOrderFront:nil];
      return;
   }

   NSRect frame = NSMakeRect( 100, 200, 500, 350 );
   s_debugPanel = [[NSWindow alloc] initWithContentRect:frame
      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
      backing:NSBackingStoreBuffered defer:NO];
   [s_debugPanel setTitle:@"Debugger"];
   [s_debugPanel setReleasedWhenClosed:NO];
   [s_debugPanel setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];

   /* Tab view with 5 tabs */
   NSTabView * tabs = [[NSTabView alloc] initWithFrame:
      [[s_debugPanel contentView] bounds]];
   [tabs setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

   NSString * tabNames[] = { @"Watch", @"Locals", @"Call Stack", @"Breakpoints", @"Output" };
   for( int i = 0; i < 5; i++ )
   {
      NSTabViewItem * item = [[NSTabViewItem alloc] initWithIdentifier:
         [NSString stringWithFormat:@"tab%d", i]];
      [item setLabel:tabNames[i]];

      if( i == 4 )
      {
         /* Output tab: scrollable text view */
         NSScrollView * sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,480,280)];
         [sv setHasVerticalScroller:YES];
         [sv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
         NSTextView * tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0,0,480,280)];
         [tv setEditable:NO];
         [tv setFont:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]];
         [tv setBackgroundColor:[NSColor colorWithCalibratedRed:0.12 green:0.12 blue:0.12 alpha:1]];
         [tv setTextColor:[NSColor colorWithCalibratedRed:0.83 green:0.83 blue:0.83 alpha:1]];
         [sv setDocumentView:tv];
         [item setView:sv];
      }
      else
      {
         /* Table view for Watch/Locals/Call Stack/Breakpoints */
         NSScrollView * sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,480,280)];
         [sv setHasVerticalScroller:YES];
         [sv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
         NSTableView * table = [[NSTableView alloc] initWithFrame:NSMakeRect(0,0,480,280)];

         NSString * cols[3];
         if( i == 0 || i == 1 ) { cols[0]=@"Name"; cols[1]=@"Value"; cols[2]=@"Type"; }
         else if( i == 2 )      { cols[0]=@"Level"; cols[1]=@"Location"; cols[2]=nil; }
         else                   { cols[0]=@"File"; cols[1]=@"Line"; cols[2]=@"Enabled"; }

         for( int c = 0; c < 3 && cols[c]; c++ )
         {
            NSTableColumn * col = [[NSTableColumn alloc] initWithIdentifier:cols[c]];
            [[col headerCell] setStringValue:cols[c]];
            [col setWidth: c==0 ? 140 : (c==1 ? 200 : 100)];
            [table addTableColumn:col];
         }

         [table setHeaderView:[[NSTableHeaderView alloc] init]];
         [table setRowHeight:20];
         [sv setDocumentView:table];
         [item setView:sv];
      }

      [tabs addTabViewItem:item];
   }

   [[s_debugPanel contentView] addSubview:tabs];
   [s_debugPanel makeKeyAndOrderFront:nil];
}

/* -----------------------------------------------------------------------
 * AI Assistant Panel — singleton floating window with Ollama chat
 * ----------------------------------------------------------------------- */

static NSWindow * s_aiPanel = nil;
static NSTextView * s_aiOutput = nil;
static NSTextField * s_aiInput = nil;
static NSPopUpButton * s_aiModelBtn = nil;

@interface HBAISendTarget : NSObject
- (void)sendMessage:(id)sender;
- (void)clearChat:(id)sender;
@end

@implementation HBAISendTarget

- (void)sendMessage:(id)sender
{
   NSString * prompt = [s_aiInput stringValue];
   if( [prompt length] == 0 ) return;

   NSString * model = [s_aiModelBtn titleOfSelectedItem];

   /* Append user message to chat */
   NSString * userMsg = [NSString stringWithFormat:@"\n> %@\n", prompt];
   [[[s_aiOutput textStorage] mutableString] appendString:userMsg];
   [s_aiInput setStringValue:@""];
   [s_aiOutput scrollRangeToVisible:NSMakeRange([[s_aiOutput textStorage] length], 0)];

   /* Call Ollama API asynchronously */
   dispatch_async( dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      NSString * urlStr = @"http://localhost:11434/api/generate";
      NSMutableURLRequest * req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
      [req setHTTPMethod:@"POST"];
      [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

      /* Escape prompt for JSON */
      NSString * escaped = [prompt stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
      escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
      escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];

      NSString * body = [NSString stringWithFormat:
         @"{\"model\":\"%@\",\"prompt\":\"%@\",\"stream\":false}", model, escaped];
      [req setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
      [req setTimeoutInterval:60];

      NSURLResponse * response = nil;
      NSError * error = nil;
      NSData * data = [NSURLConnection sendSynchronousRequest:req
                       returningResponse:&response error:&error];

      dispatch_async( dispatch_get_main_queue(), ^{
         if( error || !data )
         {
            NSString * errMsg = [NSString stringWithFormat:@"\n[Error: %@]\n",
               error ? [error localizedDescription] : @"No data"];
            [[[s_aiOutput textStorage] mutableString] appendString:errMsg];
         }
         else
         {
            NSDictionary * json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString * reply = json[@"response"];
            if( reply )
               [[[s_aiOutput textStorage] mutableString] appendString:
                  [NSString stringWithFormat:@"\n%@\n", reply]];
            else
               [[[s_aiOutput textStorage] mutableString] appendString:@"\n[No response]\n"];
         }
         [s_aiOutput scrollRangeToVisible:NSMakeRange([[s_aiOutput textStorage] length], 0)];
      });
   });
}

- (void)clearChat:(id)sender
{
   [[s_aiOutput textStorage] replaceCharactersInRange:
      NSMakeRange(0, [[s_aiOutput textStorage] length]) withString:@"AI Assistant ready.\n"];
}

@end

static HBAISendTarget * s_aiTarget = nil;

/* MAC_AIAssistantPanel() */
HB_FUNC( MAC_AIASSISTANTPANEL )
{
   if( s_aiPanel )
   {
      [s_aiPanel makeKeyAndOrderFront:nil];
      return;
   }

   NSRect frame = NSMakeRect( 120, 150, 420, 550 );
   s_aiPanel = [[NSWindow alloc] initWithContentRect:frame
      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
      backing:NSBackingStoreBuffered defer:NO];
   [s_aiPanel setTitle:@"AI Assistant (Ollama)"];
   [s_aiPanel setReleasedWhenClosed:NO];
   [s_aiPanel setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];

   NSView * cv = [s_aiPanel contentView];
   CGFloat w = [cv bounds].size.width;
   CGFloat h = [cv bounds].size.height;

   /* Model selector */
   s_aiModelBtn = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, h-35, 200, 28) pullsDown:NO];
   NSArray * models = @[@"codellama", @"llama3", @"deepseek-coder", @"mistral", @"phi3", @"gemma2"];
   for( NSString * m in models ) [s_aiModelBtn addItemWithTitle:m];
   [s_aiModelBtn setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
   [cv addSubview:s_aiModelBtn];

   /* Chat output */
   NSScrollView * sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 50, w-20, h-95)];
   [sv setHasVerticalScroller:YES];
   [sv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
   s_aiOutput = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, w-20, h-95)];
   [s_aiOutput setEditable:NO];
   [s_aiOutput setFont:[NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular]];
   [s_aiOutput setBackgroundColor:[NSColor colorWithCalibratedRed:0.12 green:0.12 blue:0.12 alpha:1]];
   [s_aiOutput setTextColor:[NSColor colorWithCalibratedRed:0.83 green:0.83 blue:0.83 alpha:1]];
   [[s_aiOutput textStorage] replaceCharactersInRange:NSMakeRange(0,0)
      withString:@"AI Assistant ready.\nConnect to Ollama at localhost:11434\n"];
   [sv setDocumentView:s_aiOutput];
   [cv addSubview:sv];

   /* Input + Send + Clear */
   s_aiInput = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 12, w-160, 28)];
   [s_aiInput setPlaceholderString:@"Ask a question..."];
   [s_aiInput setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
   [cv addSubview:s_aiInput];

   s_aiTarget = [[HBAISendTarget alloc] init];

   NSButton * sendBtn = [NSButton buttonWithTitle:@"Send" target:s_aiTarget action:@selector(sendMessage:)];
   [sendBtn setFrame:NSMakeRect(w-140, 12, 60, 28)];
   [sendBtn setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
   [cv addSubview:sendBtn];

   NSButton * clearBtn = [NSButton buttonWithTitle:@"Clear" target:s_aiTarget action:@selector(clearChat:)];
   [clearBtn setFrame:NSMakeRect(w-70, 12, 60, 28)];
   [clearBtn setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
   [cv addSubview:clearBtn];

   [s_aiPanel makeKeyAndOrderFront:nil];
}

/* -----------------------------------------------------------------------
 * Project Inspector — singleton floating window with tree view
 * ----------------------------------------------------------------------- */

static NSWindow * s_projInspector = nil;

/* MAC_ProjectInspector( aItems ) — array of strings, "  " prefix = child */
HB_FUNC( MAC_PROJECTINSPECTOR )
{
   if( s_projInspector )
   {
      [s_projInspector makeKeyAndOrderFront:nil];
      /* TODO: rebuild tree from new array */
      return;
   }

   NSRect frame = NSMakeRect( 80, 250, 260, 400 );
   s_projInspector = [[NSWindow alloc] initWithContentRect:frame
      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
      backing:NSBackingStoreBuffered defer:NO];
   [s_projInspector setTitle:@"Project Inspector"];
   [s_projInspector setReleasedWhenClosed:NO];
   [s_projInspector setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];

   /* Build outline view with items from Harbour array */
   NSScrollView * sv = [[NSScrollView alloc] initWithFrame:
      [[s_projInspector contentView] bounds]];
   [sv setHasVerticalScroller:YES];
   [sv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

   NSOutlineView * outline = [[NSOutlineView alloc] initWithFrame:[sv bounds]];
   NSTableColumn * col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
   [[col headerCell] setStringValue:@"Project"];
   [col setWidth:240];
   [outline addTableColumn:col];
   [outline setOutlineTableColumn:col];
   [outline setHeaderView:nil];  /* No header for tree view look */
   [outline setRowHeight:20];
   [sv setDocumentView:outline];

   [[s_projInspector contentView] addSubview:sv];

   /* Populate from Harbour array if provided */
   /* (For now, uses a static demo layout) */

   [s_projInspector makeKeyAndOrderFront:nil];
}

/* -----------------------------------------------------------------------
 * Editor Colors Dialog — modal dialog to configure Scintilla colors
 * ----------------------------------------------------------------------- */

/* MAC_EditorColorsDialog( hEditor ) — show color settings, apply to Scintilla */
HB_FUNC( MAC_EDITORCOLORSDIALOG )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( !ed || !ed->sciView ) return;

   ScintillaView * sv = ed->sciView;

   /* Preset colours */
   struct { const char * name; sptr_t bg, text, kw, cmd, comment, str, preproc, num, sel; } presets[] = {
      { "Dark",     SCIRGB(30,30,30),    SCIRGB(212,212,212), SCIRGB(86,156,214),
                    SCIRGB(78,201,176),  SCIRGB(106,153,85),  SCIRGB(206,145,120),
                    SCIRGB(197,134,192), SCIRGB(181,206,168), SCIRGB(38,79,120) },
      { "Light",    SCIRGB(255,255,255), SCIRGB(0,0,0),       SCIRGB(0,0,255),
                    SCIRGB(0,128,128),   SCIRGB(0,128,0),     SCIRGB(163,21,21),
                    SCIRGB(128,0,128),   SCIRGB(128,64,0),    SCIRGB(173,214,255) },
      { "Monokai",  SCIRGB(39,40,34),    SCIRGB(248,248,242), SCIRGB(249,38,114),
                    SCIRGB(102,217,239), SCIRGB(117,113,94),  SCIRGB(230,219,116),
                    SCIRGB(166,226,46),  SCIRGB(174,129,255), SCIRGB(73,72,62) },
      { "Solarized",SCIRGB(0,43,54),     SCIRGB(131,148,150), SCIRGB(181,137,0),
                    SCIRGB(42,161,152),  SCIRGB(88,110,117),  SCIRGB(42,161,152),
                    SCIRGB(203,75,22),   SCIRGB(211,54,130),  SCIRGB(7,54,66) },
   };

   /* Create modal alert with preset buttons */
   NSAlert * alert = [[NSAlert alloc] init];
   [alert setMessageText:@"Editor Colors"];
   [alert setInformativeText:@"Choose a color theme for the code editor:"];

   for( int i = 0; i < 4; i++ )
      [alert addButtonWithTitle:[NSString stringWithUTF8String:presets[i].name]];
   [alert addButtonWithTitle:@"Cancel"];

   NSModalResponse resp = [alert runModal];
   int idx = (int)(resp - NSAlertFirstButtonReturn);
   if( idx < 0 || idx >= 4 ) return;  /* Cancel */

   /* Apply selected preset */
   SciMsg( sv, SCI_STYLESETFORE, STYLE_DEFAULT, presets[idx].text );
   SciMsg( sv, SCI_STYLESETBACK, STYLE_DEFAULT, presets[idx].bg );
   SciMsg( sv, SCI_STYLECLEARALL, 0, 0 );

   SciMsg( sv, SCI_STYLESETFORE, STYLE_LINENUMBER, SCIRGB(133,133,133) );
   sptr_t gutterBg = (idx == 1) ? SCIRGB(240,240,240) : SCIRGB(37,37,38);
   SciMsg( sv, SCI_STYLESETBACK, STYLE_LINENUMBER, gutterBg );

   SciMsg( sv, SCI_STYLESETFORE, SCE_C_WORD,  presets[idx].kw );
   SciMsg( sv, SCI_STYLESETBOLD, SCE_C_WORD,  1 );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_WORD2, presets[idx].cmd );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_COMMENT,     presets[idx].comment );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_COMMENTLINE,  presets[idx].comment );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_COMMENTDOC,   presets[idx].comment );
   SciMsg( sv, SCI_STYLESETITALIC, SCE_C_COMMENT,    1 );
   SciMsg( sv, SCI_STYLESETITALIC, SCE_C_COMMENTLINE, 1 );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_STRING,    presets[idx].str );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_CHARACTER,  presets[idx].str );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_NUMBER,     presets[idx].num );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_PREPROCESSOR, presets[idx].preproc );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_OPERATOR,   presets[idx].text );
   SciMsg( sv, SCI_STYLESETFORE, SCE_C_IDENTIFIER, presets[idx].text );

   sptr_t caretClr = (idx == 1) ? SCIRGB(0,0,0) : SCIRGB(255,255,255);
   SciMsg( sv, SCI_SETCARETFORE, caretClr, 0 );
   SciMsg( sv, SCI_SETSELBACK, 1, presets[idx].sel );

   /* Update fold marker colours */
   sptr_t foldFore = (idx == 1) ? SCIRGB(80,80,80) : SCIRGB(160,160,160);
   for( int m = 25; m <= 31; m++ ) {
      SciMsg( sv, 2041, m, foldFore );
      SciMsg( sv, 2042, m, gutterBg );
   }

   [sv setNeedsDisplay:YES];
}

/* -----------------------------------------------------------------------
 * Project Options Dialog — modal dialog with build settings
 * ----------------------------------------------------------------------- */

/* MAC_ProjectOptionsDialog() */
HB_FUNC( MAC_PROJECTOPTIONSDIALOG )
{
   NSAlert * alert = [[NSAlert alloc] init];
   [alert setMessageText:@"Project Options"];
   [alert addButtonWithTitle:@"OK"];
   [alert addButtonWithTitle:@"Cancel"];

   /* Create accessory view with tabs */
   NSTabView * tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 450, 300)];

   /* Tab 1: Harbour */
   NSTabViewItem * t1 = [[NSTabViewItem alloc] initWithIdentifier:@"harbour"];
   [t1 setLabel:@"Harbour"];
   NSView * v1 = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 450, 270)];
   NSTextField * lbl1 = [NSTextField labelWithString:@"Harbour Directory:"];
   [lbl1 setFrame:NSMakeRect(10, 230, 150, 20)];
   NSTextField * hbDir = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 205, 420, 24)];
   [hbDir setStringValue:@"/Users/usuario/harbour"];
   NSTextField * lbl2 = [NSTextField labelWithString:@"Compiler Flags:"];
   [lbl2 setFrame:NSMakeRect(10, 175, 150, 20)];
   NSTextField * hbFlags = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 150, 420, 24)];
   [hbFlags setStringValue:@"-n -w -q"];
   [v1 addSubview:lbl1]; [v1 addSubview:hbDir];
   [v1 addSubview:lbl2]; [v1 addSubview:hbFlags];
   [t1 setView:v1];

   /* Tab 2: C Compiler */
   NSTabViewItem * t2 = [[NSTabViewItem alloc] initWithIdentifier:@"compiler"];
   [t2 setLabel:@"C Compiler"];
   NSView * v2 = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 450, 270)];
   NSTextField * lbl3 = [NSTextField labelWithString:@"Compiler:"];
   [lbl3 setFrame:NSMakeRect(10, 230, 150, 20)];
   NSTextField * ccName = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 205, 420, 24)];
   [ccName setStringValue:@"clang"];
   NSTextField * lbl4 = [NSTextField labelWithString:@"Flags:"];
   [lbl4 setFrame:NSMakeRect(10, 175, 150, 20)];
   NSTextField * ccFlags = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 150, 420, 24)];
   [ccFlags setStringValue:@"-O2 -fobjc-arc"];
   [v2 addSubview:lbl3]; [v2 addSubview:ccName];
   [v2 addSubview:lbl4]; [v2 addSubview:ccFlags];
   [t2 setView:v2];

   /* Tab 3: Linker */
   NSTabViewItem * t3 = [[NSTabViewItem alloc] initWithIdentifier:@"linker"];
   [t3 setLabel:@"Linker"];
   NSView * v3 = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 450, 270)];
   NSTextField * lbl5 = [NSTextField labelWithString:@"Linker Flags:"];
   [lbl5 setFrame:NSMakeRect(10, 230, 150, 20)];
   NSTextField * ldFlags = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 205, 420, 24)];
   [ldFlags setStringValue:@"-framework Cocoa -framework QuartzCore"];
   NSTextField * lbl6 = [NSTextField labelWithString:@"Libraries:"];
   [lbl6 setFrame:NSMakeRect(10, 175, 150, 20)];
   NSTextField * libs = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 150, 420, 24)];
   [libs setStringValue:@"-lhbvm -lhbrtl -lhbcommon -lhbcpage"];
   [v3 addSubview:lbl5]; [v3 addSubview:ldFlags];
   [v3 addSubview:lbl6]; [v3 addSubview:libs];
   [t3 setView:v3];

   /* Tab 4: Directories */
   NSTabViewItem * t4 = [[NSTabViewItem alloc] initWithIdentifier:@"dirs"];
   [t4 setLabel:@"Directories"];
   NSView * v4 = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 450, 270)];
   NSTextField * lbl7 = [NSTextField labelWithString:@"Project Directory:"];
   [lbl7 setFrame:NSMakeRect(10, 230, 150, 20)];
   NSTextField * projDir = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 205, 420, 24)];
   [projDir setStringValue:@"."];
   NSTextField * lbl8 = [NSTextField labelWithString:@"Output Directory:"];
   [lbl8 setFrame:NSMakeRect(10, 175, 150, 20)];
   NSTextField * outDir = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 150, 420, 24)];
   [outDir setStringValue:@"/tmp/hbbuilder_build"];
   NSTextField * lbl9 = [NSTextField labelWithString:@"Include Paths:"];
   [lbl9 setFrame:NSMakeRect(10, 120, 150, 20)];
   NSTextField * incPaths = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 95, 420, 24)];
   [incPaths setStringValue:@"/Users/usuario/harbour/include"];
   [v4 addSubview:lbl7]; [v4 addSubview:projDir];
   [v4 addSubview:lbl8]; [v4 addSubview:outDir];
   [v4 addSubview:lbl9]; [v4 addSubview:incPaths];
   [t4 setView:v4];

   [tabs addTabViewItem:t1];
   [tabs addTabViewItem:t2];
   [tabs addTabViewItem:t3];
   [tabs addTabViewItem:t4];

   [alert setAccessoryView:tabs];
   [alert runModal];
}

} /* extern "C" */
