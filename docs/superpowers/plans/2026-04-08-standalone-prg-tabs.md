# Standalone .prg Tabs (Modules + Open Files) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support three types of editor tabs: Project1.prg (fixed), form tabs (with visual designer), module tabs (compiled with project, persisted in .hbp), and open-file tabs (view/edit only, not in project).

**Architecture:** Add two new static arrays `aModules` (project modules) and `aOpenFiles` (loose files). Tab order: `[Project1.prg] [Form1..N] [Module1..N] [OpenFile1..N]`. Modify `OnEditorTabChange` to route tabs to the correct handler. Update .hbp format with `[modules]` section. Update build pipeline to include module code.

**Tech Stack:** Harbour (hbbuilder_macos.prg)

---

### Tab Layout

```
Tab 1          : Project1.prg        (fixed, no array)
Tab 2..F+1     : Form tabs           (aForms[1..F])
Tab F+2..F+M+1 : Module tabs         (aModules[1..M])
Tab F+M+2..    : Open file tabs      (aOpenFiles[1..O])
```

Helper functions:
- `nFormTabs()` → `Len(aForms)` — number of form tabs
- `nModuleTabs()` → `Len(aModules)` — number of module tabs
- Tab N mapping:
  - N == 1 → Project1.prg
  - N >= 2 and N <= F+1 → aForms[N-1]
  - N >= F+2 and N <= F+M+1 → aModules[N-F-1]
  - N >= F+M+2 → aOpenFiles[N-F-M-1]

### File Structure

**Modify:** `samples/hbbuilder_macos.prg`
- Add `static aModules` and `static aOpenFiles` arrays
- Add menu items: "Add Module", "Open File...", "Close File"
- Modify: `OnEditorTabChange`, `TBSave`, `TBOpen`, `TBRun`, `TBDebugRun`
- Modify: `AddToProject`, `RemoveFromProject`
- Modify: `INS_GetAllCode`, `SaveActiveFormCode`
- Add: `TabIndex()` helper, `MenuAddModule()`, `MenuOpenFile()`, `MenuCloseFile()`

---

### Task 1: Add static arrays and tab-index helpers

**Files:**
- Modify: `samples/hbbuilder_macos.prg:30-31`

- [ ] **Step 1: Add new static variables**

After line 31 (`static nActiveForm`), add:

```harbour
static aModules      // Array of project modules: { { cName, cCode, cFilePath }, ... }
static aOpenFiles    // Array of open files (not in project): { { cName, cCode, cFilePath }, ... }
```

- [ ] **Step 2: Initialize in Main()**

In `Main()`, after `nActiveForm := 0` (line 46), add:

```harbour
   aModules := {}
   aOpenFiles := {}
```

- [ ] **Step 3: Also initialize in TBNew()**

Find TBNew() and add initialization for aModules and aOpenFiles alongside aForms := {}.

- [ ] **Step 4: Add tab-index helper function**

Add after `SaveActiveFormCode()`:

```harbour
// Determine what type of tab nTab refers to and return { cType, nIndex }
// cType: "project", "form", "module", "openfile"
// nIndex: 1-based index into the respective array
static function TabInfo( nTab )

   local nF := Len( aForms )
   local nM := Len( aModules )

   if nTab == 1
      return { "project", 0 }
   elseif nTab <= nF + 1
      return { "form", nTab - 1 }
   elseif nTab <= nF + nM + 1
      return { "module", nTab - nF - 1 }
   else
      return { "openfile", nTab - nF - nM - 1 }
   endif

return { "project", 0 }
```

- [ ] **Step 5: Build and verify**

Run: `bash build_mac.sh 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add samples/hbbuilder_macos.prg
git commit -m "feat(macOS): add aModules/aOpenFiles arrays and TabInfo() helper"
```

---

### Task 2: Modify OnEditorTabChange to handle all tab types

**Files:**
- Modify: `samples/hbbuilder_macos.prg` — `OnEditorTabChange()` at ~line 1202

- [ ] **Step 1: Replace OnEditorTabChange**

Replace the current `OnEditorTabChange` function with:

```harbour
// Editor tab changed: route to form, module, or open file
static function OnEditorTabChange( hEd, nTab )

   local aInfo := TabInfo( nTab )

   do case
   case aInfo[1] == "form"
      if aInfo[2] != nActiveForm .and. aInfo[2] <= Len( aForms )
         SwitchToForm( aInfo[2] )
      endif
   case aInfo[1] == "module" .or. aInfo[1] == "openfile"
      // Save current form code before switching away
      SaveActiveFormCode()
      // No form to activate — just let the editor show the tab
   endcase

return nil
```

- [ ] **Step 2: Build and verify**

Run: `bash build_mac.sh 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add samples/hbbuilder_macos.prg
git commit -m "feat(macOS): OnEditorTabChange routes form/module/openfile tabs"
```

---

### Task 3: Add menu items and implement Add Module / Open File / Close File

**Files:**
- Modify: `samples/hbbuilder_macos.prg` — menu definitions and new functions

- [ ] **Step 1: Add menu items**

In the File menu (after "New Form" line ~80), add:

```harbour
   MENUITEM "Add Module..."   OF oFile ACTION MenuAddModule()
   MENUSEPARATOR OF oFile
   MENUITEM "Open File..."    OF oFile ACTION MenuOpenFile()
   MENUITEM "Close File"      OF oFile ACTION MenuCloseFile()
```

Move the existing `MENUITEM "Open..."` (TBOpen) to be `MENUITEM "Open Project..."`.

- [ ] **Step 2: Implement MenuAddModule()**

Add the function:

```harbour
// Add a standalone .prg module to the project
static function MenuAddModule()

   local cFile, cName, cCode, i, nTabPos

   cFile := MAC_OpenFileDialog( "Add Module to Project", "prg" )
   if Empty( cFile ); return nil; endif

   cName := SubStr( cFile, RAt( "/", cFile ) + 1 )
   if "." $ cName
      cName := Left( cName, At( ".", cName ) - 1 )
   endif

   // Check duplicates in forms and modules
   for i := 1 to Len( aForms )
      if Lower( aForms[i][1] ) == Lower( cName )
         MsgInfo( cName + " is already in the project (as a form)" )
         return nil
      endif
   next
   for i := 1 to Len( aModules )
      if Lower( aModules[i][1] ) == Lower( cName )
         MsgInfo( cName + " is already in the project (as a module)" )
         return nil
      endif
   next

   cCode := hb_MemoRead( cFile )
   if Empty( cCode )
      cCode := "// " + cName + ".prg" + Chr(10)
   endif

   AAdd( aModules, { cName, cCode, cFile } )

   // Tab position: after all forms
   nTabPos := 1 + Len( aForms ) + Len( aModules )
   CodeEditorAddTab( hCodeEditor, cName + ".prg" )
   CodeEditorSetTabText( hCodeEditor, nTabPos, cCode )
   CodeEditorSelectTab( hCodeEditor, nTabPos )

return nil
```

- [ ] **Step 3: Implement MenuOpenFile()**

```harbour
// Open a .prg file for viewing/editing (not added to project)
static function MenuOpenFile()

   local cFile, cName, cCode, i, nTabPos

   cFile := MAC_OpenFileDialog( "Open File", "prg" )
   if Empty( cFile ); return nil; endif

   cName := SubStr( cFile, RAt( "/", cFile ) + 1 )
   if "." $ cName
      cName := Left( cName, At( ".", cName ) - 1 )
   endif

   // Check if already open
   for i := 1 to Len( aOpenFiles )
      if Lower( aOpenFiles[i][3] ) == Lower( cFile )
         // Already open — just switch to it
         CodeEditorSelectTab( hCodeEditor, 1 + Len(aForms) + Len(aModules) + i )
         return nil
      endif
   next

   cCode := hb_MemoRead( cFile )
   if Empty( cCode )
      MsgInfo( "Could not read file: " + cFile )
      return nil
   endif

   AAdd( aOpenFiles, { cName, cCode, cFile } )

   nTabPos := 1 + Len( aForms ) + Len( aModules ) + Len( aOpenFiles )
   CodeEditorAddTab( hCodeEditor, cName + ".prg" )
   CodeEditorSetTabText( hCodeEditor, nTabPos, cCode )
   CodeEditorSelectTab( hCodeEditor, nTabPos )

return nil
```

- [ ] **Step 4: Implement MenuCloseFile()**

```harbour
// Close the current open-file tab (only for open files, not forms/modules)
static function MenuCloseFile()

   local nTab, aInfo, nIdx

   nTab := CodeEditorGetActiveTab( hCodeEditor )
   aInfo := TabInfo( nTab )

   if aInfo[1] != "openfile"
      MsgInfo( "Only open files can be closed. Use 'Remove from Project' for forms and modules." )
      return nil
   endif

   nIdx := aInfo[2]
   if nIdx < 1 .or. nIdx > Len( aOpenFiles )
      return nil
   endif

   // Remove tab from editor
   CodeEditorRemoveTab( hCodeEditor, nTab )

   // Remove from array
   ADel( aOpenFiles, nIdx )
   ASize( aOpenFiles, Len(aOpenFiles) - 1 )

   // Switch to previous tab
   if nTab > 1
      CodeEditorSelectTab( hCodeEditor, nTab - 1 )
   endif

return nil
```

- [ ] **Step 5: Build and verify**

Run: `bash build_mac.sh 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add samples/hbbuilder_macos.prg
git commit -m "feat(macOS): Add Module, Open File, Close File menu actions"
```

---

### Task 4: Update AddToProject / RemoveFromProject for modules

**Files:**
- Modify: `samples/hbbuilder_macos.prg` — existing `AddToProject()` and `RemoveFromProject()`

- [ ] **Step 1: Replace AddToProject()**

Replace the existing `AddToProject()` with a redirect to `MenuAddModule()`:

```harbour
static function AddToProject()
   MenuAddModule()
return nil
```

- [ ] **Step 2: Update RemoveFromProject()**

Replace the existing `RemoveFromProject()` to handle both forms and modules:

```harbour
static function RemoveFromProject()

   local aNames := {}, i, nSel, nType

   // Build list: forms first, then modules
   for i := 1 to Len( aForms )
      AAdd( aNames, aForms[i][1] + ".prg (Form)" )
   next
   for i := 1 to Len( aModules )
      AAdd( aNames, aModules[i][1] + ".prg (Module)" )
   next

   if Len( aNames ) == 0
      MsgInfo( "No items to remove" )
      return nil
   endif

   nSel := MAC_SelectFromList( "Remove from Project", aNames )
   if nSel < 1; return nil; endif

   if nSel <= Len( aForms )
      // Removing a form
      if Len( aForms ) <= 1 .and. Len( aModules ) == 0
         MsgInfo( "Cannot remove the last item from the project" )
         return nil
      endif
      aForms[nSel][2]:Destroy()
      CodeEditorRemoveTab( hCodeEditor, nSel + 1 )
      ADel( aForms, nSel )
      ASize( aForms, Len(aForms) - 1 )
      if nActiveForm > Len( aForms )
         nActiveForm := Max( Len( aForms ), 1 )
      endif
      if nActiveForm > 0 .and. Len( aForms ) > 0
         SwitchToForm( nActiveForm )
      endif
   else
      // Removing a module
      i := nSel - Len( aForms )
      CodeEditorRemoveTab( hCodeEditor, 1 + Len(aForms) + i )
      ADel( aModules, i )
      ASize( aModules, Len(aModules) - 1 )
   endif

   // Regenerate Project1.prg
   CodeEditorSetTabText( hCodeEditor, 1, GenerateProjectCode() )

return nil
```

- [ ] **Step 3: Build and verify**

Run: `bash build_mac.sh 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add samples/hbbuilder_macos.prg
git commit -m "feat(macOS): AddToProject/RemoveFromProject handle modules"
```

---

### Task 5: Update .hbp save/load for modules

**Files:**
- Modify: `samples/hbbuilder_macos.prg` — `TBSave()` and `TBOpen()`

- [ ] **Step 1: Update TBSave() to write modules**

In `TBSave()`, after writing form .prg files, add module saving:

```harbour
   // Write .hbp file (project index)
   cHbp := "Project1" + Chr(10)
   for i := 1 to Len( aForms )
      cHbp += aForms[i][1] + Chr(10)
   next
   if Len( aModules ) > 0
      cHbp += "[modules]" + Chr(10)
      for i := 1 to Len( aModules )
         cHbp += aModules[i][1] + Chr(10)
      next
   endif
   MemoWrit( cCurrentFile, cHbp )
```

Also save module .prg files after form files:

```harbour
   // Write each module .prg
   for i := 1 to Len( aModules )
      // Save current editor text for this module
      aModules[i][2] := CodeEditorGetTabText( hCodeEditor, 1 + Len(aForms) + i )
      MemoWrit( cDir + aModules[i][1] + ".prg", aModules[i][2] )
   next
```

- [ ] **Step 2: Update TBOpen() to load modules**

In `TBOpen()`, after loading forms, add module loading. After the form loop and before "Activate first form", add:

```harbour
   // Load modules (after [modules] marker)
   local lInModules := .F.
   aModules := {}
   for i := 2 to Len( aLines )
      cFormName := AllTrim( aLines[i] )
      if Empty( cFormName ); loop; endif
      if Lower( cFormName ) == "[modules]"
         lInModules := .T.
         loop
      endif
      if lInModules
         cFormCode := MemoRead( cDir + cFormName + ".prg" )
         if Empty( cFormCode ); loop; endif
         AAdd( aModules, { cFormName, cFormCode, cDir + cFormName + ".prg" } )
         CodeEditorAddTab( hCodeEditor, cFormName + ".prg" )
         CodeEditorSetTabText( hCodeEditor, 1 + Len(aForms) + Len(aModules), cFormCode )
      endif
   next
```

Also modify the existing form-loading loop to skip lines after `[modules]` — change it to break when it hits `[modules]`:

In the existing loop `for i := 2 to Len( aLines )`, add at the top:
```harbour
      if Lower( cFormName ) == "[modules]"
         // Will be handled in the modules loop below
         exit
      endif
```

- [ ] **Step 3: Build and verify**

Run: `bash build_mac.sh 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add samples/hbbuilder_macos.prg
git commit -m "feat(macOS): .hbp save/load supports [modules] section"
```

---

### Task 6: Update build pipeline to include modules

**Files:**
- Modify: `samples/hbbuilder_macos.prg` — `TBRun()` and `TBDebugRun()`

- [ ] **Step 1: Update TBRun() — save modules to build dir**

In TBRun(), after saving form .prg files to cBuildDir (step 1 area), add:

```harbour
   // Save module files
   for i := 1 to Len( aModules )
      aModules[i][2] := CodeEditorGetTabText( hCodeEditor, 1 + Len(aForms) + i )
      MemoWrit( cBuildDir + "/" + aModules[i][1] + ".prg", aModules[i][2] )
      cLog += "    " + aModules[i][1] + ".prg (module)" + Chr(10)
   next
```

- [ ] **Step 2: Update TBRun() — include modules in main.prg assembly**

In the main.prg assembly (step 2), after appending form code, add module code:

```harbour
   for i := 1 to Len( aModules )
      cAllPrg += MemoRead( cBuildDir + "/" + aModules[i][1] + ".prg" ) + Chr(10)
   next
```

- [ ] **Step 3: Update TBRun() — include modules in hash check**

In the hash computation, after iterating aForms, add:

```harbour
   for i := 1 to Len( aModules )
      cAllCode += aModules[i][2]
   next
```

- [ ] **Step 4: Apply same changes to TBDebugRun()**

Repeat steps 1-3 for the `TBDebugRun()` function.

- [ ] **Step 5: Build and verify**

Run: `bash build_mac.sh 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add samples/hbbuilder_macos.prg
git commit -m "feat(macOS): build pipeline compiles project modules"
```

---

### Task 7: Update INS_GetAllCode to include modules

**Files:**
- Modify: `samples/hbbuilder_macos.prg` — `INS_GetAllCode()`

- [ ] **Step 1: Update INS_GetAllCode**

Add module code to the "all code" string:

```harbour
function INS_GetAllCode()

   local cAll := "", i

   cAll := CodeEditorGetTabText( hCodeEditor, 1 )  // Project1.prg
   for i := 1 to Len( aForms )
      cAll += aForms[i][3]
      cAll += CodeEditorGetTabText( hCodeEditor, i + 1 )
   next
   for i := 1 to Len( aModules )
      cAll += CodeEditorGetTabText( hCodeEditor, 1 + Len(aForms) + i )
   next

return cAll
```

- [ ] **Step 2: Build and verify**

Run: `bash build_mac.sh 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add samples/hbbuilder_macos.prg
git commit -m "feat(macOS): INS_GetAllCode includes module code"
```

---

### Task 8: Verify CodeEditorRemoveTab exists

**Files:**
- Check: `backends/cocoa/cocoa_editor.mm`

- [ ] **Step 1: Check if CodeEditorRemoveTab exists**

Search for `CODEEDITORREMOVEAB` or `RemoveTab` in cocoa_editor.mm. If it doesn't exist, implement it:

```objc
/* CodeEditorRemoveTab( hEditor, nTabIndex ) — 1-based */
HB_FUNC( CODEEDITORREMOVETAB )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   int nTab = hb_parni(2) - 1;  /* 0-based */
   if( !ed || !ed->tabBar || nTab < 0 ) return;

   NSInteger count = [ed->tabBar numberOfItems];
   if( nTab >= (int)count ) return;

   [ed->tabBar removeItemAtIndex:nTab];

   /* Remove the stored text for this tab */
   if( nTab < (int)[ed->tabTexts count] )
      [ed->tabTexts removeObjectAtIndex:nTab];

   /* Select previous tab if we removed the active one */
   NSInteger active = [ed->tabBar indexOfSelectedItem];
   if( active >= (int)[ed->tabBar numberOfItems] && [ed->tabBar numberOfItems] > 0 )
      [ed->tabBar selectItemAtIndex:[ed->tabBar numberOfItems] - 1];
}
```

Also check `CodeEditorGetActiveTab` exists. If not:

```objc
/* CodeEditorGetActiveTab( hEditor ) → nTab (1-based) */
HB_FUNC( CODEEDITORGETACTIVETAB )
{
   CODEEDITOR * ed = (CODEEDITOR *)(HB_PTRUINT) hb_parnint(1);
   if( !ed || !ed->tabBar ) { hb_retni(0); return; }
   hb_retni( (int)[ed->tabBar indexOfSelectedItem] + 1 );
}
```

- [ ] **Step 2: Build and verify**

Run: `bash build_mac.sh 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add backends/cocoa/cocoa_editor.mm samples/hbbuilder_macos.prg
git commit -m "feat(macOS): CodeEditorRemoveTab and CodeEditorGetActiveTab"
```

---

### Task 9: Final integration test

- [ ] **Step 1: Build and run**

```bash
bash build_mac.sh
open bin/HbBuilder.app
```

- [ ] **Step 2: Test Add Module**

1. File > Add Module... → select a .prg file
2. Verify tab appears after form tabs
3. Edit the module code
4. File > Save → verify module saved to disk and in .hbp under `[modules]`
5. Run (F9) → verify module code is compiled

- [ ] **Step 3: Test Open File**

1. File > Open File... → select any .prg
2. Verify tab appears after module tabs
3. File > Save → verify open file is NOT in .hbp
4. File > Close File → verify tab removed
5. Reopen same file → verify no duplicates

- [ ] **Step 4: Test project reload**

1. File > Open Project... → open a .hbp with modules
2. Verify form tabs + module tabs load correctly
3. Verify open files are NOT restored

- [ ] **Step 5: Commit all and push**

```bash
git add -A
git commit -m "feat(macOS): standalone .prg tabs — modules and open files"
git push
```
