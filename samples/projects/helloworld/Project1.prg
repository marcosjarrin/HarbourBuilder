// Project1.prg - Hello World project entry point
//
// Standard HarbourBuilder project main file.
// Creates and shows Form1.

#include "hbbuilder.ch"

REQUEST HB_GT_GUI_DEFAULT

// ---------------------------------------------------------------------------
// Main() - Application entry point
// ---------------------------------------------------------------------------
function Main()

   Form1()

return nil

// ---------------------------------------------------------------------------
// MsgInfo() - Displays an information message box
// ---------------------------------------------------------------------------
function MsgInfo( cMsg )

   W32_MsgBox( cMsg, "Info" )

return nil

// Framework classes
#include "classes.prg"

#pragma BEGINDUMP
#include <hbapi.h>
#include <windows.h>
HB_FUNC( W32_MSGBOX )
{
   MessageBoxA( GetActiveWindow(), hb_parc(1), hb_parc(2), MB_OK | MB_ICONINFORMATION );
}
#pragma ENDDUMP
