// Project1.prg
//--------------------------------------------------------------------
#include "hbbuilder.ch"
//--------------------------------------------------------------------

PROCEDURE Main()

   local oApp, oForm1

   oApp := TApplication():New()
   oApp:Title := "TMariaDB Sample"

   oForm1 := TForm1():New()
   oApp:CreateForm( oForm1 )

   oForm1:oDb1:bOnConnect    := { || oForm1:oStatus1:Text := "Connected to MariaDB " + ;
                                       oForm1:oDb1:cServer + ":" + ;
                                       hb_ValToStr( oForm1:oDb1:nPort ) }
   oForm1:oDb1:bOnDisconnect := { || oForm1:oStatus1:Text := "Disconnected" }
   oForm1:oDb1:bOnError      := { | cMsg | oForm1:oStatus1:Text := "ERROR: " + cMsg }

   oForm1:oBtnConnect:OnClick := { || ConnectAndList( oForm1 ) }
   oForm1:oBtnExec:OnClick    := { || ExecQuery( oForm1 ) }

   oApp:Run()

return
//--------------------------------------------------------------------

static function ConnectAndList( oForm )

   local aTables, i

   oForm:oDb1:cServer   := oForm:oEdHost:Text
   oForm:oDb1:nPort     := Val( oForm:oEdPort:Text )
   oForm:oDb1:cUser     := oForm:oEdUser:Text
   oForm:oDb1:cPassword := oForm:oEdPass:Text
   oForm:oDb1:cDatabase := oForm:oEdDb:Text

   if oForm:oDb1:IsConnected()
      oForm:oDb1:Close()
   endif
   if ! oForm:oDb1:Open(); return nil; endif

   aTables := oForm:oDb1:Tables()
   oForm:oLstTables:Clear()
   for i := 1 to Len( aTables )
      oForm:oLstTables:Add( aTables[ i ] )
   next
   oForm:oStatus1:Text := "Connected. " + hb_ValToStr( Len( aTables ) ) + " table(s)."

return nil

//--------------------------------------------------------------------
static function ExecQuery( oForm )

   local cSQL, aRows, aRow, cOut := "", i, j

   if ! oForm:oDb1:IsConnected()
      oForm:oStatus1:Text := "Connect first."
      return nil
   endif

   cSQL := AllTrim( oForm:oMemSQL:Text )
   if Empty( cSQL ); return nil; endif

   if Upper( Left( cSQL, 6 ) ) == "SELECT" .or. Upper( Left( cSQL, 4 ) ) == "SHOW"
      aRows := oForm:oDb1:Query( cSQL )
      cOut  := hb_ValToStr( Len( aRows ) ) + " row(s):" + hb_eol()
      for i := 1 to Min( Len( aRows ), 200 )
         aRow := aRows[ i ]
         for j := 1 to Len( aRow )
            cOut += iif( j > 1, " | ", "" ) + hb_ValToStr( aRow[ j ] )
         next
         cOut += hb_eol()
      next
   else
      if oForm:oDb1:Execute( cSQL )
         cOut := "OK. Last insert id: " + hb_ValToStr( oForm:oDb1:LastInsertId() )
      else
         cOut := "FAIL: " + oForm:oDb1:LastError()
      endif
   endif

   oForm:oMemOut:Text := cOut

return nil
//--------------------------------------------------------------------
