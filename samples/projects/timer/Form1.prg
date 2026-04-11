// Form1.prg
//--------------------------------------------------------------------

CLASS TForm1 FROM TForm

   // IDE-managed Components
   DATA oTimer1   // TTimer

   // Event handlers

   METHOD CreateForm()

ENDCLASS
//--------------------------------------------------------------------

METHOD CreateForm() CLASS TForm1

   ::Title  := "Form1"
   ::Left   := 100
   ::Top    := 100
   ::Width  := 400
   ::Height := 300

   COMPONENT ::oTimer1 TYPE CT_TIMER OF Self  // TTimer

   // Event wiring
   ::oTimer1:OnTimer := { || Timer1Timer( Self ) }

return nil
//--------------------------------------------------------------------

//--------------------------------------------------------------------
static function Timer1Timer( oForm )

   oForm:Title := Time()

return nil
