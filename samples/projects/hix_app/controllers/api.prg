#include "hbbuilder.ch"

function main()
   local hInfo := { ;
      "server"  => "HarbourBuilder/HIX", ;
      "time"    => Time(), ;
      "date"    => Date(), ;
      "method"  => UServer("REQUEST_METHOD"), ;
      "path"    => UServer("REQUEST_URI") ;
   }
   UAddHeader( "Content-Type", "application/json" )
   UWrite( hb_jsonEncode( hInfo ) )
return nil
