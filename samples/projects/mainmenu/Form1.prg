// Form1.prg - TMainMenu cross-platform sample
//
// IDE-loadable form (CLASS TForm1 FROM TForm). Showcases the runtime DSL:
//
//   COMPONENT ::oMenu1 TYPE CT_MAINMENU OF Self     // creates TMainMenu
//   ::oMenu1:aOnClick := { ... }                    // one slot per node
//   DEFINE MENUBAR ::oMenu1
//      DEFINE POPUP "&File"
//         MENUITEM "&New" ACTION FileNew(Self) ACCEL "Ctrl+N"
//         ...
//      END POPUP
//   END MENUBAR
//
// The same source compiles on Win32, macOS and Linux: each backend maps
// CT_MAINMENU to its native menu primitive (HMENU / NSMenu / GtkMenuBar).
// At click time the framework walks aOnClick by node index and evaluates
// the matching codeblock — popups and separators occupy a slot too, so
// their entry in aOnClick is nil.
//--------------------------------------------------------------------

CLASS TForm1 FROM TForm

   // IDE-managed Components
   DATA oMenu1     // TMainMenu
   DATA oMemo1     // TEdit
   DATA oStatus1   // TLabel

   METHOD CreateForm()

ENDCLASS
//--------------------------------------------------------------------

METHOD CreateForm() CLASS TForm1

   ::Title    := "TMainMenu Sample"
   ::Width    := 640
   ::Height   := 480
   ::FontName := "Segoe UI"
   ::FontSize := 10

   COMPONENT ::oMenu1 TYPE CT_MAINMENU OF Self  // TMainMenu

   // aOnClick must align 1:1 with the node order below.
   // popups and separators get nil entries.
   ::oMenu1:aOnClick := { ;
      nil                              , ;  //  1  POPUP   &File
      {|| FileNew ( Self )            }, ;  //  2  &New
      {|| FileOpen( Self )            }, ;  //  3  &Open...
      {|| FileSave( Self )            }, ;  //  4  &Save
      nil                              , ;  //  5  ---
      {|| Self:Close()                }, ;  //  6  E&xit
      nil                              , ;  //  7  POPUP   &Edit
      {|| EditAction( Self, "Cut"   ) }, ;  //  8  Cu&t
      {|| EditAction( Self, "Copy"  ) }, ;  //  9  &Copy
      {|| EditAction( Self, "Paste" ) }, ;  // 10  &Paste
      nil                              , ;  // 11  POPUP   &Help
      {|| ShowAbout()                 }  ;  // 12  &About...
   }

   DEFINE MENUBAR ::oMenu1

      DEFINE POPUP "&File"
         MENUITEM "&New"        ACTION FileNew( Self )       ACCEL "Ctrl+N"
         MENUITEM "&Open..."    ACTION FileOpen( Self )      ACCEL "Ctrl+O"
         MENUITEM "&Save"       ACTION FileSave( Self )      ACCEL "Ctrl+S"
         MENUSEPARATOR
         MENUITEM "E&xit"       ACTION Self:Close()          ACCEL "Alt+F4"
      END POPUP

      DEFINE POPUP "&Edit"
         MENUITEM "Cu&t"        ACTION EditAction( Self, "Cut"   ) ACCEL "Ctrl+X"
         MENUITEM "&Copy"       ACTION EditAction( Self, "Copy"  ) ACCEL "Ctrl+C"
         MENUITEM "&Paste"      ACTION EditAction( Self, "Paste" ) ACCEL "Ctrl+V"
      END POPUP

      DEFINE POPUP "&Help"
         MENUITEM "&About..."   ACTION ShowAbout()           ACCEL "F1"
      END POPUP

   END MENUBAR

   // Editing area + status line
   @ 0, 0 GET ::oMemo1 VAR "Pick any menu item to see it dispatch..." ;
      OF Self SIZE 624, 400

   @ 410, 10 SAY ::oStatus1 PROMPT "Ready" OF Self SIZE 600

return nil
//--------------------------------------------------------------------

// Menu handlers — each updates the status line so the click is visible
//--------------------------------------------------------------------
static function FileNew( oForm )
   oForm:oMemo1:Text := ""
   SetStatus( oForm, "File > New" )
return nil

static function FileOpen( oForm )
   SetStatus( oForm, "File > Open..." )
   MsgInfo( "OpenDialog would appear here." )
return nil

static function FileSave( oForm )
   SetStatus( oForm, "File > Save" )
   MsgInfo( "SaveDialog would appear here." )
return nil

static function EditAction( oForm, cWhat )
   SetStatus( oForm, "Edit > " + cWhat )
return nil

static function ShowAbout()
   MsgInfo( "TMainMenu Sample 1.0" + Chr(10) + ;
            "Built with HarbourBuilder" + Chr(10) + ;
            "DEFINE MENUBAR DSL - Win/Mac/Linux" )
return nil

static function SetStatus( oForm, cMsg )
   if oForm:oStatus1 != nil
      oForm:oStatus1:Caption := cMsg
   endif
return nil
