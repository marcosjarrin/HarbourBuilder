// Form1.prg
//--------------------------------------------------------------------

CLASS TForm1 FROM TForm

   // IDE-managed Components
   DATA oLabel1   // TLabel

   // Event handlers

   METHOD CreateForm()

ENDCLASS
//--------------------------------------------------------------------

METHOD CreateForm() CLASS TForm1

   ::Title  := "Form1"
   ::Left   := 1008
   ::Top    := 309
   ::Width  := 400
   ::Height := 300

   @ 80, 88 SAY ::oLabel1 PROMPT "Hello world" OF Self SIZE 215
   ::oLabel1:oFont := "Georgia,36,00FF2E"

return nil
//--------------------------------------------------------------------
