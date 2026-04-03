// Form1.prg - Hello World sample form for HarbourBuilder
//
// Demonstrates basic controls: Label, Edit, Button, CheckBox, ComboBox
// using xBase command syntax from hbbuilder.ch

#include "hbbuilder.ch"

// ---------------------------------------------------------------------------
// Form1() - Creates and activates the Hello World form
// ---------------------------------------------------------------------------
function Form1()

   local oForm
   local oLblWelcome, oEditName, oBtnHello, oBtnAbout
   local oChkDark, oCbxLang

   // --- Define the main form ---
   DEFINE FORM oForm TITLE "Hello World" SIZE 400, 350 FONT "Segoe UI", 11

   // --- Welcome label at the top ---
   @ 20, 20 SAY oLblWelcome PROMPT "Welcome to HarbourBuilder!" OF oForm SIZE 350

   // --- Name entry section ---
   @ 60, 20 SAY "Your name:" OF oForm SIZE 100
   @ 58, 130 GET oEditName VAR "" OF oForm SIZE 240, 24

   // --- "Say Hello" button ---
   // Clicking this button shows a greeting with the entered name
   @ 100, 20 BUTTON oBtnHello PROMPT "&Say Hello" OF oForm SIZE 120, 30 DEFAULT
   oBtnHello:OnClick := { || SayHello( oEditName ) }

   // --- "About" button ---
   // Shows version and project information
   @ 100, 150 BUTTON oBtnAbout PROMPT "&About" OF oForm SIZE 120, 30
   oBtnAbout:OnClick := { || ShowAbout() }

   // --- Dark mode checkbox ---
   @ 150, 20 CHECKBOX oChkDark PROMPT "Dark mode" OF oForm SIZE 200

   // --- Language selector ---
   @ 190, 20 SAY "Language:" OF oForm SIZE 100
   @ 188, 130 COMBOBOX oCbxLang OF oForm ;
      ITEMS { "English", "Spanish", "Portuguese" } SIZE 200
   oCbxLang:Value := 0

   // --- Activate the form (show it) ---
   ACTIVATE FORM oForm CENTERED

   // --- Clean up ---
   oForm:Destroy()

return nil

// ---------------------------------------------------------------------------
// SayHello() - Greets the user by the name entered in the Edit field
// ---------------------------------------------------------------------------
static function SayHello( oEdit )

   local cName := oEdit:GetText()

   if Empty( cName )
      MsgInfo( "Hello, World!" )
   else
      MsgInfo( "Hello, " + AllTrim( cName ) + "!" )
   endif

return nil

// ---------------------------------------------------------------------------
// ShowAbout() - Displays version and project information
// ---------------------------------------------------------------------------
static function ShowAbout()

   MsgInfo( "HarbourBuilder - Hello World Sample" + Chr(10) + ;
            "Version 1.0" + Chr(10) + ;
            "Built with Harbour + HarbourBuilder" )

return nil
