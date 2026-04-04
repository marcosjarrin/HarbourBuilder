// dbf_example.prg - DBF table example using TDBFTable
// Demonstrates creating, writing, and reading a native DBF file
//
// Run from: samples/projects/database/

#include "hbbuilder.ch"

function Main()

   local oDb, i, aStruct

   ? "=== TDBFTable Example ==="
   ?

   // Create a new DBF file
   dbCreate( "contacts.dbf", { ;
      { "NAME",  "C", 30, 0 }, ;
      { "EMAIL", "C", 40, 0 }, ;
      { "AGE",   "N",  3, 0 }, ;
      { "ACTIVE","L",  1, 0 } } )

   // Open with TDBFTable
   oDb := TDBFTable():New()
   oDb:cDatabase := "contacts.dbf"
   oDb:cRDD      := "DBFCDX"

   if ! oDb:Open()
      ? "Error: " + oDb:LastError()
      return nil
   endif

   ? "Connected to: " + oDb:cDatabase
   ? "Driver: " + oDb:cDriver
   ?

   // Insert records
   ? "Inserting 5 records..."
   local aNames := { "Alice", "Bob", "Carol", "David", "Eve" }
   local aEmails := { "alice@dev.io", "bob@dev.io", "carol@dev.io", "david@dev.io", "eve@dev.io" }
   local aAges := { 28, 34, 22, 45, 31 }

   for i := 1 to 5
      oDb:Append()
      oDb:FieldPut( 1, aNames[i] )
      oDb:FieldPut( 2, aEmails[i] )
      oDb:FieldPut( 3, aAges[i] )
      oDb:FieldPut( 4, .T. )
   next

   ? "Records inserted: " + LTrim(Str(oDb:RecCount()))
   ?

   // Read all records
   ? "Reading all records:"
   ? PadR("Name", 30) + " " + PadR("Email", 40) + " Age"
   ? Replicate("-", 76)

   oDb:GoTop()
   while ! oDb:Eof()
      ? PadR(AllTrim(oDb:FieldGet(1)), 30) + " " + ;
        PadR(AllTrim(oDb:FieldGet(2)), 40) + " " + ;
        LTrim(Str(oDb:FieldGet(3)))
      oDb:Skip()
   enddo

   ?
   ? "Structure:"
   aStruct := oDb:Structure()
   for i := 1 to Len( aStruct )
      ? "  " + PadR(aStruct[i][1], 10) + " " + aStruct[i][2] + " " + LTrim(Str(aStruct[i][3]))
   next

   oDb:Close()
   ?
   ? "=== Done ==="

return nil
