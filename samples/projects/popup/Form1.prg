// Form1.prg
//--------------------------------------------------------------------

CLASS TForm1 FROM TForm

   // IDE-managed Components
   DATA oPopup1   // TPopupMenu
   DATA oButton1   // TButton
   DATA oStatus1   // TLabel

   // Event handlers

   METHOD CreateForm()

ENDCLASS
//--------------------------------------------------------------------

METHOD CreateForm() CLASS TForm1

   ::Title  := "TPopupMenu Sample"
   ::Left   := 807
   ::Top    := 313
   ::Width  := 480
   ::Height := 280

   COMPONENT ::oPopup1 TYPE CT_POPUPMENU OF Self  // TPopupMenu
   DEFINE POPUPMENU ::oPopup1
      MENUITEM "Cu&t" ACTION PopAction( Self, "Cut" )
      MENUITEM "&Copy" ACTION PopAction( Self, "Copy" )
      MENUITEM "&Paste" ACTION PopAction( Self, "Paste" )
      MENUSEPARATOR
      DEFINE POPUP "&Format"
         MENUITEM "&Bold" ACTION PopAction( Self, "Format > Bold" )
         MENUITEM "&Italic" ACTION PopAction( Self, "Format > Italic" )
         MENUITEM "&Underline" ACTION PopAction( Self, "Format > Underline" )
      END POPUP
      MENUSEPARATOR
      MENUITEM "Select &All" ACTION PopAction( Self, "Select All" )
   END POPUPMENU
   @ 96, 60 BUTTON ::oButton1 PROMPT "Show Popup" OF Self SIZE 120, 32
   @ 200, 16 SAY ::oStatus1 PROMPT "Click the button to open the context menu." OF Self SIZE 329

return nil
//--------------------------------------------------------------------

// Popup handlers
//--------------------------------------------------------------------
static function PopAction( oForm, cWhat )
   if oForm:oStatus1 != nil
      oForm:oStatus1:Text := "Picked: " + cWhat
   endif
return nil
