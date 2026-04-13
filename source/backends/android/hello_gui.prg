// hello_gui.prg - minimal GUI demo for the Android backend (iter 1)
//
// Uses the UI_* API directly (bypassing classes.prg) to prove the JNI
// plumbing end-to-end. Once this runs on the emulator we start wiring
// the IDE's form designer to emit equivalent UI_* calls.

PROCEDURE Main()

   LOCAL hForm, hLabel, hEdit, hBtn

   hForm  := UI_FormNew( "Hello Android", 400, 600 )
   hLabel := UI_LabelNew(  hForm, "Escribe tu nombre:", 20,  20, 300,  30 )
   hEdit  := UI_EditNew(   hForm, "",                   20,  60, 300,  50 )
   hBtn   := UI_ButtonNew( hForm, "Saludar",            20, 130, 300,  50 )

   UI_OnClick( hBtn, ;
      {|| UI_SetText( hLabel, "Hola, " + UI_GetText( hEdit ) + " !" ) } )

   UI_FormRun( hForm )   // no-op on Android; Activity owns the event loop

RETURN
