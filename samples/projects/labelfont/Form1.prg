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
   ::Left   := 1122
   ::Top    := 377
   ::Width  := 603
   ::Height := 441
   ::FontName := "Segoe UI"
   ::FontSize := 9
   ::Color  := 2960685

   @ 112, 152 SAY ::oLabel1 PROMPT "Hello" OF Self SIZE 240, 104
   ::oLabel1:oFont := "Georgia,60,00FF2E"

return nil
//--------------------------------------------------------------------
