// Form1.prg
//--------------------------------------------------------------------
// One Label + one Edit + one Button exercise the Yes/No dropdown
// (every logical property opens a combobox now).
// One TDbfTable non-visual component exercises the cRDD dropdown
// (string-valued enum: DBFCDX / DBFNTX / DBFFPT).
//--------------------------------------------------------------------

CLASS TForm1 FROM TForm

   // IDE-managed Components
   DATA oLabel1     // TLabel
   DATA oEdit1      // TEdit
   DATA oButton1    // TButton
   DATA oDbfTable1  // TDbfTable (non-visual)

   // Event handlers
   METHOD Button1Click()

   METHOD CreateForm()

ENDCLASS

//--------------------------------------------------------------------

METHOD CreateForm() CLASS TForm1

   ::Title  := "DBF Table Demo"
   ::Left   := 120
   ::Top    := 120
   ::Width  := 420
   ::Height := 240
   ::AppTitle := "DbfTableDemo"

   @ 20,  20 SAY    ::oLabel1  PROMPT "Customer name:" OF Self SIZE 200, 24
   @ 20,  54 GET    ::oEdit1   VAR "" OF Self SIZE 260, 26
   @ 20,  96 BUTTON ::oButton1 PROMPT "Open table" OF Self SIZE 160, 32

   COMPONENT ::oDbfTable1 TYPE CT_DBFTABLE OF Self  // TDbfTable
   ::oDbfTable1:cFileName := "customers.dbf"
   ::oDbfTable1:cRDD      := "DBFCDX"

   ::oButton1:OnClick := { || ::Button1Click() }

return nil

//--------------------------------------------------------------------

METHOD Button1Click() CLASS TForm1

   // The real open/close logic is out of scope for this sample -
   // this method only proves the event wiring and the Yes/No dropdown
   // works on boolean handler-related properties.
   ::oLabel1:Text := "Opening " + ::oDbfTable1:cFileName + ;
                     " (RDD: " + ::oDbfTable1:cRDD + ")..."

return nil

//--------------------------------------------------------------------
