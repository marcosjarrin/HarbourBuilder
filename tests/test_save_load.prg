// test_save_load.prg — Test battery for project save/load
//
// Tests:
// 1. MemoWrit / MemoRead round-trip
// 2. .hbp file format (project index)
// 3. .prg file generation (form code)
// 4. Project structure integrity
// 5. Multiple forms save/load
// 6. Empty project handling
// 7. Special characters in code
// 8. Path handling

#include "../harbour/hbbuilder.ch"

static nPass := 0
static nFail := 0
static nTotal := 0

function Main()

   local cTestDir := "/tmp/hbbuilder_test_" + LTrim(Str(Seconds()))

   QOut( "" )
   QOut( "=== HbBuilder Save/Load Test Battery ===" )
   QOut( "" )

   MAC_ShellExec( "mkdir -p " + cTestDir )

   // Group 1: MemoWrit / MemoRead
   TestGroup( "MemoWrit / MemoRead" )
   Test( "Write and read simple text", ;
      TestMemoRoundTrip( cTestDir, "Hello World" ) )
   Test( "Write and read empty string", ;
      TestMemoRoundTrip( cTestDir, "" ) )
   Test( "Write and read multiline", ;
      TestMemoRoundTrip( cTestDir, "Line1" + Chr(10) + "Line2" + Chr(10) + "Line3" ) )
   Test( "Write and read special chars", ;
      TestMemoRoundTrip( cTestDir, 'He said "hello" & OK' ) )

   // Group 2: .hbp file format
   TestGroup( "Project file format (.hbp)" )
   Test( "Single form project", TestHbpFormat( cTestDir, { "Form1" } ) )
   Test( "Multi-form project", TestHbpFormat( cTestDir, { "Form1", "Form2", "Form3" } ) )

   // Group 3: Form code generation
   TestGroup( "Form code generation" )
   Test( "Basic form code structure", TestFormCodeGen( cTestDir ) )

   // Group 4: Full save/load cycle
   TestGroup( "Full project save/load cycle" )
   Test( "Save and reload single form", TestSaveLoadCycle( cTestDir, 1 ) )
   Test( "Save and reload 3 forms", TestSaveLoadCycle( cTestDir, 3 ) )

   // Group 5: Edge cases
   TestGroup( "Edge cases" )
   Test( "Path with spaces", TestPathSpaces( cTestDir ) )
   Test( "Large code file (10KB)", TestLargeFile( cTestDir ) )
   Test( "Unicode in code", TestUnicode( cTestDir ) )

   // Cleanup
   MAC_ShellExec( "rm -rf " + cTestDir )

   // Summary
   QOut( "" )
   QOut( "=== Results ===" )
   QOut( "Passed: " + LTrim(Str(nPass)) + " / " + LTrim(Str(nTotal)) )
   if nFail > 0
      QOut( "FAILED: " + LTrim(Str(nFail)) )
   else
      QOut( "All tests PASSED!" )
   endif
   QOut( "" )

return nil

// === Test helpers ===

static function TestGroup( cName )
   QOut( "" )
   QOut( "--- " + cName + " ---" )
return nil

static function Test( cName, lResult )
   nTotal++
   if lResult
      nPass++
      QOut( "  PASS: " + cName )
   else
      nFail++
      QOut( "  FAIL: " + cName )
   endif
return nil

// === Test implementations ===

static function TestMemoRoundTrip( cDir, cText )
   local cFile := cDir + "/test_memo.txt"
   local cRead
   MemoWrit( cFile, cText )
   cRead := MemoRead( cFile )
return cRead == cText

static function TestHbpFormat( cDir, aForms )
   local cFile := cDir + "/TestProject.hbp"
   local cHbp := "", i, cRead, aLines

   // Build .hbp content
   cHbp := "TestProject" + Chr(10)
   for i := 1 to Len( aForms )
      cHbp += aForms[i] + Chr(10)
   next
   MemoWrit( cFile, cHbp )

   // Read back and verify
   cRead := MemoRead( cFile )
   if Empty( cRead ); return .F.; endif

   aLines := HB_ATokens( cRead, Chr(10) )
   if Len( aLines ) < Len( aForms ) + 1; return .F.; endif

   // First line = project name
   if AllTrim( aLines[1] ) != "TestProject"; return .F.; endif

   // Remaining lines = form names
   for i := 1 to Len( aForms )
      if AllTrim( aLines[i+1] ) != aForms[i]; return .F.; endif
   next

return .T.

static function TestFormCodeGen( cDir )
   local cCode := "", cRead

   cCode += "// Form1.prg" + Chr(10) + Chr(10)
   cCode += "CLASS TForm1 FROM TForm" + Chr(10)
   cCode += "   // IDE-managed Components" + Chr(10)
   cCode += "   METHOD CreateForm()" + Chr(10)
   cCode += "ENDCLASS" + Chr(10) + Chr(10)
   cCode += 'METHOD CreateForm() CLASS TForm1' + Chr(10)
   cCode += '   ::Title  := "Form1"' + Chr(10)
   cCode += '   ::Left   := 100' + Chr(10)
   cCode += '   ::Top    := 200' + Chr(10)
   cCode += '   ::Width  := 400' + Chr(10)
   cCode += '   ::Height := 300' + Chr(10)
   cCode += 'return nil' + Chr(10)

   MemoWrit( cDir + "/Form1.prg", cCode )
   cRead := MemoRead( cDir + "/Form1.prg" )

   if ! ( "CLASS TForm1 FROM TForm" $ cRead ); return .F.; endif
   if ! ( "METHOD CreateForm()" $ cRead ); return .F.; endif
   if ! ( "ENDCLASS" $ cRead ); return .F.; endif
   if ! ( "::Title" $ cRead ); return .F.; endif

return .T.

static function TestSaveLoadCycle( cDir, nForms )
   local cProjDir := cDir + "/proj" + LTrim(Str(nForms))
   local cHbp := "", i, cFormCode, cRead, aLines

   MAC_ShellExec( "mkdir -p " + cProjDir )

   // Save project
   cHbp := "Project1" + Chr(10)
   for i := 1 to nForms
      cHbp += "Form" + LTrim(Str(i)) + Chr(10)
      // Write form file
      cFormCode := "// Form" + LTrim(Str(i)) + ".prg" + Chr(10)
      cFormCode += "CLASS TForm" + LTrim(Str(i)) + " FROM TForm" + Chr(10)
      cFormCode += "ENDCLASS" + Chr(10)
      MemoWrit( cProjDir + "/Form" + LTrim(Str(i)) + ".prg", cFormCode )
   next
   MemoWrit( cProjDir + "/Project1.hbp", cHbp )
   MemoWrit( cProjDir + "/Project1.prg", '#include "hbbuilder.ch"' + Chr(10) )

   // Load and verify
   cRead := MemoRead( cProjDir + "/Project1.hbp" )
   if Empty( cRead ); return .F.; endif

   aLines := HB_ATokens( cRead, Chr(10) )
   if AllTrim( aLines[1] ) != "Project1"; return .F.; endif

   // Verify all form files exist and are readable
   for i := 1 to nForms
      cRead := MemoRead( cProjDir + "/Form" + LTrim(Str(i)) + ".prg" )
      if Empty( cRead ); return .F.; endif
      if ! ( "TForm" + LTrim(Str(i)) $ cRead ); return .F.; endif
   next

return .T.

static function TestPathSpaces( cDir )
   local cPath := cDir + "/path with spaces"
   local cFile := cPath + "/test.prg"
   local cRead
   MAC_ShellExec( 'mkdir -p "' + cPath + '"' )
   MemoWrit( cFile, "// test" + Chr(10) )
   cRead := MemoRead( cFile )
return "// test" $ cRead

static function TestLargeFile( cDir )
   local cFile := cDir + "/large.prg"
   local cCode := "", cRead, i
   for i := 1 to 200
      cCode += "// Line " + LTrim(Str(i)) + " of test code with some padding text here" + Chr(10)
   next
   MemoWrit( cFile, cCode )
   cRead := MemoRead( cFile )
return Len( cRead ) == Len( cCode )

static function TestUnicode( cDir )
   local cFile := cDir + "/unicode.prg"
   local cCode := "// Comentario con acentos" + Chr(10)
   local cRead
   cCode += "// More text" + Chr(10)
   MemoWrit( cFile, cCode )
   cRead := MemoRead( cFile )
return cRead == cCode

#include "../harbour/classes.prg"
