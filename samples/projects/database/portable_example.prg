// portable_example.prg - Database-agnostic code using TDatabase interface
// Shows how the same code works with any database by changing one line
//
// This is the key benefit of the unified TDatabase architecture:
// switch from SQLite to MySQL/PostgreSQL by changing only the constructor.
//
// Run from: samples/projects/database/

#include "hbbuilder.ch"

function Main()

   local oDb

   ? "=== Portable Database Example ==="
   ? "Shows the same API working with different backends"
   ?

   // --- Using SQLite (works out of the box) ---
   ? "--- SQLite ---"
   oDb := TSQLite():New()
   oDb:cDatabase := "portable_test.sqlite"
   TestDatabase( oDb )

   ?
   // --- Using DBF (native Harbour, always available) ---
   ? "--- DBF (via SQL emulation) ---"
   oDb := TDBFTable():New()
   oDb:cDatabase := "portable_test.dbf"
   TestDBF( oDb )

   ?
   // --- These would work if the libraries are installed: ---
   ? "--- MySQL (needs libmysqlclient) ---"
   oDb := TMySQL():New()
   oDb:cServer   := "localhost"
   oDb:cDatabase := "testdb"
   oDb:cUser     := "root"
   if ! oDb:Open()
      ? "  " + oDb:LastError()
   endif

   ?
   ? "--- PostgreSQL (needs libpq) ---"
   oDb := TPostgreSQL():New()
   oDb:cServer   := "localhost"
   oDb:cDatabase := "testdb"
   if ! oDb:Open()
      ? "  " + oDb:LastError()
   endif

   ?
   ? "--- MariaDB (wire-compatible with MySQL) ---"
   oDb := TMariaDB():New()
   oDb:cServer   := "localhost"
   if ! oDb:Open()
      ? "  " + oDb:LastError()
   endif

   ?
   ? "=== All drivers tested ==="
   ? "SQLite and DBF work out of the box."
   ? "MySQL/PostgreSQL/MariaDB/Firebird/Oracle/MongoDB need their client libraries."

return nil

// Generic database test - works with any TDatabase subclass that supports SQL
static function TestDatabase( oDb )

   local aRows, i

   if ! oDb:Open()
      ? "  Error: " + oDb:LastError()
      return nil
   endif

   ? "  Connected: " + oDb:cDriver + " (" + oDb:cDatabase + ")"

   // Create and populate
   oDb:Execute( "DROP TABLE IF EXISTS demo" )
   oDb:Execute( "CREATE TABLE demo (id INTEGER PRIMARY KEY, label TEXT, value REAL)" )
   oDb:Execute( "INSERT INTO demo VALUES (1, 'Alpha', 10.5)" )
   oDb:Execute( "INSERT INTO demo VALUES (2, 'Beta', 20.3)" )
   oDb:Execute( "INSERT INTO demo VALUES (3, 'Gamma', 30.7)" )

   // Query
   aRows := oDb:Query( "SELECT id, label, value FROM demo ORDER BY id" )
   ? "  Rows: " + LTrim(Str(Len(aRows)))
   for i := 1 to Len( aRows )
      ? "    " + LTrim(Str(aRows[i][1])) + " " + aRows[i][2] + " " + LTrim(Str(aRows[i][3]))
   next

   oDb:Close()
   ? "  Closed"

return nil

// DBF-specific test (no SQL, uses native methods)
static function TestDBF( oDb )

   // Create DBF
   if ! File( oDb:cDatabase )
      dbCreate( oDb:cDatabase, { ;
         { "ID",    "N", 5, 0 }, ;
         { "LABEL", "C", 20, 0 }, ;
         { "VALUE", "N", 10, 2 } } )
   endif

   if ! oDb:Open()
      ? "  Error: " + oDb:LastError()
      return nil
   endif

   ? "  Connected: " + oDb:cDriver + " (" + oDb:cDatabase + ")"

   // Append records
   oDb:Append(); oDb:FieldPut(1, 1); oDb:FieldPut(2, "Alpha"); oDb:FieldPut(3, 10.5)
   oDb:Append(); oDb:FieldPut(1, 2); oDb:FieldPut(2, "Beta");  oDb:FieldPut(3, 20.3)
   oDb:Append(); oDb:FieldPut(1, 3); oDb:FieldPut(2, "Gamma"); oDb:FieldPut(3, 30.7)

   ? "  Records: " + LTrim(Str(oDb:RecCount()))

   oDb:GoTop()
   while ! oDb:Eof()
      ? "    " + LTrim(Str(oDb:FieldGet(1))) + " " + AllTrim(oDb:FieldGet(2)) + " " + LTrim(Str(oDb:FieldGet(3)))
      oDb:Skip()
   enddo

   oDb:Close()
   ? "  Closed"

return nil
