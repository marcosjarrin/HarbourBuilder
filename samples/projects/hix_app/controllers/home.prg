#include "hbbuilder.ch"

function main()
   local aTickets := { ;
      { "TKT-001", "Login button broken",      "Open"   }, ;
      { "TKT-002", "Dashboard loads slowly",   "In Progress" }, ;
      { "TKT-003", "Export CSV not working",   "Open"   }, ;
      { "TKT-004", "Dark mode contrast issue", "Closed" }  ;
   }
   local cUser := UGet( "user" )
   if Empty( cUser ); cUser := "Guest"; endif
   UView( "views/home.html", aTickets, cUser )
return nil
