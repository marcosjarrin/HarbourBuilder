// inspector_mac.prg - Harbour wrapper functions for the inspector
// The C implementation (INS_Create, etc.) comes from cocoa_inspector.m
// This file contains ONLY the Harbour-level functions.

// Force symbol registration for C functions called via hb_dynsymFindName from C
EXTERNAL UI_BROWSESETCOLPROP
EXTERNAL UI_BROWSEGETCOLPROPS
EXTERNAL UI_BROWSECOLCOUNT

function InspectorOpen()
   if _InsGetData() == 0
      _InsSetData( INS_Create() )
   endif
return nil

function InspectorRefresh( hCtrl )
   local h := _InsGetData()
   local aProps, aEvents
   local i, cName, cHandler, cCode
   if h != 0
      if hCtrl != nil .and. hCtrl != 0
         aProps  := UI_GetAllProps( hCtrl )
         aEvents := UI_GetAllEvents( hCtrl )

         // Resolve handler names from editor code
         cCode := _InsGetEditorCode()
         cName := UI_GetProp( hCtrl, "cName" )
         if Empty( cName )
            if UI_GetProp( hCtrl, "cClassName" ) == "TForm"
               cName := "Form1"
            else
               cName := "ctrl"
            endif
         endif
         if ! Empty( cCode ) .and. ! Empty( aEvents )
            for i := 1 to Len( aEvents )
               if Len( aEvents[i] ) >= 3 .and. ! Empty( aEvents[i][1] )
                  cHandler := cName + SubStr( aEvents[i][1], 3 )
                  if ( "function " + cHandler ) $ cCode
                     aEvents[i][2] := cHandler
                  endif
               endif
            next
         endif

         INS_RefreshWithData( h, hCtrl, aProps )
         INS_SetEvents( h, aEvents )
      else
         INS_RefreshWithData( h, 0, {} )
         INS_SetEvents( h, {} )
      endif
   endif
return nil

// Populate combo with all controls from the design form
// Combo map: maps combo index -> { nType, hCtrl, nColIdx }
//   nType: 0=form, 1=control, 2=browse column
function InspectorPopulateCombo( hForm )
   local h := _InsGetData()
   local i, j, nCount, hChild, cName, cClass, cEntry, nColCount
   local aMap, cTabsStr, aTabsArr, jj

   if h == 0 .or. hForm == 0
      return nil
   endif

   INS_ComboClear( h )
   INS_SetFormCtrl( h, hForm )
   aMap := {}

   // Add the form itself: "oForm1 AS TForm1"
   cName  := UI_GetProp( hForm, "cName" )
   cClass := UI_GetProp( hForm, "cClassName" )
   if Empty( cName ); cName := "Form1"; endif
   cEntry := "o" + cName + " AS T" + cName
   INS_ComboAdd( h, cEntry )
   AAdd( aMap, { 0, hForm, 0 } )

   // Add all child controls: "oButton1 AS TButton"
   nCount := UI_GetChildCount( hForm )
   for i := 1 to nCount
      hChild := UI_GetChild( hForm, i )
      if hChild != 0
         cName  := UI_GetProp( hChild, "cName" )
         cClass := UI_GetProp( hChild, "cClassName" )
         if Empty( cName ); cName := "ctrl" + LTrim( Str( i ) ); endif
         cEntry := "o" + cName + " AS " + cClass
         INS_ComboAdd( h, cEntry )
         AAdd( aMap, { 1, hChild, 0 } )

         // If it's a Browse, add its columns as sub-entries
         if UI_GetType( hChild ) == 79  // CT_BROWSE
            nColCount := UI_BrowseColCount( hChild )
            for j := 1 to nColCount
               cEntry := "  o" + cName + "Col" + LTrim( Str( j ) ) + " AS TBrwColumn"
               INS_ComboAdd( h, cEntry )
               AAdd( aMap, { 2, hChild, j - 1 } )  // 0-based col index
            next
         endif

         // If it's a Folder/TPageControl, add its pages as sub-entries
         // "oFolderN:aPages[N] AS TFolderPage"
         if UI_GetType( hChild ) == 33  // CT_TABCONTROL2
            cTabsStr := UI_GetProp( hChild, "aTabs" )
            if ! Empty( cTabsStr )
               aTabsArr := hb_ATokens( cTabsStr, "|" )
               for jj := 1 to Len( aTabsArr )
                  cEntry := "o" + cName + ":aPages[" + LTrim( Str( jj ) ) + ;
                            "] AS TFolderPage  /* " + aTabsArr[jj] + " */"
                  INS_ComboAdd( h, cEntry )
                  AAdd( aMap, { 3, hChild, jj - 1 } )  // 0-based page idx
               next
            endif
         endif
      endif
   next

   _InsSetComboMap( aMap )

   // Select form (first entry)
   INS_ComboSelect( h, 0 )

return nil

function InspectorGetComboMap()
return _InsGetComboMap()

// Refresh inspector showing column properties
function InspectorRefreshColumn( hBrowse, nCol )
   local h := _InsGetData()
   local aProps
   if h != 0 .and. hBrowse != 0
      aProps := UI_BrowseGetColProps( hBrowse, nCol )
      if ! Empty( aProps )
         INS_RefreshWithData( h, hBrowse, aProps )
         INS_SetBrowseCol( h, nCol )  // Tell inspector we're editing a column
         INS_SetEvents( h, {} )  // Columns have no events
      endif
   endif
return nil

function InspectorClose()
   local h := _InsGetData()
   if h != 0
      INS_Destroy( h )
      _InsSetData( 0 )
   endif
return nil

function Inspector( hCtrl )
   InspectorOpen()
   InspectorRefresh( hCtrl )
return nil
