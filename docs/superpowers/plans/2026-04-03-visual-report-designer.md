# Visual Report Designer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a visual report designer for HarbourBuilder that lets users design reports with drag-and-drop bands (Header, Detail, Footer, Group), place labels/fields/images/shapes, bind to TDatabase/TDataSource, preview in a window, and print — all integrated with the existing Object Inspector.

**Architecture:** The report designer is a specialized form designer. A `TReportDesigner` window renders horizontal bands as colored strips. Users drop fields/labels into bands from the palette or inspector. Each band and field has properties editable in the Object Inspector. Two-way code sync generates `METHOD CreateReport()` just like form designer generates `METHOD CreateForm()`. Preview renders the report in a scrollable GtkDrawingArea using Cairo.

**Tech Stack:** Harbour OOP (classes.prg), C/GTK3 (gtk3_core.c) for the designer window and Cairo preview, existing Object Inspector integration, existing TDatabase/TDataSource for data binding.

---

## File Structure

| File | Responsibility |
|------|---------------|
| `harbour/classes.prg` | Modify: add TReportBand, TReportField, extend TReport with visual design data |
| `backends/gtk3/gtk3_report_designer.c` | Create: GTK3 report designer window — band rendering, drag/drop fields, selection handles, Cairo drawing |
| `backends/gtk3/gtk3_core.c` | Modify: add CT_REPORTBAND/CT_REPORTFIELD defines, register report designer HB_FUNCs |
| `samples/hbbuilder_linux.prg` | Modify: wire "Design Report" menu/action, report code generation |
| `harbour/hbbuilder.ch` | Modify: add xcommand macros for DEFINE REPORT, DEFINE BAND, REPORT FIELD |
| `samples/projects/printing/report_designer_example.prg` | Create: example using the visual report designer |
| `tests/test_report.prg` | Create: unit tests for report band/field management |

---

### Task 1: Report Data Model (TReportBand + TReportField classes)

**Files:**
- Modify: `harbour/classes.prg` (append after TReport)
- Create: `tests/test_report.prg`

- [ ] **Step 1: Write the failing test**

```harbour
// tests/test_report.prg
#include "../harbour/hbbuilder.ch"

REQUEST DBFCDX

static nTests := 0, nPassed := 0, nFailed := 0

function Main()
   ? "=== Report Designer Unit Tests ==="
   ?

   TestGroup( "Report Band Model" )
   Test_CreateBand()
   Test_AddFieldToBand()
   Test_BandProperties()

   TestGroup( "Report Field Model" )
   Test_FieldProperties()
   Test_FieldDataBinding()

   TestGroup( "Report with Bands" )
   Test_ReportAddBands()
   Test_ReportGenerateCode()

   ?
   ? "Results: " + LTrim(Str(nPassed)) + " passed, " + LTrim(Str(nFailed)) + " failed"
   if nFailed > 0; ? "SOME TESTS FAILED"; else; ? "ALL TESTS PASSED"; endif
return nil

static function TestGroup( c )
   ?; ? "--- " + c + " ---"
return nil

static function Assert( l, c )
   nTests++
   if l; nPassed++; ? "  PASS: " + c; else; nFailed++; ? "  FAIL: " + c; endif
return l

static function Test_CreateBand()
   local oBand := TReportBand():New( "Header" )
   Assert( oBand:cName == "Header", "Band name = Header" )
   Assert( oBand:nHeight == 30, "Default height = 30" )
   Assert( Len( oBand:aFields ) == 0, "No fields initially" )
return nil

static function Test_AddFieldToBand()
   local oBand := TReportBand():New( "Detail" )
   local oFld := TReportField():New( "Name" )
   oFld:cFieldName := "NAME"
   oFld:nLeft := 10
   oFld:nTop := 5
   oFld:nWidth := 100
   oFld:nHeight := 16
   oBand:AddField( oFld )
   Assert( Len( oBand:aFields ) == 1, "Band has 1 field after add" )
   Assert( oBand:aFields[1]:cFieldName == "NAME", "Field is bound to NAME" )
return nil

static function Test_BandProperties()
   local oBand := TReportBand():New( "Footer" )
   oBand:nHeight := 50
   oBand:lPrintOnEveryPage := .T.
   Assert( oBand:nHeight == 50, "Band height = 50" )
   Assert( oBand:lPrintOnEveryPage, "PrintOnEveryPage = .T." )
return nil

static function Test_FieldProperties()
   local oFld := TReportField():New( "Price" )
   oFld:cFieldName := "PRICE"
   oFld:nAlignment := 2  // Right
   oFld:cFormat := "9,999.99"
   oFld:cFontName := "Monospace"
   oFld:nFontSize := 10
   Assert( oFld:cFieldName == "PRICE", "Field bound to PRICE" )
   Assert( oFld:nAlignment == 2, "Right aligned" )
   Assert( oFld:cFormat == "9,999.99", "Number format set" )
return nil

static function Test_FieldDataBinding()
   local oFld := TReportField():New( "Total" )
   oFld:cExpression := "PRICE * QTY"
   Assert( oFld:cExpression == "PRICE * QTY", "Expression field" )
   oFld:cText := "Grand Total:"
   Assert( oFld:cText == "Grand Total:", "Static text" )
return nil

static function Test_ReportAddBands()
   local oRpt := TReport():New()
   oRpt:cTitle := "Sales Report"
   oRpt:AddDesignBand( TReportBand():New( "Header" ) )
   oRpt:AddDesignBand( TReportBand():New( "Detail" ) )
   oRpt:AddDesignBand( TReportBand():New( "Footer" ) )
   Assert( Len( oRpt:aDesignBands ) == 3, "Report has 3 design bands" )
   Assert( oRpt:aDesignBands[1]:cName == "Header", "First band is Header" )
   Assert( oRpt:aDesignBands[2]:cName == "Detail", "Second band is Detail" )
   Assert( oRpt:aDesignBands[3]:cName == "Footer", "Third band is Footer" )
return nil

static function Test_ReportGenerateCode()
   local oRpt := TReport():New()
   local oBand, oFld, cCode
   oRpt:cTitle := "Test Report"

   oBand := TReportBand():New( "Header" )
   oFld := TReportField():New( "Title" )
   oFld:cText := "Sales Report"
   oFld:nLeft := 10; oFld:nTop := 5; oFld:nWidth := 200; oFld:nHeight := 20
   oBand:AddField( oFld )
   oRpt:AddDesignBand( oBand )

   oBand := TReportBand():New( "Detail" )
   oFld := TReportField():New( "FldName" )
   oFld:cFieldName := "NAME"
   oFld:nLeft := 10; oFld:nTop := 2; oFld:nWidth := 100; oFld:nHeight := 14
   oBand:AddField( oFld )
   oRpt:AddDesignBand( oBand )

   cCode := oRpt:GenerateCode( "Report1" )
   Assert( "CLASS TReport1" $ cCode, "Code contains CLASS TReport1" )
   Assert( "Sales Report" $ cCode, "Code contains title" )
   Assert( "NAME" $ cCode, "Code contains field reference" )
return nil

// MsgInfo stub for test context
function MsgInfo( c, t )
   HB_SYMBOL_UNUSED( t ); ? "[MsgInfo] " + c
return nil
```

- [ ] **Step 2: Implement TReportBand and TReportField classes**

Add to `harbour/classes.prg` after the TMongoDB class:

```harbour
//============================================================================//
//  REPORT DESIGNER CLASSES
//============================================================================//

CLASS TReportBand
   DATA cName               INIT ""       // "Header", "Detail", "Footer", "GroupHeader", "GroupFooter", "PageHeader", "PageFooter"
   DATA nHeight             INIT 30       // Band height in mm (design units)
   DATA aFields             INIT {}       // Array of TReportField
   DATA lPrintOnEveryPage   INIT .F.      // Print on every page (headers/footers)
   DATA lKeepTogether       INIT .T.      // Keep band on same page
   DATA lVisible            INIT .T.      // Band visible
   DATA nBackColor          INIT -1       // Background color (-1 = transparent)

   METHOD New( cName ) CONSTRUCTOR
   METHOD AddField( oField )
   METHOD RemoveField( nIndex )
   METHOD FieldCount()
ENDCLASS

METHOD New( cName ) CLASS TReportBand
   if cName != nil; ::cName := cName; endif
   ::aFields := {}
   if ::cName == "Header" .or. ::cName == "PageHeader"
      ::lPrintOnEveryPage := .T.
   endif
return Self

METHOD AddField( oField ) CLASS TReportBand
   AAdd( ::aFields, oField )
return nil

METHOD RemoveField( nIndex ) CLASS TReportBand
   if nIndex > 0 .and. nIndex <= Len( ::aFields )
      ADel( ::aFields, nIndex )
      ASize( ::aFields, Len(::aFields) - 1 )
   endif
return nil

METHOD FieldCount() CLASS TReportBand
return Len( ::aFields )

//----------------------------------------------------------------------------//

CLASS TReportField
   DATA cName           INIT ""       // Field identifier
   DATA cText           INIT ""       // Static text (if not bound to data)
   DATA cFieldName      INIT ""       // Data source field name
   DATA cExpression     INIT ""       // Calculated expression
   DATA nLeft           INIT 0        // Position in band (mm)
   DATA nTop            INIT 0
   DATA nWidth          INIT 80
   DATA nHeight         INIT 16
   DATA nAlignment      INIT 0        // 0=Left, 1=Center, 2=Right
   DATA cFontName       INIT "Sans"
   DATA nFontSize       INIT 10
   DATA lBold           INIT .F.
   DATA lItalic         INIT .F.
   DATA lUnderline      INIT .F.
   DATA cFormat         INIT ""       // Number/date format mask
   DATA nForeColor      INIT 0        // Text color (RGB)
   DATA nBackColor      INIT -1       // Background (-1 = transparent)
   DATA nBorderWidth    INIT 0        // Border thickness
   DATA cFieldType      INIT "text"   // "text", "image", "shape", "line", "barcode"

   METHOD New( cName ) CONSTRUCTOR
   METHOD IsDataBound()
   METHOD GetValue( oDataSource )
ENDCLASS

METHOD New( cName ) CLASS TReportField
   if cName != nil; ::cName := cName; endif
return Self

METHOD IsDataBound() CLASS TReportField
return ! Empty( ::cFieldName ) .or. ! Empty( ::cExpression )

METHOD GetValue( oDataSource ) CLASS TReportField
   local xVal, nFld, i
   if ! Empty( ::cFieldName ) .and. oDataSource != nil .and. oDataSource:oDatabase != nil
      // Find field index by name
      for i := 1 to oDataSource:oDatabase:FieldCount()
         if Upper( oDataSource:oDatabase:FieldName(i) ) == Upper( ::cFieldName )
            xVal := oDataSource:oDatabase:FieldGet( i )
            if ! Empty( ::cFormat ) .and. ValType( xVal ) == "N"
               return Transform( xVal, ::cFormat )
            endif
            return hb_ValToStr( xVal )
         endif
      next
   endif
   if ! Empty( ::cText )
      return ::cText
   endif
return ""
```

- [ ] **Step 3: Extend TReport with design band support and code generation**

Add these methods to the existing TReport class in `harbour/classes.prg`:

```harbour
// Add to TReport DATA declarations:
   DATA aDesignBands  INIT {}       // Array of TReportBand (visual design)
   DATA nPageWidth    INIT 210      // mm (A4)
   DATA nPageHeight   INIT 297      // mm (A4)
   DATA nMarginLeft   INIT 15       // mm
   DATA nMarginRight  INIT 15
   DATA nMarginTop    INIT 15
   DATA nMarginBottom INIT 15

// Add these methods:
   METHOD AddDesignBand( oBand )
   METHOD RemoveDesignBand( nIndex )
   METHOD GetDesignBand( cName )
   METHOD GenerateCode( cClassName )

METHOD AddDesignBand( oBand ) CLASS TReport
   AAdd( ::aDesignBands, oBand )
return nil

METHOD RemoveDesignBand( nIndex ) CLASS TReport
   if nIndex > 0 .and. nIndex <= Len( ::aDesignBands )
      ADel( ::aDesignBands, nIndex )
      ASize( ::aDesignBands, Len(::aDesignBands) - 1 )
   endif
return nil

METHOD GetDesignBand( cName ) CLASS TReport
   local i
   for i := 1 to Len( ::aDesignBands )
      if ::aDesignBands[i]:cName == cName
         return ::aDesignBands[i]
      endif
   next
return nil

METHOD GenerateCode( cClassName ) CLASS TReport
   local cCode := "", cBandCode := "", i, j, oBand, oFld, e := Chr(10)

   cCode += "CLASS T" + cClassName + " FROM TReport" + e + e
   cCode += "   METHOD New() CONSTRUCTOR" + e
   cCode += "   METHOD CreateReport()" + e + e
   cCode += "ENDCLASS" + e + e

   cCode += "METHOD New() CLASS T" + cClassName + e
   cCode += '   ::cTitle := "' + ::cTitle + '"' + e
   cCode += "return Self" + e + e

   cCode += "METHOD CreateReport() CLASS T" + cClassName + e + e

   for i := 1 to Len( ::aDesignBands )
      oBand := ::aDesignBands[i]
      cCode += '   // --- ' + oBand:cName + ' band (height=' + LTrim(Str(oBand:nHeight)) + 'mm) ---' + e

      if oBand:cName == "Detail"
         cCode += '   ::AddBand( "Detail", { |oPrn, oData|' + e
      else
         cCode += '   ::AddBand( "' + oBand:cName + '", { |oPrn|' + e
      endif

      for j := 1 to Len( oBand:aFields )
         oFld := oBand:aFields[j]
         if ! Empty( oFld:cFieldName )
            if oBand:cName == "Detail"
               cCode += '      oPrn:PrintLine( ' + LTrim(Str(oFld:nTop)) + ', ' + ;
                  LTrim(Str(oFld:nLeft)) + ', oData:FieldGet("' + oFld:cFieldName + '") )' + e
            else
               cCode += '      oPrn:PrintLine( ' + LTrim(Str(oFld:nTop)) + ', ' + ;
                  LTrim(Str(oFld:nLeft)) + ', "' + oFld:cFieldName + '" )' + e
            endif
         elseif ! Empty( oFld:cText )
            cCode += '      oPrn:PrintLine( ' + LTrim(Str(oFld:nTop)) + ', ' + ;
               LTrim(Str(oFld:nLeft)) + ', "' + oFld:cText + '" )' + e
         endif
      next

      cCode += "   } )" + e + e
   next

   cCode += "return nil" + e
return cCode
```

- [ ] **Step 4: Build and run tests**

```bash
cd tests
./build_test_debugger.sh  # reuse existing build pattern for test_report.prg
```

Expected: All 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add harbour/classes.prg tests/test_report.prg
git commit -m "feat: TReportBand + TReportField data model with code generation"
```

---

### Task 2: Report Designer Window (GTK3 Cairo rendering)

**Files:**
- Create: `backends/gtk3/gtk3_report_designer.c`
- Modify: `backends/gtk3/gtk3_core.c` (include the new file, add HB_FUNCs)

The designer window renders bands as horizontal colored strips in a scrollable area. Each band shows its name on the left, a ruler at the top, and fields as positioned rectangles within bands. Fields can be selected, moved, and resized using the same handle system as the form designer.

- [ ] **Step 1: Create `gtk3_report_designer.c` with band rendering**

Key functions:
- `HB_FUNC( RPT_DESIGNEROPEN )` — open/create the designer window
- `HB_FUNC( RPT_DESIGNERCLOSE )` — close designer
- `HB_FUNC( RPT_ADDBAND )` — add a band to the visual designer
- `HB_FUNC( RPT_ADDFIELD )` — add a field to a band
- `HB_FUNC( RPT_SELECTFIELD )` — select a field (for inspector)
- `HB_FUNC( RPT_GETSELECTEDFIELD )` — get selected field properties
- `on_report_draw()` — Cairo callback: draw ruler, bands, fields, selection handles
- `on_report_click()` — hit-test bands/fields, select, start drag
- `on_report_motion()` — drag fields, resize
- `on_report_release()` — complete drag/resize

Band colors: Header=#4A90D9 (blue), Detail=#FFFFFF (white), Footer=#4A90D9 (blue), GroupHeader=#6BBF6B (green), PageHeader=#D4A843 (gold).

- [ ] **Step 2: Wire into `gtk3_core.c`**

Add `#include "gtk3_report_designer.c"` at end of gtk3_core.c (same pattern as other subsystems embedded in the file), or compile separately and link.

- [ ] **Step 3: Commit**

```bash
git add backends/gtk3/gtk3_report_designer.c backends/gtk3/gtk3_core.c
git commit -m "feat: report designer window with Cairo band/field rendering"
```

---

### Task 3: Inspector Integration for Report Bands/Fields

**Files:**
- Modify: `backends/gtk3/gtk3_core.c` (add UI_GetAllProps cases for report types)
- Modify: `samples/hbbuilder_linux.prg` (wire Design Report action)

- [ ] **Step 1: Add report property introspection**

When a band is selected in the report designer, the inspector shows:
- cName (read-only), nHeight, lPrintOnEveryPage, lKeepTogether, lVisible, nBackColor

When a field is selected:
- cName, cText, cFieldName, cExpression, nLeft, nTop, nWidth, nHeight, nAlignment, cFontName, nFontSize, lBold, lItalic, cFormat, nForeColor, nBackColor, cFieldType

- [ ] **Step 2: Add "Design Report" action to IDE**

In `hbbuilder_linux.prg`, add handling when user double-clicks a TReport component in the form designer: open the Report Designer window for that report.

- [ ] **Step 3: Report code generation**

When the user closes the report designer or saves, call `TReport:GenerateCode()` and insert the generated METHOD into the code editor, following the same pattern as `SyncDesignerToCode()`.

- [ ] **Step 4: Commit**

```bash
git add backends/gtk3/gtk3_core.c samples/hbbuilder_linux.prg
git commit -m "feat: inspector integration for report bands and fields"
```

---

### Task 4: Preview Window (Cairo page rendering)

**Files:**
- Create: `backends/gtk3/gtk3_report_preview.c` (or add to gtk3_report_designer.c)
- Modify: `harbour/classes.prg` (TReport:Preview method)

- [ ] **Step 1: Cairo preview renderer**

Create a scrollable GtkWindow with a GtkDrawingArea that renders the report as pages:
- White page background with margins shown as gray lines
- Bands rendered top-to-bottom with actual data from TDataSource
- Detail band repeats for each record
- Page breaks when content exceeds page height
- Navigation: Page Up/Down, Zoom In/Out slider
- Toolbar: Print, Zoom, Page navigation

- [ ] **Step 2: Wire TReport:Preview()**

```harbour
METHOD Preview() CLASS TReport
   RPT_PreviewOpen( Self )  // Opens the preview window
return nil
```

- [ ] **Step 3: Test with example data**

Create a report with Header/Detail/Footer bands, bind to a DBF with 20+ records, verify pagination, field rendering, and formatting.

- [ ] **Step 4: Commit**

```bash
git add backends/gtk3/gtk3_report_preview.c harbour/classes.prg
git commit -m "feat: report preview window with Cairo page rendering"
```

---

### Task 5: xCommand Macros + Example Project

**Files:**
- Modify: `harbour/hbbuilder.ch` (add report xcommands)
- Create: `samples/projects/printing/report_designer_example.prg`

- [ ] **Step 1: Add xcommand macros**

```xbase
#xcommand DEFINE REPORT <oRpt> [ TITLE <cTitle> ] [ DATASOURCE <oDS> ] ;
   => <oRpt> := TReport():New() ;
      [; <oRpt>:cTitle := <cTitle> ] ;
      [; <oRpt>:oDataSource := <oDS> ]

#xcommand DEFINE BAND <oBand> NAME <cName> [ HEIGHT <nH> ] OF <oRpt> ;
   => <oBand> := TReportBand():New( <cName> ) ;
      [; <oBand>:nHeight := <nH> ] ;
      ; <oRpt>:AddDesignBand( <oBand> )

#xcommand REPORT FIELD <oFld> [ TEXT <cText> ] [ FIELD <cField> ] ;
   [ AT <nTop>, <nLeft> ] [ SIZE <nW>, <nH> ] OF <oBand> ;
   => <oFld> := TReportField():New() ;
      [; <oFld>:cText := <cText> ] ;
      [; <oFld>:cFieldName := <cField> ] ;
      [; <oFld>:nTop := <nTop> ] [; <oFld>:nLeft := <nLeft> ] ;
      [; <oFld>:nWidth := <nW> ] [; <oFld>:nHeight := <nH> ] ;
      ; <oBand>:AddField( <oFld> )
```

- [ ] **Step 2: Create example project**

```harbour
// report_designer_example.prg
#include "hbbuilder.ch"
REQUEST DBFCDX

function Main()
   local oDb, oDS, oRpt, oBand, oFld

   // Open data
   oDb := TDBFTable():New()
   oDb:cDatabase := "employees.dbf"
   oDb:Open()
   oDS := TDataSource():New( oDb )

   // Define report using xcommands
   DEFINE REPORT oRpt TITLE "Employee List" DATASOURCE oDS

   DEFINE BAND oBand NAME "Header" HEIGHT 40 OF oRpt
   REPORT FIELD oFld TEXT "EMPLOYEE LIST" AT 5, 10 SIZE 180, 20 OF oBand
   oFld:lBold := .T.
   oFld:nFontSize := 16

   DEFINE BAND oBand NAME "Detail" HEIGHT 18 OF oRpt
   REPORT FIELD oFld FIELD "NAME"   AT 2, 10  SIZE 100, 14 OF oBand
   REPORT FIELD oFld FIELD "DEPT"   AT 2, 120 SIZE  80, 14 OF oBand
   REPORT FIELD oFld FIELD "SALARY" AT 2, 210 SIZE  60, 14 OF oBand
   oFld:nAlignment := 2
   oFld:cFormat := "999,999.99"

   DEFINE BAND oBand NAME "Footer" HEIGHT 25 OF oRpt
   REPORT FIELD oFld TEXT "End of Report" AT 5, 10 SIZE 100, 14 OF oBand

   // Generate and display code
   ? oRpt:GenerateCode( "EmployeeReport" )

   // Preview
   oRpt:Preview()

   oDb:Close()
return nil
```

- [ ] **Step 3: Test the example**

```bash
cd samples/projects
bash build_example.sh printing/report_designer_example
```

- [ ] **Step 4: Commit**

```bash
git add harbour/hbbuilder.ch samples/projects/printing/report_designer_example.prg
git commit -m "feat: report xcommand macros + example project"
```

---

### Task 6: Update Documentation and ChangeLog

**Files:**
- Modify: `README.md` (update progress table, add report designer to features)
- Modify: `ChangeLog.txt` (document session)
- Modify: `docs/linux.md` (add report designer section)

- [ ] **Step 1: Update all docs**
- [ ] **Step 2: Commit**

```bash
git add README.md ChangeLog.txt docs/linux.md
git commit -m "docs: visual report designer documentation"
```

---

## Dependency Graph

```
Task 1 (Data Model) ──→ Task 2 (Designer Window) ──→ Task 3 (Inspector)
                    └──→ Task 5 (xCommands)           │
                                                      ↓
                                                 Task 4 (Preview)
                                                      │
                                                      ↓
                                                 Task 6 (Docs)
```

Tasks 1 and 5 can be done in parallel. Task 2 depends on Task 1. Tasks 3 and 4 depend on Task 2. Task 6 is last.

---

## Key Design Decisions

1. **Bands are horizontal strips** — same metaphor as FastReport, Crystal Reports, R&R Report Writer. Users understand this immediately.

2. **Fields within bands** — each field has position (nLeft, nTop) relative to the band's top-left corner. This simplifies rendering and code generation.

3. **Code generation follows form pattern** — `GenerateCode("Report1")` produces a complete CLASS with `CreateReport()` METHOD, just like `RegenerateFormCode()` produces `CreateForm()`.

4. **Inspector reuse** — the existing Object Inspector works for report bands and fields without modification, just by returning appropriate property arrays from `UI_GetAllProps()`.

5. **Cairo preview** — renders directly to a GtkDrawingArea using Cairo. No external dependencies. Same rendering code can output to PDF in the future.

6. **xCommand macros** — `DEFINE REPORT`, `DEFINE BAND`, `REPORT FIELD` enable declarative report definition, consistent with the rest of HarbourBuilder's xBase syntax.
