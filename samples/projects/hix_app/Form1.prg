#include "hbbuilder.ch"

CLASS Form1 FROM TForm
   DATA oServer
   DATA oBtnStart
   DATA oBtnStop
   DATA oLabel
   DATA oWebView

   METHOD New() CONSTRUCTOR
   METHOD OnStartClick()
   METHOD OnStopClick()
ENDCLASS

METHOD New() CLASS Form1
   local cRoot

   ::Super:New()
   ::cTitle := "HIX App Demo"
   ::nWidth  := 900
   ::nHeight := 650

   // Root is the hix_app folder itself
   cRoot := RTrim( hb_DirBase(), "/" )

   ::oServer := TWebServer():New()
   ::oServer:nPort := 8081
   ::oServer:cRoot := cRoot

   // HIX-style routes: string path to controller .prg
   ::oServer:AddRoute( "GET",  "/",         "controllers/home.prg" )
   ::oServer:AddRoute( "GET",  "/api/info", "controllers/api.prg"  )

   ::oBtnStart := TButton():New( 10, 10, 120, 32, "Start Server", Self )
   ::oBtnStart:bOnClick := { || ::OnStartClick() }

   ::oBtnStop := TButton():New( 140, 10, 120, 32, "Stop Server", Self )
   ::oBtnStop:bOnClick := { || ::OnStopClick() }
   ::oBtnStop:lEnabled := .F.

   ::oLabel := TLabel():New( 270, 16, 360, 20, "Server stopped", Self )

   ::oWebView := TWebView():New( 10, 50, 880, 580, Self )
   ::oWebView:cURL := "about:blank"

return Self

METHOD OnStartClick() CLASS Form1
   ::oServer:Start()
   if ::oServer:lRunning
      ::oLabel:cText    := "Running: http://localhost:8081/"
      ::oWebView:cURL   := "http://localhost:8081/"
      ::oBtnStart:lEnabled := .F.
      ::oBtnStop:lEnabled  := .T.
   endif
return nil

METHOD OnStopClick() CLASS Form1
   ::oServer:Stop()
   ::oLabel:cText := "Server stopped"
   ::oBtnStart:lEnabled := .T.
   ::oBtnStop:lEnabled  := .F.
return nil
