// Form1.prg
//--------------------------------------------------------------------

CLASS TForm1 FROM TForm

   // IDE-managed Components
   DATA oWebServer1   // TWebServer
   DATA oBtnStart   // TButton
   DATA oBtnStop   // TButton
   DATA oBtnBrowser   // TButton
   DATA oLabel   // TLabel
   DATA oWebView1   // TWebView

   // Event handlers

   METHOD CreateForm()
   METHOD OnStartClick()
   METHOD OnStopClick()
   METHOD OnBrowserClick()

ENDCLASS
//--------------------------------------------------------------------

METHOD CreateForm() CLASS TForm1

   ::Title  := "HIX App Demo"
   ::Width  := 900
   ::Height := 650

   COMPONENT ::oWebServer1 TYPE CT_WEBSERVER OF Self  // TWebServer @ 808,8
   ::oWebServer1:nPort := 8081

   @ 10, 10 BUTTON ::oBtnStart PROMPT "Start Server" OF Self SIZE 120, 32
   ::oBtnStart:oFont := ".AppleSystemUIFont,12"
   @ 10, 140 BUTTON ::oBtnStop PROMPT "Stop Server" OF Self SIZE 120, 32
   ::oBtnStop:oFont := ".AppleSystemUIFont,12"
   @ 10, 270 BUTTON ::oBtnBrowser PROMPT "Open in Browser" OF Self SIZE 130, 32
   ::oBtnBrowser:oFont := ".AppleSystemUIFont,12"
   @ 16, 410 SAY ::oLabel PROMPT "Server stopped" OF Self SIZE 360
   ::oLabel:oFont := ".AppleSystemUIFont,12"
   @ 50, 10 WEBVIEW ::oWebView1 OF Self SIZE 880, 580
   ::oWebView1:oFont := ".AppleSystemUIFont,12"

   // Event wiring
   ::oBtnStart:OnClick   := { || ::OnStartClick() }
   ::oBtnStop:Enabled    := .F.
   ::oBtnStop:OnClick    := { || ::OnStopClick() }
   ::oBtnBrowser:Enabled := .F.
   ::oBtnBrowser:OnClick := { || ::OnBrowserClick() }

return nil
//--------------------------------------------------------------------

METHOD OnStartClick() CLASS TForm1

   // HIX-style routes: string path to controller .prg
   // cRoot is resolved relative to the project folder at runtime
   ::oWebServer1:aRoutes := {}
   ::oWebServer1:AddRoute( "GET", "/",        "controllers/home.prg" )
   ::oWebServer1:AddRoute( "GET", "/api/info", "controllers/api.prg"  )

   ::oWebServer1:Start()
   if ::oWebServer1:lRunning
      ::oLabel:Text := "Running: http://localhost:" + hb_ntos( ::oWebServer1:nPort ) + "/"
      ::oWebView1:Navigate( "http://localhost:" + hb_ntos( ::oWebServer1:nPort ) + "/" )
      ::oBtnStart:Enabled   := .F.
      ::oBtnStop:Enabled    := .T.
      ::oBtnBrowser:Enabled := .T.
   endif

return nil

METHOD OnStopClick() CLASS TForm1
   ::oWebServer1:Stop()
   ::oLabel:Text := "Server stopped"
   ::oWebView1:Navigate( "about:blank" )
   ::oBtnStart:Enabled   := .T.
   ::oBtnStop:Enabled    := .F.
   ::oBtnBrowser:Enabled := .F.
return nil

METHOD OnBrowserClick() CLASS TForm1
   MAC_ShellExec( "open http://localhost:" + hb_ntos( ::oWebServer1:nPort ) + "/" )
return nil
