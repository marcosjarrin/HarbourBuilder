# TReport Visual Designer (Option B) — Design Spec

## Goal

A visual report designer built on top of the existing HarbourBuilder form designer infrastructure. Users design reports by placing TBand controls on a TForm and TReportField controls inside bands. The result generates portable Harbour code that executes via TPrinter on macOS, Windows, and Linux.

## Architecture

```
IDE (HarbourBuilder)
│
├── Palette → CT_BAND, CT_REPORTFIELD
│
├── TForm (report mode)
│   ├── TBand × N  (auto-stacked, full width)
│   │   └── TReportField × N  (label, data, image, line)
│   └── Inspector → band/field properties and events
│
└── TReport:Print()
    ├── TPrinter:BeginDoc / PrintLine / PrintRect / PrintImage / EndDoc
    └── Backend: NSPrintOperation (macOS) | GDI (Windows) | Cairo (Linux)
```

**Key principle:** TBand and TReportField are standard HarbourBuilder controls. The existing form designer (drag/drop, inspector, code generation, two-way sync) handles them without structural changes. Only TPrinter methods need native implementation per platform.

## Tech Stack

- Harbour OOP: `source/core/classes.prg` — TBand, TReportField, TReport runtime
- Cocoa: `source/backends/cocoa/cocoa_core.m` — HBBand NSView, palette icons, inspector wiring
- Inspector: `source/backends/cocoa/cocoa_inspector.m` — band/field properties and events
- Macros: `include/hbbuilder.ch` — BAND and REPORTFIELD xcommands
- Constants: `include/hbbuilder.ch` — CT_BAND, CT_REPORTFIELD

## Files Created or Modified

| File | Change |
|------|--------|
| `source/core/classes.prg` | Add TBand class; extend TReport:Print() with full rendering loop; extend TReportField:GetValue() |
| `source/backends/cocoa/cocoa_core.m` | Add HBBand NSView, CT_BAND palette entry, UI_BandNew / UI_BandGetType / UI_BandSetType functions |
| `source/backends/cocoa/cocoa_inspector.m` | Add InsPopulateProps/Events cases for CT_BAND and CT_REPORTFIELD |
| `include/hbbuilder.ch` | Add CT_BAND constant, BAND macro, REPORTFIELD macro |
| `source/hbbuilder_macos.prg` | Add CT_BAND/CT_REPORTFIELD to RestoreFormFromCode parser |
| `samples/projects/report/` | New sample: Report1.hbp, Project1.prg, Form1.prg |

---

## Section 1: TBand Control

### Class Definition

```harbour
CLASS TBand FROM TControl
   DATA cBandType         INIT "Detail"   // "Header","PageHeader","Detail","PageFooter","Footer"
   DATA lPrintOnEveryPage INIT .F.        // auto-set .T. for PageHeader/PageFooter
   DATA lVisible          INIT .T.
   DATA nBackColor        INIT -1         // -1 = auto by type
   DATA aFields           INIT {}         // array of TReportField objects

   METHOD New( oParent, cType, nHeight )
   METHOD AddField( oField )
   METHOD RemoveField( nIndex )
   METHOD FieldCount()
   METHOD BandOrder()                     // returns sort order integer for auto-stack
ENDCLASS
```

### Band Type Order (auto-stack)

| Type | Order | lPrintOnEveryPage | Default color |
|------|-------|-------------------|---------------|
| `"Header"` | 1 | .F. | Light blue |
| `"PageHeader"` | 2 | .T. | Light green |
| `"Detail"` | 3 | .F. | White |
| `"PageFooter"` | 4 | .T. | Light green |
| `"Footer"` | 5 | .F. | Light gray |

### Visual Behavior

- Full width of the form at all times (Left=0, Width=form width)
- Top is computed automatically by summing heights of all bands above
- User resizes height by dragging the bottom edge
- Band label (type name) shown centered in the band strip in design mode
- Each band type has a distinct background color for easy identification
- Fields placed inside the band are positioned relative to the band (nTop=0 is the band top)

### Cocoa Implementation (HBBand NSView)

- Subclass of HBControl
- Draws colored background + type label in `drawRect:`
- Responds to child control drop (TReportField drops inside)
- On resize: fires recalcTopOfBands() on parent HBForm to restack all bands

### Inspector Properties

| Property | Type | Category |
|----------|------|----------|
| BandType | Enum (Header/PageHeader/Detail/PageFooter/Footer) | Behavior |
| Height | Integer | Layout |
| PrintOnEveryPage | Logical | Behavior |
| Visible | Logical | Behavior |
| BackColor | Color | Appearance |

### Inspector Events

| Event | Handler signature | When |
|-------|------------------|------|
| OnPrint | `{ || ... }` | Before rendering each band instance |
| OnAfterPrint | `{ || ... }` | After rendering each band instance |

### Generated Code (BAND macro)

```harbour
BAND ::oBand1 TYPE "Header"     OF Self HEIGHT 40
BAND ::oBand2 TYPE "PageHeader" OF Self HEIGHT 24
BAND ::oBand3 TYPE "Detail"     OF Self HEIGHT 20
BAND ::oBand4 TYPE "PageFooter" OF Self HEIGHT 24
BAND ::oBand5 TYPE "Footer"     OF Self HEIGHT 30
```

### hbbuilder.ch macro

```harbour
#xcommand BAND <oVar> TYPE <cType> OF <oParent> HEIGHT <nH> => ;
   <oVar> := TBand():New( <oParent>, <cType>, <nH> )
```

---

## Section 2: TReportField Control

### Class Definition

TReportField already exists in classes.prg. Extensions needed:

```harbour
CLASS TReportField
   // Existing properties (unchanged):
   DATA cName, cText, cFieldName, cExpression, cFormat
   DATA nLeft, nTop, nWidth, nHeight, nAlignment
   DATA cFontName, nFontSize, lBold, lItalic, lUnderline
   DATA nForeColor, nBackColor, nBorderWidth
   DATA cFieldType   // "label", "data", "image", "line"

   // New: parent band reference
   DATA oBand        INIT nil

   // Existing methods (unchanged):
   METHOD New( cName )
   METHOD IsDataBound()
   METHOD GetValue( oDataSource )

   // New: render to TPrinter
   METHOD Render( oPrinter, nBaseY, oDataSource )
ENDCLASS
```

### Field Types

| cFieldType | Key property | Renders via |
|-----------|-------------|------------|
| `"label"` | `cText` — static string | `TPrinter:PrintLine` |
| `"data"` | `cFieldName` or `cExpression` | `TPrinter:PrintLine` with value from datasource |
| `"image"` | `cFieldName` (BLOB) or `cText` (file path) | `TPrinter:PrintImage` |
| `"line"` | `nBorderWidth` — line thickness | `TPrinter:PrintRect` with nHeight=nBorderWidth |

### TReportField:Render( oPrinter, nBaseY, oDataSource )

```harbour
METHOD Render( oPrinter, nBaseY, oDataSource ) CLASS TReportField
   local nAbsY := nBaseY + ::nTop
   local cVal
   do case
   case ::cFieldType == "label"
      oPrinter:PrintLine( nAbsY, ::nLeft, ::cText )
   case ::cFieldType == "data"
      cVal := ::GetValue( oDataSource )
      oPrinter:PrintLine( nAbsY, ::nLeft, cVal )
   case ::cFieldType == "image"
      oPrinter:PrintImage( nAbsY, ::nLeft, ::nWidth, ::nHeight, ::cText )
   case ::cFieldType == "line"
      oPrinter:PrintRect( nAbsY, ::nLeft, ::nWidth, ::nBorderWidth )
   endcase
return nil
```

### Inspector Properties

| Property | Type | Category |
|----------|------|----------|
| FieldType | Enum (label/data/image/line) | Behavior |
| Text | String | Data |
| FieldName | String | Data |
| Expression | String | Data |
| Format | String | Data |
| FontName | String | Appearance |
| FontSize | Integer | Appearance |
| Bold | Logical | Appearance |
| Italic | Logical | Appearance |
| Alignment | Enum (Left/Center/Right) | Appearance |
| ForeColor | Color | Appearance |
| BackColor | Color | Appearance |
| BorderWidth | Integer | Appearance |

### Generated Code (REPORTFIELD macro)

```harbour
REPORTFIELD ::oFld1 TYPE "label" PROMPT "Informe de Ventas" ;
   OF ::oBand1 AT 5, 10 SIZE 180, 16 FONT ".AppleSystemUIFont", 14 BOLD

REPORTFIELD ::oFld2 TYPE "data" FIELD "NAME" ;
   OF ::oBand3 AT 2, 10 SIZE 80, 14

REPORTFIELD ::oFld3 TYPE "data" FIELD "PRICE" FORMAT "999,999.99" ;
   OF ::oBand3 AT 2, 100 SIZE 60, 14 ALIGN 2

REPORTFIELD ::oFld4 TYPE "line" OF ::oBand2 AT 20, 0 SIZE 560, 1
```

### hbbuilder.ch macro

```harbour
#xcommand REPORTFIELD <oVar> TYPE <cType> ;
      [ PROMPT <cText> ] ;
      [ FIELD <cField> ] ;
      [ FORMAT <cFmt> ] ;
      OF <oBand> ;
      AT <nTop>, <nLeft> SIZE <nW> [, <nH>] ;
      [ FONT <cFont> [, <nFSize>] ] ;
      [ BOLD ] [ ITALIC ] ;
      [ ALIGN <nAlign> ] ;
   => ;
   <oVar> := TReportField():New() ; ;
   <oVar>:cFieldType := <cType> ; ;
   [ <oVar>:cText      := <cText> ; ] ;
   [ <oVar>:cFieldName := <cField> ; ] ;
   [ <oVar>:cFormat    := <cFmt> ; ] ;
   <oVar>:nTop    := <nTop> ; <oVar>:nLeft   := <nLeft> ; ;
   <oVar>:nWidth  := <nW>   ; <oVar>:nHeight := <nH> ; ;
   [ <oVar>:cFontName := <cFont> ; <oVar>:nFontSize := <nFSize> ; ] ;
   [ <oVar>:lBold   := .T. ; ] ;
   [ <oVar>:lItalic := .T. ; ] ;
   [ <oVar>:nAlignment := <nAlign> ; ] ;
   <oBand>:AddField( <oVar> )
```

---

## Section 3: TReport:Print() Runtime

### Extended TReport properties

```harbour
CLASS TReport
   // Existing (unchanged):
   DATA oPrinter, cTitle, aBands, aColumns, oDataSource
   DATA aDesignBands, nPageWidth, nPageHeight
   DATA nMarginLeft, nMarginRight, nMarginTop, nMarginBottom

   // New runtime state:
   DATA nCurrentY    INIT 0    // current Y cursor in points
   DATA nCurrentPage INIT 0    // current page number
   DATA nUsableHeight          // computed: nPageHeight - nMarginTop - nMarginBottom
ENDCLASS
```

### TReport:Print() execution loop

```harbour
METHOD Print() CLASS TReport
   local oBand, oField, nBandY

   ::nCurrentPage   := 0
   ::nCurrentY      := ::nMarginTop
   ::nUsableHeight  := ::nPageHeight - ::nMarginTop - ::nMarginBottom

   ::oPrinter:BeginDoc( ::cTitle )
   ::nCurrentPage := 1

   // Header (once)
   ::RenderBand( ::GetDesignBand("Header") )

   // PageHeader (first page)
   ::RenderBand( ::GetDesignBand("PageHeader") )

   // Detail loop
   if ::oDataSource != nil
      ::oDataSource:GoFirst()
      while ! ::oDataSource:Eof()
         oBand := ::GetDesignBand("Detail")
         // Page break check
         if ::nCurrentY + oBand:nHeight > ::nMarginTop + ::nUsableHeight
            ::RenderBand( ::GetDesignBand("PageFooter") )
            ::oPrinter:NewPage()
            ::nCurrentPage++
            ::nCurrentY := ::nMarginTop
            ::RenderBand( ::GetDesignBand("PageHeader") )
         endif
         ::RenderBand( oBand )
         ::oDataSource:Skip()
      enddo
   endif

   // PageFooter + Footer (once at end)
   ::RenderBand( ::GetDesignBand("PageFooter") )
   ::RenderBand( ::GetDesignBand("Footer") )

   ::oPrinter:EndDoc()
return nil

METHOD RenderBand( oBand ) CLASS TReport
   local oField
   if oBand == nil .or. ! oBand:lVisible; return nil; endif
   if oBand:bOnPrint != nil; Eval( oBand:bOnPrint ); endif
   for each oField in oBand:aFields
      oField:Render( ::oPrinter, ::nCurrentY, ::oDataSource )
   next
   ::nCurrentY += oBand:nHeight
   if oBand:bOnAfterPrint != nil; Eval( oBand:bOnAfterPrint ); endif
return nil
```

---

## Section 4: Two-Way Code Sync

### RestoreFormFromCode — new patterns to parse

| Pattern | Action |
|---------|--------|
| `BAND ::oX TYPE "Header" OF Self HEIGHT 40` | Create TBand, set type+height, add to form, restack |
| `REPORTFIELD ::oF TYPE "label" PROMPT "X" OF ::oBand1 AT 5,10 SIZE 80,14` | Create TReportField, assign to band |

### Parsing order in RestoreFormFromCode

1. Parse all `COMPONENT` lines → create non-visual components
2. Parse all `BAND` lines → create and stack bands
3. Parse all `REPORTFIELD` lines → assign fields to their bands
4. Parse event wiring → connect OnPrint / OnAfterPrint / OnClick handlers

### GenerateCode output order

```
// Non-visual components
COMPONENT ::oPrinter1 TYPE CT_PRINTER OF Self
COMPONENT ::oReport1  TYPE CT_REPORT  OF Self
COMPONENT ::oDS1      TYPE CT_DATABASE OF Self

// Bands (sorted by BandOrder)
BAND ::oBand1 TYPE "Header"     OF Self HEIGHT 40
BAND ::oBand2 TYPE "PageHeader" OF Self HEIGHT 24
BAND ::oBand3 TYPE "Detail"     OF Self HEIGHT 20
BAND ::oBand4 TYPE "PageFooter" OF Self HEIGHT 24
BAND ::oBand5 TYPE "Footer"     OF Self HEIGHT 30

// Fields (grouped by band)
REPORTFIELD ::oFld1 TYPE "label" PROMPT "Informe de Ventas" OF ::oBand1 AT 5,10 SIZE 180,16 FONT ".AppleSystemUIFont",14 BOLD
REPORTFIELD ::oFld2 TYPE "data"  FIELD "NAME"  OF ::oBand3 AT 2,10  SIZE 80,14
REPORTFIELD ::oFld3 TYPE "data"  FIELD "PRICE" FORMAT "999,999.99" OF ::oBand3 AT 2,100 SIZE 60,14 ALIGN 2

// Wiring
::oReport1:oPrinter    := ::oPrinter1
::oReport1:oDataSource := ::oDS1
::oBand3:OnPrint       := { || ::OnDetailPrint() }
::oBtnPrint:OnClick    := { || ::OnStartClick()  }
```

---

## Section 5: Sample Project

`samples/projects/report/` — demonstrates all 5 band types with a DBF datasource.

```
Report1.hbp
Project1.prg
Form1.prg
```

**Form layout:**
- TBand Header (height=40): label "Product Inventory", label with date expression
- TBand PageHeader (height=24): column labels (Name, Price, Stock), line separator
- TBand Detail (height=18): data fields NAME, PRICE (formatted), STOCK
- TBand PageFooter (height=20): page number expression
- TBand Footer (height=30): label "End of Report", line separator
- TButton "Print" → OnStartClick() calls TReport:Print()
- TButton "Setup" → OnSetupClick() calls TPrinter:ShowPrintPanel()
- TComboBox for printer selection
- TMemo log for events

**Data:** Creates a test DBF with NAME/PRICE/STOCK on first run if not present.

---

## Out of Scope (v1)

- GroupHeader / GroupFooter bands
- Sub-reports
- Export to Excel/HTML/CSV
- Undo/Redo in designer
- Zoom / rulers
- Calculated summary fields (SUM, COUNT, AVG) — user implements in OnPrint
- Conditional formatting
