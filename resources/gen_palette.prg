// gen_palette.prg - Generate professional palette icon strip
// Compile: build_cpp.bat gen_palette (from samples/)
// Run: gen_palette.exe -> creates ../resources/palette_new.bmp

#include "../include/hbbuilder.ch"

REQUEST HB_GT_GUI_DEFAULT

function Main()
   GenPaletteIcons()
return nil

#pragma BEGINDUMP

#include <hbapi.h>
#include <windows.h>
#include <stdio.h>
#include <math.h>

#define ICON_SIZE 32
#define ICON_COUNT 109

typedef struct { const char * abbr; DWORD bgColor; } ICONINFO;

HB_FUNC( GENPALETTEICONS )
{
   /* Colors by category - modern flat design palette */
   #define C_STD  RGB(52,152,219)   /* Blue - Standard */
   #define C_ADD  RGB(155,89,182)   /* Purple - Additional */
   #define C_NAT  RGB(46,204,113)   /* Green - Native */
   #define C_SYS  RGB(241,196,15)   /* Amber - System */
   #define C_DLG  RGB(230,126,34)   /* Orange - Dialogs */
   #define C_DBA  RGB(231,76,60)    /* Red - Data Access */
   #define C_DBC  RGB(192,57,43)    /* Dark Red - Data Controls */
   #define C_PRN  RGB(127,140,141)  /* Slate - Printing */
   #define C_NET  RGB(26,188,156)   /* Teal - Internet */
   #define C_ERP  RGB(142,68,173)   /* Violet - ERP */
   #define C_THR  RGB(44,62,80)     /* Navy - Threading */
   #define C_AI   RGB(243,156,18)   /* Gold - AI */

   static ICONINFO icons[ICON_COUNT] = {
      /* Standard (11) */
      {"A",C_STD},{"ab",C_STD},{"M",C_STD},{"Btn",C_STD},
      {"Ck",C_STD},{"Rd",C_STD},{"Ls",C_STD},{"Cb",C_STD},
      {"Gp",C_STD},{"Pn",C_STD},{"SB",C_STD},
      /* Additional (10) */
      {"BB",C_ADD},{"Sp",C_ADD},{"Im",C_ADD},{"Sh",C_ADD},
      {"Bv",C_ADD},{"Mk",C_ADD},{"SG",C_ADD},{"SB",C_ADD},
      {"ST",C_ADD},{"LE",C_ADD},
      /* Native (9) */
      {"Tb",C_NAT},{"TV",C_NAT},{"LV",C_NAT},{"PB",C_NAT},
      {"RE",C_NAT},{"TK",C_NAT},{"UD",C_NAT},{"DT",C_NAT},
      {"MC",C_NAT},
      /* System (2) */
      {"Tm",C_SYS},{"Px",C_SYS},
      /* Dialogs (6) */
      {"Op",C_DLG},{"Sv",C_DLG},{"Ft",C_DLG},{"Cl",C_DLG},
      {"Fn",C_DLG},{"Rp",C_DLG},
      /* Data Access (9) */
      {"DB",C_DBA},{"My",C_DBA},{"Mr",C_DBA},{"Pg",C_DBA},
      {"SL",C_DBA},{"Fb",C_DBA},{"MS",C_DBA},{"Or",C_DBA},
      {"Mg",C_DBA},
      /* Data Controls (8) */
      {"Bw",C_DBC},{"DG",C_DBC},{"DN",C_DBC},{"DT",C_DBC},
      {"DE",C_DBC},{"DC",C_DBC},{"DK",C_DBC},{"DI",C_DBC},
      /* Printing (8) */
      {"Pr",C_PRN},{"Rp",C_PRN},{"Lb",C_PRN},{"PP",C_PRN},
      {"PS",C_PRN},{"PD",C_PRN},{"RV",C_PRN},{"BP",C_PRN},
      /* Internet (9) */
      {"Wb",C_NET},{"WS",C_NET},{"Wk",C_NET},{"HT",C_NET},
      {"FT",C_NET},{"SM",C_NET},{"TS",C_NET},{"TC",C_NET},
      {"UD",C_NET},
      /* ERP (12) */
      {"PP",C_ERP},{"Sc",C_ERP},{"Rp",C_ERP},{"BC",C_ERP},
      {"PD",C_ERP},{"XL",C_ERP},{"Au",C_ERP},{"Pm",C_ERP},
      {"Cu",C_ERP},{"Tx",C_ERP},{"Ds",C_ERP},{"Sh",C_ERP},
      /* Threading (8) */
      {"Th",C_THR},{"Mx",C_THR},{"Se",C_THR},{"CS",C_THR},
      {"TP",C_THR},{"At",C_THR},{"CV",C_THR},{"Ch",C_THR},
      /* AI (7) */
      {"OA",C_AI},{"Gm",C_AI},{"Cl",C_AI},{"DS",C_AI},
      {"Gk",C_AI},{"Ol",C_AI},{"Tf",C_AI}
   };

   int totalW = ICON_COUNT * ICON_SIZE;
   HDC hScreenDC, hMemDC;
   HBITMAP hBmp, hOldBmp;
   BITMAPFILEHEADER bf;
   BITMAPINFOHEADER bi;
   int i, dataSize, rowBytes;
   void * pBits;
   FILE * fp;
   HFONT hFont, hOldFont;
   LOGFONTA lf = {0};

   printf("Generating %d icons at %dx%d...\n", ICON_COUNT, ICON_SIZE, ICON_SIZE);

   hScreenDC = GetDC(NULL);
   hMemDC = CreateCompatibleDC(hScreenDC);

   memset(&bi,0,sizeof(bi));
   bi.biSize = sizeof(bi);
   bi.biWidth = totalW;
   bi.biHeight = ICON_SIZE;
   bi.biPlanes = 1;
   bi.biBitCount = 24;
   bi.biCompression = BI_RGB;

   hBmp = CreateDIBSection(hMemDC,(BITMAPINFO*)&bi,DIB_RGB_COLORS,&pBits,NULL,0);
   hOldBmp = (HBITMAP)SelectObject(hMemDC,hBmp);

   /* Fill with magenta (transparency key) */
   { RECT rc = {0,0,totalW,ICON_SIZE};
     HBRUSH hBr = CreateSolidBrush(RGB(255,0,255));
     FillRect(hMemDC,&rc,hBr); DeleteObject(hBr); }

   /* Bold font */
   lf.lfHeight = -11; lf.lfWeight = FW_BOLD;
   lf.lfCharSet = DEFAULT_CHARSET; lf.lfQuality = CLEARTYPE_QUALITY;
   lstrcpyA(lf.lfFaceName,"Segoe UI");
   hFont = CreateFontIndirectA(&lf);
   hOldFont = (HFONT)SelectObject(hMemDC,hFont);
   SetBkMode(hMemDC,TRANSPARENT);
   SetTextColor(hMemDC,RGB(255,255,255));

   for(i = 0; i < ICON_COUNT; i++)
   {
      int x = i * ICON_SIZE;
      RECT rcIcon = {x+1, 1, x+ICON_SIZE-1, ICON_SIZE-1};
      RECT rcText = {x+2, 7, x+ICON_SIZE-2, ICON_SIZE-4};
      HBRUSH hBr;
      HPEN hPen;
      int r,g,b;

      /* Darker border */
      r = GetRValue(icons[i].bgColor); g = GetGValue(icons[i].bgColor); b = GetBValue(icons[i].bgColor);
      r = r > 40 ? r-40 : 0; g = g > 40 ? g-40 : 0; b = b > 40 ? b-40 : 0;

      hBr = CreateSolidBrush(icons[i].bgColor);
      hPen = CreatePen(PS_SOLID,1,RGB(r,g,b));
      SelectObject(hMemDC,hBr); SelectObject(hMemDC,hPen);
      RoundRect(hMemDC, rcIcon.left, rcIcon.top, rcIcon.right, rcIcon.bottom, 6, 6);
      DeleteObject(hBr); DeleteObject(hPen);

      /* White abbreviation text */
      DrawTextA(hMemDC, icons[i].abbr, -1, &rcText,
         DT_CENTER|DT_VCENTER|DT_SINGLELINE|DT_NOPREFIX);
   }

   SelectObject(hMemDC,hOldFont); DeleteObject(hFont);

   /* Write BMP */
   rowBytes = ((totalW * 3 + 3) & ~3);
   dataSize = rowBytes * ICON_SIZE;

   memset(&bf,0,sizeof(bf));
   bf.bfType = 0x4D42;
   bf.bfSize = sizeof(bf) + sizeof(bi) + dataSize;
   bf.bfOffBits = sizeof(bf) + sizeof(bi);

   fp = fopen("..\\resources\\palette_new.bmp","wb");
   if(fp) {
      fwrite(&bf,sizeof(bf),1,fp);
      fwrite(&bi,sizeof(bi),1,fp);
      fwrite(pBits,dataSize,1,fp);
      fclose(fp);
      printf("Written: resources/palette_new.bmp (%d bytes, %d icons)\n",
         bf.bfSize, ICON_COUNT);
      MessageBoxA(NULL,"palette_new.bmp generated successfully!\n\n"
         "Rename to palette.bmp to use in the IDE.",
         "Palette Icon Generator",MB_OK|MB_ICONINFORMATION);
   }

   SelectObject(hMemDC,hOldBmp); DeleteObject(hBmp);
   DeleteDC(hMemDC); ReleaseDC(NULL,hScreenDC);
}

#pragma ENDDUMP
