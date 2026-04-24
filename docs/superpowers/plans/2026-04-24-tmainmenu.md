# TMainMenu Component Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a TMainMenu non-visual component to HarbourBuilder's Linux IDE that lets users design a menu bar visually and generates native GTK3 menus at runtime.

**Architecture:** The component lives entirely in `gtk3_core.c` (C struct + runtime attachment + property serialization), `gtk3_inspector.c` (new 'M' property type + Menu Items Editor dialog), and `hbbuilder_linux.prg` (code generation and parsing). No new files are created — all changes extend existing files following established patterns.

**Tech Stack:** GTK3 (C), Harbour (.prg), existing `UI_MENUPOPUPADD` / `UI_MENUITEMADDEX` / `UI_MENUSEPADD` infrastructure already in gtk3_core.c.

---

## File Map

| File | What changes |
|------|-------------|
| `source/backends/gtk3/gtk3_core.c` | Add CT_MAINMENU constant, HBMenuNode/HBMainMenu structs, register in IsNonVisualControl/defs[]/calloc switch, add HBMainMenu_Attach(), hook into HBForm_CreateAllChildren(), add aMenuItems to UI_GETALLPROPS/UI_SETPROP/UI_GETPROP |
| `source/backends/gtk3/gtk3_inspector.c` | Handle 'M' property type (display, non-editable, InsApplyValue), add OpenMenuEditor() dialog, call it from on_row_activated |
| `source/hbbuilder_linux.prg` | Add CT_MAINMENU to ComponentTypeFromName(), RegenerateFormCode() special case for CT_MAINMENU, RestoreFormFromCode() DEFINE MENUBAR parser |

---

## Task 1: CT_MAINMENU constant, structs, and size registration

**Files:**
- Modify: `source/backends/gtk3/gtk3_core.c`

- [ ] **Step 1: Add the CT_MAINMENU constant after the last CT_ block (around line 136)**

  Find the block ending with `#define CT_REPORTVIEWER 108` / `#define CT_BARCODEPRINTER 109`. Add after it:

  ```c
  #define CT_MAINMENU   132
  ```

- [ ] **Step 2: Add HBMenuNode and HBMainMenu struct definitions**

  Find the `HBTimer` struct (search for `typedef struct { HBControl base; int FInterval;`). Add the following immediately before it:

  ```c
  #define MAX_MENU_NODES 128

  typedef struct {
     char  szCaption[128];
     char  szShortcut[32];
     char  szHandler[128];
     int   bSeparator;
     int   bEnabled;
     int   nParent;
     int   nLevel;
  } HBMenuNode;

  typedef struct {
     HBControl   base;
     HBMenuNode  FNodes[MAX_MENU_NODES];
     int         FNodeCount;
  } HBMainMenu;
  ```

- [ ] **Step 3: Add CT_MAINMENU to the calloc size switch**

  In `HBForm_CreateControlOfType()`, find the switch that assigns `sz`:
  ```c
  case CT_TIMER:    sz = sizeof(HBTimer); break;
  ```
  Add immediately after it:
  ```c
  case CT_MAINMENU: sz = sizeof(HBMainMenu); break;
  ```

- [ ] **Step 4: Add CT_MAINMENU to the defs[] palette array**

  Find the `defs[]` entry for CT_TIMER:
  ```c
  { CT_TIMER,      "TTimer",          "",            32,  32 },
  ```
  Add immediately after it:
  ```c
  { CT_MAINMENU,   "TMainMenu",       "",            32,  32 },
  ```

- [ ] **Step 5: Build and verify it compiles**

  ```bash
  cd /home/anto/HarbourBuilder && ./build_linux.sh
  ```
  Expected: builds successfully. The component won't appear in the palette yet.

- [ ] **Step 6: Commit**

  ```bash
  git add source/backends/gtk3/gtk3_core.c
  git commit -m "feat: add CT_MAINMENU constant, HBMenuNode/HBMainMenu structs, register in defs[] and calloc switch"
  ```

---

## Task 2: Register CT_MAINMENU as non-visual

**Files:**
- Modify: `source/backends/gtk3/gtk3_core.c`

- [ ] **Step 1: Add CT_MAINMENU to IsNonVisualControl()**

  Find the `IsNonVisualControl()` function (around line 421). The switch has many cases. Find the last case line before `return 1;`. It currently ends with:
  ```c
  case CT_PRINTDIALOG: case CT_BARCODEPRINTER:
     return 1;
  ```
  Change it to:
  ```c
  case CT_PRINTDIALOG: case CT_BARCODEPRINTER:
  case CT_MAINMENU:
     return 1;
  ```

- [ ] **Step 2: Build and run the IDE**

  ```bash
  cd /home/anto/HarbourBuilder && ./build_linux.sh
  ./bin/hbbuilder_linux
  ```
  Expected: the IDE starts. Open a form, look in the Standard palette tab — you should now see the TMainMenu component icon (generic 32x32 icon). Dragging it onto the form should place a non-visual icon below the canvas.

- [ ] **Step 3: Commit**

  ```bash
  git add source/backends/gtk3/gtk3_core.c
  git commit -m "feat: register CT_MAINMENU as non-visual component in IsNonVisualControl()"
  ```

---

## Task 3: ComponentTypeFromName in hbbuilder_linux.prg

**Files:**
- Modify: `source/hbbuilder_linux.prg`

- [ ] **Step 1: Add CT_MAINMENU to ComponentTypeFromName()**

  Find `ComponentTypeFromName()` (around line 3297). Find the last case before `endcase`:
  ```harbour
  case cName == "CT_COMPARRAY";     return 131
  endcase
  ```
  Change to:
  ```harbour
  case cName == "CT_COMPARRAY";     return 131
  case cName == "CT_MAINMENU";      return 132
  endcase
  ```

- [ ] **Step 2: Build and verify**

  ```bash
  cd /home/anto/HarbourBuilder && ./build_linux.sh
  ```
  Expected: builds successfully.

- [ ] **Step 3: Commit**

  ```bash
  git add source/hbbuilder_linux.prg
  git commit -m "feat: add CT_MAINMENU to ComponentTypeFromName()"
  ```

---

## Task 4: aMenuItems property in UI_GETALLPROPS, UI_SETPROP, UI_GETPROP

**Files:**
- Modify: `source/backends/gtk3/gtk3_core.c`

### Serialization format

Each node is one token. Nodes are separated by `|`. Within a node, six fields are separated by `\x01` (ASCII SOH — avoids conflicts with captions/shortcuts that may contain pipes):

```
Caption\x01Shortcut\x01Handler\x01Enabled\x01Level\x01Parent
```

A separator node uses empty Caption and `bSeparator=1` indicated by `---` as caption:

```
---\x01\x01\x010\x011\x010
```

- [ ] **Step 1: Add `case CT_MAINMENU:` in UI_GETALLPROPS to expose aMenuItems as type 'M'**

  Find `UI_GETALLPROPS` (around line 4026). Find the `case CT_TIMER:` block:
  ```c
  case CT_TIMER:
     ADD_N("nInterval",((HBTimer*)p)->FInterval,"Behavior");
     break;
  ```
  Add before it:
  ```c
  case CT_MAINMENU:
  {
     HBMainMenu * m = (HBMainMenu *)p;
     char szSerial[4096] = "";
     int pos = 0;
     for( int i = 0; i < m->FNodeCount && pos < (int)sizeof(szSerial) - 64; i++ ) {
        if( i > 0 ) szSerial[pos++] = '|';
        const char * cap = m->FNodes[i].bSeparator ? "---" : m->FNodes[i].szCaption;
        int n = snprintf( szSerial + pos, sizeof(szSerial) - pos,
           "%s\x01%s\x01%s\x01%d\x01%d\x01%d",
           cap,
           m->FNodes[i].szShortcut,
           m->FNodes[i].szHandler,
           m->FNodes[i].bEnabled,
           m->FNodes[i].nLevel,
           m->FNodes[i].nParent );
        if( n > 0 ) pos += n;
     }
     pRow = hb_itemArrayNew(4);
     hb_arraySetC( pRow, 1, "aMenuItems" );
     hb_arraySetC( pRow, 2, szSerial );
     hb_arraySetC( pRow, 3, "Data" );
     hb_arraySetC( pRow, 4, "M" );
     hb_arrayAdd( pArray, pRow );
     hb_itemRelease( pRow );
     break;
  }
  ```

- [ ] **Step 2: Add aMenuItems handling in UI_SETPROP**

  Find `UI_SETPROP` (search for `HB_FUNC( UI_SETPROP )`). Find the `aItems` handler block:
  ```c
  else if( strcasecmp(szProp,"aItems")==0 && HB_ISCHAR(3) &&
  ```
  Add before the closing `}` of `UI_SETPROP` (find the last `else if` block and add after it):
  ```c
  else if( strcasecmp(szProp,"aMenuItems")==0 && HB_ISCHAR(3) &&
           p->FControlType == CT_MAINMENU )
  {
     HBMainMenu * m = (HBMainMenu *)p;
     const char * raw = hb_parc(3);
     m->FNodeCount = 0;
     memset( m->FNodes, 0, sizeof(m->FNodes) );
     while( *raw && m->FNodeCount < MAX_MENU_NODES )
     {
        /* Find end of this node token */
        const char * pipe = strchr( raw, '|' );
        int tokLen = pipe ? (int)(pipe - raw) : (int)strlen(raw);
        /* Parse 6 SOH-separated fields */
        char tok[512]; int tl = tokLen < 511 ? tokLen : 511;
        memcpy( tok, raw, tl ); tok[tl] = 0;
        int fi = m->FNodeCount;
        char * f0 = tok;
        char * f1 = strchr(f0, '\x01'); if(f1){*f1++=0;}else f1=(char*)"";
        char * f2 = f1?strchr(f1,'\x01'):NULL; if(f2){*f2++=0;}else f2=(char*)"";
        char * f3 = f2?strchr(f2,'\x01'):NULL; if(f3){*f3++=0;}else f3=(char*)"";
        char * f4 = f3?strchr(f3,'\x01'):NULL; if(f4){*f4++=0;}else f4=(char*)"";
        char * f5 = f4?strchr(f4,'\x01'):NULL; if(f5){*f5++=0;}else f5=(char*)"-1";
        m->FNodes[fi].bSeparator = (strcmp(f0,"---")==0) ? 1 : 0;
        if( !m->FNodes[fi].bSeparator )
           strncpy( m->FNodes[fi].szCaption, f0, sizeof(m->FNodes[fi].szCaption)-1 );
        strncpy( m->FNodes[fi].szShortcut, f1, sizeof(m->FNodes[fi].szShortcut)-1 );
        strncpy( m->FNodes[fi].szHandler,  f2, sizeof(m->FNodes[fi].szHandler)-1 );
        m->FNodes[fi].bEnabled = f3[0]?atoi(f3):1;
        m->FNodes[fi].nLevel   = f4[0]?atoi(f4):0;
        m->FNodes[fi].nParent  = f5[0]?atoi(f5):-1;
        m->FNodeCount++;
        if( !pipe ) break;
        raw = pipe + 1;
     }
  }
  ```

- [ ] **Step 3: Add aMenuItems handling in UI_GETPROP**

  Find `HB_FUNC( UI_GETPROP )`. Find where it handles `"aItems"` for combobox/listbox. After that block add:
  ```c
  else if( strcasecmp(szProp,"aMenuItems")==0 && p->FControlType==CT_MAINMENU )
  {
     HBMainMenu * m = (HBMainMenu *)p;
     char szSerial[4096] = "";
     int pos = 0;
     for( int i = 0; i < m->FNodeCount && pos < (int)sizeof(szSerial)-64; i++ ) {
        if( i > 0 ) szSerial[pos++] = '|';
        const char * cap = m->FNodes[i].bSeparator ? "---" : m->FNodes[i].szCaption;
        int n = snprintf( szSerial+pos, sizeof(szSerial)-pos,
           "%s\x01%s\x01%s\x01%d\x01%d\x01%d",
           cap,
           m->FNodes[i].szShortcut,
           m->FNodes[i].szHandler,
           m->FNodes[i].bEnabled,
           m->FNodes[i].nLevel,
           m->FNodes[i].nParent );
        if( n>0 ) pos+=n;
     }
     hb_retc( szSerial );
  }
  ```

- [ ] **Step 4: Build and verify**

  ```bash
  cd /home/anto/HarbourBuilder && ./build_linux.sh
  ```
  Expected: compiles successfully. Drop a TMainMenu on a form and open the inspector — it should show `aMenuItems` row with `(0 nodes) ...`.

- [ ] **Step 5: Commit**

  ```bash
  git add source/backends/gtk3/gtk3_core.c
  git commit -m "feat: add aMenuItems property (type 'M') to TMainMenu via UI_GETALLPROPS/UI_SETPROP/UI_GETPROP"
  ```

---

## Task 5: Inspector support for type 'M' (display and non-editable)

**Files:**
- Modify: `source/backends/gtk3/gtk3_inspector.c`

- [ ] **Step 1: Load the 'M' type value in InspectorPopulate (same as 'A')**

  In the property-loading loop (around line 207), find:
  ```c
  else if( d->rows[d->nRows].cType == 'A' )
  {
     /* Store raw pipe-separated value; InsRebuildStore shows "(N items)" */
     strncpy( d->rows[d->nRows].szValue, hb_arrayGetCPtr(pRow,2), 255 );
  }
  ```
  Add immediately after it:
  ```c
  else if( d->rows[d->nRows].cType == 'M' )
  {
     strncpy( d->rows[d->nRows].szValue, hb_arrayGetCPtr(pRow,2), 255 );
  }
  ```

- [ ] **Step 2: Display "(N nodes) ..." for 'M' type in InsRebuildStore**

  Find in `InsRebuildStore` the block:
  ```c
  if( d->rows[nReal].cType == 'A' )
  {
     const char * raw = d->rows[nReal].szValue;
     int nItems = 0;
     if( raw[0] ) { nItems = 1; for( const char * p = raw; *p; p++ ) if( *p == '|' ) nItems++; }
     snprintf( arrayDisp, sizeof(arrayDisp), "(%d items)  ...", nItems );
     dispValue = arrayDisp;
  }
  ```
  Add immediately after it:
  ```c
  else if( d->rows[nReal].cType == 'M' )
  {
     const char * raw = d->rows[nReal].szValue;
     int nNodes = 0;
     if( raw[0] ) { nNodes = 1; for( const char * p = raw; *p; p++ ) if( *p == '|' ) nNodes++; }
     snprintf( arrayDisp, sizeof(arrayDisp), "(%d nodes)  ...", nNodes );
     dispValue = arrayDisp;
  }
  ```

- [ ] **Step 3: Make 'M' type non-editable inline**

  Find the `editable` calculation (around line 315):
  ```c
  gboolean editable = (d->nTab == 0) &&
     (d->rows[nReal].cType != 'C' && d->rows[nReal].cType != 'F' &&
      d->rows[nReal].cType != 'A' &&
      !(d->rows[nReal].cType == 'N' && pEnumRow != NULL));
  ```
  Change to:
  ```c
  gboolean editable = (d->nTab == 0) &&
     (d->rows[nReal].cType != 'C' && d->rows[nReal].cType != 'F' &&
      d->rows[nReal].cType != 'A' && d->rows[nReal].cType != 'M' &&
      !(d->rows[nReal].cType == 'N' && pEnumRow != NULL));
  ```

- [ ] **Step 4: Make InsApplyValue pass 'M' as string (same as 'A')**

  Find in `InsApplyValue`:
  ```c
  if( d->rows[nReal].cType == 'S' || d->rows[nReal].cType == 'F' ||
      d->rows[nReal].cType == 'A' )
     hb_vmPushString( d->rows[nReal].szValue, strlen(d->rows[nReal].szValue) );
  ```
  Change to:
  ```c
  if( d->rows[nReal].cType == 'S' || d->rows[nReal].cType == 'F' ||
      d->rows[nReal].cType == 'A' || d->rows[nReal].cType == 'M' )
     hb_vmPushString( d->rows[nReal].szValue, strlen(d->rows[nReal].szValue) );
  ```

  Do the same in the `nBrowseCol >= 0` branch if it also checks `cType == 'A'` — search and update.

- [ ] **Step 5: Build and verify**

  ```bash
  cd /home/anto/HarbourBuilder && ./build_linux.sh && ./bin/hbbuilder_linux
  ```
  Drop TMainMenu on a form, open inspector — `aMenuItems` row shows `(0 nodes) ...` and is not inline-editable.

- [ ] **Step 6: Commit**

  ```bash
  git add source/backends/gtk3/gtk3_inspector.c
  git commit -m "feat: add 'M' property type support in inspector (display, non-editable, InsApplyValue)"
  ```

---

## Task 6: Menu Items Editor dialog

**Files:**
- Modify: `source/backends/gtk3/gtk3_inspector.c`

The editor is a GTK dialog with two panes. The left pane is a GtkTreeStore with two columns (Caption, Shortcut). The right pane is a form with Caption/Shortcut/OnClick entries and an Enabled checkbox.

- [ ] **Step 1: Add helper structs and the node array at the top of the editor**

  Add this forward declaration and data structure near the top of `gtk3_inspector.c` (before `on_row_activated`):

  ```c
  /* ===== Menu Items Editor ===== */
  #define MEI_MAX 128

  typedef struct {
     char  szCaption[128];
     char  szShortcut[32];
     char  szHandler[128];
     int   bSeparator;
     int   bEnabled;
     int   nLevel;
     int   nParent;
  } MEINode;

  typedef struct {
     MEINode     nodes[MEI_MAX];
     int         nCount;
     GtkWidget * tree;         /* GtkTreeView (left pane) */
     GtkWidget * eCaption;     /* GtkEntry */
     GtkWidget * eShortcut;    /* GtkEntry */
     GtkWidget * eHandler;     /* GtkEntry */
     GtkWidget * cbEnabled;    /* GtkCheckButton */
     int         nSel;         /* currently selected node index, -1 if none */
     int         bUpdating;    /* guard against recursive selection updates */
  } MEIDATA;
  ```

- [ ] **Step 2: Add MEI_Serialize — converts node array to pipe+SOH string**

  ```c
  static void MEI_Serialize( MEIDATA * d, char * out, int outLen )
  {
     int pos = 0;
     out[0] = 0;
     for( int i = 0; i < d->nCount && pos < outLen - 64; i++ ) {
        if( i > 0 ) out[pos++] = '|';
        const char * cap = d->nodes[i].bSeparator ? "---" : d->nodes[i].szCaption;
        int n = snprintf( out+pos, outLen-pos, "%s\x01%s\x01%s\x01%d\x01%d\x01%d",
           cap, d->nodes[i].szShortcut, d->nodes[i].szHandler,
           d->nodes[i].bEnabled, d->nodes[i].nLevel, d->nodes[i].nParent );
        if( n > 0 ) pos += n;
     }
  }
  ```

- [ ] **Step 3: Add MEI_Parse — fills node array from pipe+SOH string**

  ```c
  static void MEI_Parse( MEIDATA * d, const char * raw )
  {
     d->nCount = 0;
     if( !raw || !raw[0] ) return;
     while( *raw && d->nCount < MEI_MAX )
     {
        const char * pipe = strchr( raw, '|' );
        int tl = pipe ? (int)(pipe - raw) : (int)strlen(raw);
        char tok[512]; if(tl>511)tl=511;
        memcpy(tok,raw,tl); tok[tl]=0;
        int fi = d->nCount;
        char*f0=tok;
        char*f1=strchr(f0,'\x01'); if(f1){*f1++=0;}else f1=(char*)"";
        char*f2=f1?strchr(f1,'\x01'):NULL; if(f2){*f2++=0;}else f2=(char*)"";
        char*f3=f2?strchr(f2,'\x01'):NULL; if(f3){*f3++=0;}else f3=(char*)"";
        char*f4=f3?strchr(f3,'\x01'):NULL; if(f4){*f4++=0;}else f4=(char*)"";
        char*f5=f4?strchr(f4,'\x01'):NULL; if(f5){*f5++=0;}else f5=(char*)"-1";
        d->nodes[fi].bSeparator = strcmp(f0,"---")==0;
        strncpy(d->nodes[fi].szCaption, d->nodes[fi].bSeparator?"":f0, 127);
        strncpy(d->nodes[fi].szShortcut, f1, 31);
        strncpy(d->nodes[fi].szHandler,  f2, 127);
        d->nodes[fi].bEnabled = f3[0]?atoi(f3):1;
        d->nodes[fi].nLevel   = f4[0]?atoi(f4):0;
        d->nodes[fi].nParent  = f5[0]?atoi(f5):-1;
        d->nCount++;
        if(!pipe) break;
        raw = pipe+1;
     }
  }
  ```

- [ ] **Step 4: Add MEI_RebuildTree — fills GtkTreeStore from node array**

  ```c
  static void MEI_RebuildTree( MEIDATA * d )
  {
     GtkTreeStore * store = GTK_TREE_STORE(
        gtk_tree_view_get_model(GTK_TREE_VIEW(d->tree)) );
     gtk_tree_store_clear( store );

     /* iters[level] = parent iter for that level */
     GtkTreeIter iters[8];
     int hasIter[8] = {0};

     for( int i = 0; i < d->nCount; i++ ) {
        MEINode * n = &d->nodes[i];
        GtkTreeIter it;
        GtkTreeIter * parent = (n->nLevel>0 && hasIter[n->nLevel-1])
                                ? &iters[n->nLevel-1] : NULL;
        gtk_tree_store_append( store, &it, parent );
        const char * cap = n->bSeparator ? "──────" : n->szCaption;
        gtk_tree_store_set( store, &it,
           0, cap,
           1, n->szShortcut,
           2, i,   /* store node index */
           -1 );
        if( !n->bSeparator ) {
           iters[n->nLevel] = it;
           hasIter[n->nLevel] = 1;
           /* invalidate deeper levels */
           for(int lv=n->nLevel+1;lv<8;lv++) hasIter[lv]=0;
        }
     }
     gtk_tree_view_expand_all( GTK_TREE_VIEW(d->tree) );
  }
  ```

- [ ] **Step 5: Add MEI_SelectionChanged — loads selected node's props into right pane**

  ```c
  static void on_mei_selection_changed( GtkTreeSelection * sel, gpointer data )
  {
     MEIDATA * d = (MEIDATA *)data;
     if( d->bUpdating ) return;
     GtkTreeIter it;
     GtkTreeModel * model;
     if( !gtk_tree_selection_get_selected(sel, &model, &it) ) { d->nSel=-1; return; }
     int idx;
     gtk_tree_model_get( model, &it, 2, &idx, -1 );
     if( idx<0 || idx>=d->nCount ) { d->nSel=-1; return; }
     d->bUpdating = 1;
     d->nSel = idx;
     MEINode * n = &d->nodes[idx];
     gtk_entry_set_text( GTK_ENTRY(d->eCaption),  n->bSeparator ? "" : n->szCaption );
     gtk_entry_set_text( GTK_ENTRY(d->eShortcut), n->szShortcut );
     gtk_entry_set_text( GTK_ENTRY(d->eHandler),  n->szHandler );
     gtk_toggle_button_set_active( GTK_TOGGLE_BUTTON(d->cbEnabled), n->bEnabled );
     gtk_widget_set_sensitive( d->eCaption,  !n->bSeparator );
     gtk_widget_set_sensitive( d->eShortcut, !n->bSeparator );
     gtk_widget_set_sensitive( d->eHandler,  !n->bSeparator );
     d->bUpdating = 0;
  }
  ```

- [ ] **Step 6: Add right-pane change callbacks**

  ```c
  static void on_mei_caption_changed( GtkEditable * e, gpointer data )
  {
     MEIDATA * d = (MEIDATA *)data;
     if( d->bUpdating || d->nSel<0 ) return;
     strncpy( d->nodes[d->nSel].szCaption,
              gtk_entry_get_text(GTK_ENTRY(e)), 127 );
     /* Update tree label */
     GtkTreeStore * store = GTK_TREE_STORE(
        gtk_tree_view_get_model(GTK_TREE_VIEW(d->tree)) );
     GtkTreeModel * model = GTK_TREE_MODEL(store);
     GtkTreeIter it;
     gboolean valid = gtk_tree_model_get_iter_first( model, &it );
     /* Walk to find the row with index == d->nSel */
     while( valid ) {
        int idx; gtk_tree_model_get( model, &it, 2, &idx, -1 );
        if( idx == d->nSel ) {
           gtk_tree_store_set( store, &it, 0, gtk_entry_get_text(GTK_ENTRY(e)), -1 );
           break;
        }
        valid = gtk_tree_model_iter_next( model, &it );
     }
  }

  static void on_mei_shortcut_changed( GtkEditable * e, gpointer data )
  {
     MEIDATA * d = (MEIDATA *)data;
     if( d->bUpdating || d->nSel<0 ) return;
     strncpy( d->nodes[d->nSel].szShortcut, gtk_entry_get_text(GTK_ENTRY(e)), 31 );
     GtkTreeStore * store = GTK_TREE_STORE(
        gtk_tree_view_get_model(GTK_TREE_VIEW(d->tree)) );
     GtkTreeModel * model = GTK_TREE_MODEL(store);
     GtkTreeIter it;
     gboolean valid = gtk_tree_model_get_iter_first( model, &it );
     while( valid ) {
        int idx; gtk_tree_model_get( model, &it, 2, &idx, -1 );
        if( idx == d->nSel ) {
           gtk_tree_store_set( store, &it, 1, gtk_entry_get_text(GTK_ENTRY(e)), -1 );
           break;
        }
        valid = gtk_tree_model_iter_next( model, &it );
     }
  }

  static void on_mei_handler_changed( GtkEditable * e, gpointer data )
  {
     MEIDATA * d = (MEIDATA *)data;
     if( d->bUpdating || d->nSel<0 ) return;
     strncpy( d->nodes[d->nSel].szHandler, gtk_entry_get_text(GTK_ENTRY(e)), 127 );
  }

  static void on_mei_enabled_toggled( GtkToggleButton * tb, gpointer data )
  {
     MEIDATA * d = (MEIDATA *)data;
     if( d->bUpdating || d->nSel<0 ) return;
     d->nodes[d->nSel].bEnabled = gtk_toggle_button_get_active(tb) ? 1 : 0;
  }
  ```

- [ ] **Step 7: Add toolbar button callbacks (+Item, +SubItem, +Sep, ↑, ↓, ✕)**

  ```c
  static void mei_add_node( MEIDATA * d, int nLevel, int bSeparator )
  {
     if( d->nCount >= MEI_MAX ) return;
     /* Insert after current selection (or at end) */
     int insAfter = d->nSel >= 0 ? d->nSel : d->nCount - 1;
     /* Find last sibling or descendant after insAfter to insert after */
     int insPos = insAfter + 1;
     /* Shift nodes up */
     for( int i = d->nCount; i > insPos; i-- )
        d->nodes[i] = d->nodes[i-1];
     /* Determine parent index */
     int nParent = -1;
     if( nLevel > 0 ) {
        for( int i = insPos - 1; i >= 0; i-- ) {
           if( d->nodes[i].nLevel == nLevel - 1 && !d->nodes[i].bSeparator ) {
              nParent = i;
              break;
           }
        }
     }
     memset( &d->nodes[insPos], 0, sizeof(MEINode) );
     strcpy( d->nodes[insPos].szCaption, bSeparator ? "" : "NewItem" );
     d->nodes[insPos].bSeparator = bSeparator;
     d->nodes[insPos].bEnabled = 1;
     d->nodes[insPos].nLevel = nLevel;
     d->nodes[insPos].nParent = nParent;
     d->nCount++;
     /* Fix parent refs for nodes shifted past insPos */
     for( int i = insPos+1; i < d->nCount; i++ )
        if( d->nodes[i].nParent >= insPos ) d->nodes[i].nParent++;
     d->nSel = insPos;
     MEI_RebuildTree( d );
  }

  static void on_mei_add_item  ( GtkButton * b, gpointer d ) { mei_add_node((MEIDATA*)d,1,0); }
  static void on_mei_add_sub   ( GtkButton * b, gpointer d ) { mei_add_node((MEIDATA*)d,2,0); }
  static void on_mei_add_popup ( GtkButton * b, gpointer d ) { mei_add_node((MEIDATA*)d,0,0); }
  static void on_mei_add_sep   ( GtkButton * b, gpointer d ) { mei_add_node((MEIDATA*)d,
     ((MEIDATA*)d)->nSel>=0 ? ((MEIDATA*)d)->nodes[((MEIDATA*)d)->nSel].nLevel : 1, 1); }

  static void on_mei_move_up( GtkButton * b, gpointer data )
  {
     MEIDATA * d = (MEIDATA *)data;
     if( d->nSel <= 0 ) return;
     int i = d->nSel;
     MEINode tmp = d->nodes[i];
     d->nodes[i] = d->nodes[i-1];
     d->nodes[i-1] = tmp;
     d->nSel = i-1;
     MEI_RebuildTree( d );
  }

  static void on_mei_move_down( GtkButton * b, gpointer data )
  {
     MEIDATA * d = (MEIDATA *)data;
     if( d->nSel < 0 || d->nSel >= d->nCount-1 ) return;
     int i = d->nSel;
     MEINode tmp = d->nodes[i];
     d->nodes[i] = d->nodes[i+1];
     d->nodes[i+1] = tmp;
     d->nSel = i+1;
     MEI_RebuildTree( d );
  }

  static void on_mei_delete( GtkButton * b, gpointer data )
  {
     MEIDATA * d = (MEIDATA *)data;
     if( d->nSel < 0 || d->nCount == 0 ) return;
     int del = d->nSel;
     for( int i = del; i < d->nCount-1; i++ )
        d->nodes[i] = d->nodes[i+1];
     d->nCount--;
     d->nSel = del < d->nCount ? del : d->nCount-1;
     MEI_RebuildTree( d );
  }
  ```

- [ ] **Step 8: Add OpenMenuEditor() — builds and runs the dialog**

  ```c
  static void OpenMenuEditor( INSDATA * ins, int nReal )
  {
     MEIDATA d;
     memset( &d, 0, sizeof(d) );
     d.nSel = -1;
     MEI_Parse( &d, ins->rows[nReal].szValue );

     GtkWidget * dialog = gtk_dialog_new_with_buttons( "Menu Items Editor",
        GTK_WINDOW(ins->window),
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        "OK", GTK_RESPONSE_OK,
        "Cancel", GTK_RESPONSE_CANCEL,
        NULL );
     gtk_window_set_default_size( GTK_WINDOW(dialog), 640, 400 );

     GtkWidget * content = gtk_dialog_get_content_area( GTK_DIALOG(dialog) );

     /* Toolbar */
     GtkWidget * toolbar = gtk_box_new( GTK_ORIENTATION_HORIZONTAL, 4 );
     gtk_box_pack_start( GTK_BOX(content), toolbar, FALSE, FALSE, 4 );

     struct { const char * label; GCallback cb; } btns[] = {
        { "+Popup",   G_CALLBACK(on_mei_add_popup) },
        { "+Item",    G_CALLBACK(on_mei_add_item)  },
        { "+SubItem", G_CALLBACK(on_mei_add_sub)   },
        { "+Sep",     G_CALLBACK(on_mei_add_sep)   },
        { "↑",        G_CALLBACK(on_mei_move_up)   },
        { "↓",        G_CALLBACK(on_mei_move_down) },
        { "✕",        G_CALLBACK(on_mei_delete)    },
     };
     for( int i = 0; i < 7; i++ ) {
        GtkWidget * btn = gtk_button_new_with_label( btns[i].label );
        g_signal_connect( btn, "clicked", btns[i].cb, &d );
        gtk_box_pack_start( GTK_BOX(toolbar), btn, FALSE, FALSE, 0 );
     }

     /* Horizontal paned: tree | properties */
     GtkWidget * paned = gtk_paned_new( GTK_ORIENTATION_HORIZONTAL );
     gtk_paned_set_position( GTK_PANED(paned), 380 );
     gtk_box_pack_start( GTK_BOX(content), paned, TRUE, TRUE, 4 );

     /* Left: tree */
     GtkWidget * sw = gtk_scrolled_window_new( NULL, NULL );
     gtk_scrolled_window_set_policy( GTK_SCROLLED_WINDOW(sw),
        GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC );
     GtkTreeStore * store = gtk_tree_store_new( 3, G_TYPE_STRING, G_TYPE_STRING, G_TYPE_INT );
     d.tree = gtk_tree_view_new_with_model( GTK_TREE_MODEL(store) );
     g_object_unref( store );
     gtk_tree_view_set_headers_visible( GTK_TREE_VIEW(d.tree), TRUE );
     GtkCellRenderer * rend = gtk_cell_renderer_text_new();
     GtkTreeViewColumn * col0 = gtk_tree_view_column_new_with_attributes(
        "Caption", rend, "text", 0, NULL );
     gtk_tree_view_column_set_min_width( col0, 200 );
     gtk_tree_view_append_column( GTK_TREE_VIEW(d.tree), col0 );
     GtkCellRenderer * rend2 = gtk_cell_renderer_text_new();
     GtkTreeViewColumn * col1 = gtk_tree_view_column_new_with_attributes(
        "Shortcut", rend2, "text", 1, NULL );
     gtk_tree_view_append_column( GTK_TREE_VIEW(d.tree), col1 );
     gtk_container_add( GTK_CONTAINER(sw), d.tree );
     gtk_widget_show( d.tree );
     gtk_paned_add1( GTK_PANED(paned), sw );

     GtkTreeSelection * sel = gtk_tree_view_get_selection( GTK_TREE_VIEW(d.tree) );
     g_signal_connect( sel, "changed", G_CALLBACK(on_mei_selection_changed), &d );

     /* Right: properties form */
     GtkWidget * grid = gtk_grid_new();
     gtk_grid_set_row_spacing( GTK_GRID(grid), 6 );
     gtk_grid_set_column_spacing( GTK_GRID(grid), 8 );
     gtk_widget_set_margin_start( grid, 8 );
     gtk_widget_set_margin_top( grid, 8 );

     auto addRow = ^( int row, const char * lbl, GtkWidget * w ) {
        GtkWidget * label = gtk_label_new( lbl );
        gtk_widget_set_halign( label, GTK_ALIGN_END );
        gtk_grid_attach( GTK_GRID(grid), label, 0, row, 1, 1 );
        gtk_grid_attach( GTK_GRID(grid), w, 1, row, 1, 1 );
        gtk_widget_set_hexpand( w, TRUE );
     };
     // Note: Clang blocks won't compile on all toolchains — use inline calls:
     d.eCaption  = gtk_entry_new();
     d.eShortcut = gtk_entry_new();
     d.eHandler  = gtk_entry_new();
     d.cbEnabled = gtk_check_button_new_with_label( "Enabled" );

     GtkWidget * lCaption  = gtk_label_new("Caption:");  gtk_widget_set_halign(lCaption,  GTK_ALIGN_END);
     GtkWidget * lShortcut = gtk_label_new("Shortcut:"); gtk_widget_set_halign(lShortcut, GTK_ALIGN_END);
     GtkWidget * lOnClick  = gtk_label_new("OnClick:");  gtk_widget_set_halign(lOnClick,  GTK_ALIGN_END);
     gtk_grid_attach( GTK_GRID(grid), lCaption,     0, 0, 1, 1 );
     gtk_grid_attach( GTK_GRID(grid), d.eCaption,   1, 0, 1, 1 );
     gtk_grid_attach( GTK_GRID(grid), lShortcut,    0, 1, 1, 1 );
     gtk_grid_attach( GTK_GRID(grid), d.eShortcut,  1, 1, 1, 1 );
     gtk_grid_attach( GTK_GRID(grid), lOnClick,     0, 2, 1, 1 );
     gtk_grid_attach( GTK_GRID(grid), d.eHandler,   1, 2, 1, 1 );
     gtk_grid_attach( GTK_GRID(grid), d.cbEnabled,  1, 3, 1, 1 );
     gtk_widget_set_hexpand( d.eCaption,  TRUE );
     gtk_widget_set_hexpand( d.eShortcut, TRUE );
     gtk_widget_set_hexpand( d.eHandler,  TRUE );

     g_signal_connect( d.eCaption,  "changed", G_CALLBACK(on_mei_caption_changed),  &d );
     g_signal_connect( d.eShortcut, "changed", G_CALLBACK(on_mei_shortcut_changed), &d );
     g_signal_connect( d.eHandler,  "changed", G_CALLBACK(on_mei_handler_changed),  &d );
     g_signal_connect( d.cbEnabled, "toggled", G_CALLBACK(on_mei_enabled_toggled),  &d );

     GtkWidget * propSw = gtk_scrolled_window_new( NULL, NULL );
     gtk_scrolled_window_set_policy( GTK_SCROLLED_WINDOW(propSw),
        GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC );
     gtk_container_add( GTK_CONTAINER(propSw), grid );
     gtk_paned_add2( GTK_PANED(paned), propSw );

     gtk_widget_show_all( content );

     /* Populate tree from current node data */
     MEI_RebuildTree( &d );

     if( gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_OK ) {
        char result[4096] = "";
        MEI_Serialize( &d, result, sizeof(result) );
        strncpy( ins->rows[nReal].szValue, result, 255 );
        InsApplyValue( ins, nReal );
        InsRebuildStore( ins );
     }
     gtk_widget_destroy( dialog );
  }
  ```

  > **Note on the lambda/block syntax:** The `^` block syntax above is Clang-specific and will NOT compile with GCC. Replace the `addRow` block with a simple inline helper that directly calls `gtk_grid_attach` — the code above already does this explicitly, so just remove the unused `addRow` variable.

- [ ] **Step 9: Hook 'M' type in on_row_activated to open the editor**

  Find in `on_row_activated` (around line 617):
  ```c
  /* Array property: open multiline editor (pipe-separated items) */
  if( d->rows[nReal].cType == 'A' )
  {
  ```
  Add immediately before it:
  ```c
  /* Menu property: open Menu Items Editor */
  if( d->rows[nReal].cType == 'M' )
  {
     OpenMenuEditor( d, nReal );
     return;
  }
  ```

- [ ] **Step 10: Build and verify dialog opens**

  ```bash
  cd /home/anto/HarbourBuilder && ./build_linux.sh && ./bin/hbbuilder_linux
  ```
  Drop TMainMenu, open inspector, double-click `aMenuItems` row → Menu Items Editor dialog opens. Add a Popup ("+Popup"), then an item ("+Item"), fill in Caption "File" and shortcut "Ctrl+F". Click OK → inspector updates to `(2 nodes) ...`.

- [ ] **Step 11: Commit**

  ```bash
  git add source/backends/gtk3/gtk3_inspector.c
  git commit -m "feat: add Menu Items Editor dialog for TMainMenu aMenuItems property"
  ```

---

## Task 7: HBMainMenu_Attach (runtime menu creation)

**Files:**
- Modify: `source/backends/gtk3/gtk3_core.c`

- [ ] **Step 1: Add the shortcut parser helper**

  Add before `HBMainMenu_Attach`:

  ```c
  /* Parse "Ctrl+N", "Alt+F4", "Shift+F5" → modifier + keyval */
  static void ParseShortcut( const char * sz, GdkModifierType * mod, guint * key )
  {
     *mod = 0; *key = 0;
     if( !sz || !sz[0] ) return;
     char buf[64]; strncpy(buf,sz,63); buf[63]=0;
     char * plus = strrchr(buf,'+');
     const char * keyPart = plus ? plus+1 : buf;
     if( plus ) *plus = 0;
     /* Modifiers */
     if( strcasestr(buf,"Ctrl")  ) *mod |= GDK_CONTROL_MASK;
     if( strcasestr(buf,"Alt")   ) *mod |= GDK_MOD1_MASK;
     if( strcasestr(buf,"Shift") ) *mod |= GDK_SHIFT_MASK;
     /* Key */
     if( strlen(keyPart)==1 )
        *key = gdk_unicode_to_keyval((guint32)keyPart[0]);
     else
        *key = gdk_keyval_from_name(keyPart);
  }
  ```

- [ ] **Step 2: Add the menu-item callback data struct and callback**

  ```c
  typedef struct {
     char szHandler[128];
  } HBMenuCBData;

  static void on_mainmenu_item_activated( GtkMenuItem * item, gpointer data )
  {
     HBMenuCBData * cbd = (HBMenuCBData *)data;
     if( !cbd || !cbd->szHandler[0] ) return;
     /* Convert to uppercase — Harbour symbol names are uppercase */
     char sym[128]; int i;
     for(i=0;cbd->szHandler[i]&&i<127;i++) sym[i]=toupper((unsigned char)cbd->szHandler[i]);
     sym[i]=0;
     PHB_DYNS pDyn = hb_dynsymFindName(sym);
     if(pDyn){ hb_vmPushDynSym(pDyn); hb_vmPushNil(); hb_vmDo(0); }
  }
  ```

- [ ] **Step 3: Add HBMainMenu_Attach()**

  ```c
  static void HBMainMenu_Attach( HBControl * p, HBForm * form )
  {
     HBMainMenu * m = (HBMainMenu *)p;
     if( m->FNodeCount == 0 ) return;

     /* Ensure menu bar exists */
     if( !form->FMenuBar )
        form->FMenuBar = gtk_menu_bar_new();

     /* Stack of open popup GtkMenuShell widgets, indexed by nLevel */
     GtkWidget * popupShells[8] = {0};
     popupShells[0] = form->FMenuBar;   /* level 0 = top bar */

     /* Ensure accel group is attached */
     if( !s_accelGroup ) {
        s_accelGroup = gtk_accel_group_new();
        if( form->FWindow )
           gtk_window_add_accel_group( GTK_WINDOW(form->FWindow), s_accelGroup );
     }

     for( int i = 0; i < m->FNodeCount; i++ )
     {
        HBMenuNode * n = &m->FNodes[i];
        int lv = n->nLevel;
        GtkWidget * parentShell = (lv > 0 && lv <= 7) ? popupShells[lv] : popupShells[0];
        if( !parentShell ) continue;

        if( n->bSeparator )
        {
           GtkWidget * sep = gtk_separator_menu_item_new();
           gtk_menu_shell_append( GTK_MENU_SHELL(parentShell), sep );
        }
        else if( lv == 0 )
        {
           /* Root popup (top-level menu) */
           GtkWidget * mi = gtk_menu_item_new_with_mnemonic( n->szCaption );
           GtkWidget * sub = gtk_menu_new();
           gtk_menu_item_set_submenu( GTK_MENU_ITEM(mi), sub );
           gtk_menu_shell_append( GTK_MENU_SHELL(form->FMenuBar), mi );
           popupShells[1] = sub;
           /* Invalidate deeper */
           for(int lv2=2;lv2<8;lv2++) popupShells[lv2]=NULL;
        }
        else
        {
           int hasChildren = ( i+1 < m->FNodeCount &&
                               m->FNodes[i+1].nLevel > lv );
           if( hasChildren )
           {
              /* Sub-popup */
              GtkWidget * mi = gtk_menu_item_new_with_mnemonic( n->szCaption );
              GtkWidget * sub = gtk_menu_new();
              gtk_menu_item_set_submenu( GTK_MENU_ITEM(mi), sub );
              gtk_menu_shell_append( GTK_MENU_SHELL(parentShell), mi );
              if( lv+1 < 8 ) popupShells[lv+1] = sub;
              for(int lv2=lv+2;lv2<8;lv2++) popupShells[lv2]=NULL;
           }
           else
           {
              /* Leaf item */
              GtkWidget * mi = gtk_menu_item_new_with_mnemonic( n->szCaption );
              if( !n->bEnabled )
                 gtk_widget_set_sensitive( mi, FALSE );

              if( n->szHandler[0] ) {
                 HBMenuCBData * cbd = (HBMenuCBData *)malloc(sizeof(HBMenuCBData));
                 strncpy( cbd->szHandler, n->szHandler, 127 );
                 g_signal_connect_data( mi, "activate",
                    G_CALLBACK(on_mainmenu_item_activated), cbd,
                    (GClosureNotify)free, 0 );
              }

              if( n->szShortcut[0] ) {
                 GdkModifierType mod; guint key;
                 ParseShortcut( n->szShortcut, &mod, &key );
                 if( key ) {
                    if(!s_accelGroup){ s_accelGroup=gtk_accel_group_new();
                       if(form->FWindow) gtk_window_add_accel_group(GTK_WINDOW(form->FWindow),s_accelGroup); }
                    gtk_widget_add_accelerator(mi,"activate",s_accelGroup,key,mod,GTK_ACCEL_VISIBLE);
                 }
              }

              gtk_menu_shell_append( GTK_MENU_SHELL(parentShell), mi );
           }
        }
     }
  }
  ```

- [ ] **Step 4: Hook CT_MAINMENU into HBForm_CreateAllChildren()**

  Find in `HBForm_CreateAllChildren()` (around line 2394):
  ```c
  if( IsNonVisualControl( child->FControlType ) && !form->FDesignMode ) continue;
  ```
  Change to:
  ```c
  if( IsNonVisualControl( child->FControlType ) && !form->FDesignMode ) {
     if( child->FControlType == CT_MAINMENU )
        HBMainMenu_Attach( child, form );
     continue;
  }
  ```

- [ ] **Step 5: Ensure FMenuBar is packed into the vbox in HBForm_Run/Show**

  Find around line 2462 in `gtk3_core.c`:
  ```c
  if( form->FMenuBar ) {
     gtk_box_pack_start( GTK_BOX(vbox), form->FMenuBar, FALSE, FALSE, 0 );
     gtk_widget_show_all( form->FMenuBar );
  }
  ```
  This code already exists. Verify it runs AFTER `HBForm_CreateAllChildren()` — if not, the FMenuBar will be NULL when it reaches this point. Check `HBForm_Run()` order:
  - `HBForm_CreateAllChildren()` must be called BEFORE the vbox packing
  - Look at line 2544: `HBForm_CreateAllChildren( form );`
  - Look at line 2462: vbox packing
  - If `HBForm_CreateAllChildren` is called first, FMenuBar will be populated before packing — verify the line numbers. If not, move `HBForm_CreateAllChildren` before the vbox packing in `HBForm_Run`.

- [ ] **Step 6: Build and test runtime**

  ```bash
  cd /home/anto/HarbourBuilder && ./build_linux.sh && ./bin/hbbuilder_linux
  ```
  1. Create a new form, drop TMainMenu onto it.
  2. Double-click aMenuItems → add popup "File" (level 0), then item "Exit" (level 1, handler "mnuExit").
  3. Click OK → save project.
  4. Press F5 (Run) → form shows a native GTK menu bar with "File" popup and "Exit" item.

- [ ] **Step 7: Commit**

  ```bash
  git add source/backends/gtk3/gtk3_core.c
  git commit -m "feat: add HBMainMenu_Attach() for runtime GTK3 menu bar creation from TMainMenu nodes"
  ```

---

## Task 8: Code generation (RegenerateFormCode)

**Files:**
- Modify: `source/hbbuilder_linux.prg`

- [ ] **Step 1: Add CT_MAINMENU special case in RegenerateFormCode()**

  Find in `RegenerateFormCode()` the `otherwise` block (around line 824):
  ```harbour
  otherwise
     if nType >= CT_TIMER  // Non-visual component
        cCreate += '   COMPONENT ::o' + cCtrlName + ' TYPE CT_' + ...
        if nType == CT_TIMER
           ...
        endif
     else
        ...
     endif
  endcase
  ```

  Add a new `case` BEFORE `otherwise`:
  ```harbour
  case nType == 132  // CT_MAINMENU
     cCreate += '   COMPONENT ::o' + cCtrlName + ' TYPE CT_MAINMENU OF Self  // TMainMenu' + e
     // Emit DEFINE MENUBAR block
     cVal := UI_GetProp( hCtrl, "aMenuItems" )
     if ValType( cVal ) == "C" .and. ! Empty( cVal )
        local aNodes, cNode, aFields, nLevel, cPrev, nLevelPrev
        local nLv, aPendingEnd
        aNodes := HB_ATokens( cVal, "|" )
        cCreate += '   DEFINE MENUBAR' + e
        aPendingEnd := {}
        nLevelPrev := -1
        for kk := 1 to Len( aNodes )
           cNode := aNodes[kk]
           aFields := HB_ATokens( cNode, Chr(1) )
           if Len( aFields ) < 6; loop; endif
           nLv := Val( aFields[5] )
           local cCaption  := aFields[1]
           local cShortcut := aFields[2]
           local cHandler  := aFields[3]
           local bEnabled  := aFields[4] != "0"
           // Close pending END POPUP for levels deeper than current
           do while Len( aPendingEnd ) > 0 .and. ;
                     ATail( aPendingEnd ) >= nLv
              cCreate += Replicate( "   ", ATail(aPendingEnd)+1) + '   END POPUP' + e
              ASize( aPendingEnd, Len(aPendingEnd)-1 )
           enddo
           local cIndent := Replicate( "   ", nLv + 1 ) + "   "
           if cCaption == "---"
              cCreate += cIndent + 'MENUSEPARATOR' + e
           else
              // Look ahead: is the NEXT node at a deeper level?
              local bIsPopup := .F.
              if kk < Len( aNodes )
                 local aNext := HB_ATokens( aNodes[kk+1], Chr(1) )
                 if Len(aNext) >= 5 .and. Val(aNext[5]) > nLv
                    bIsPopup := .T.
                 endif
              endif
              if nLv == 0 .or. bIsPopup
                 cCreate += cIndent + 'DEFINE POPUP "' + cCaption + '"' + e
                 AAdd( aPendingEnd, nLv )
              else
                 cCreate += cIndent + 'MENUITEM "' + cCaption + '"'
                 if ! Empty( cHandler )
                    cCreate += ' ACTION ' + cHandler + '()'
                 endif
                 if ! Empty( cShortcut )
                    cCreate += ' ACCEL "' + cShortcut + '"'
                 endif
                 cCreate += e
              endif
           endif
        next
        // Close remaining open popups
        do while Len( aPendingEnd ) > 0
           cCreate += Replicate( "   ", ATail(aPendingEnd)+1) + '   END POPUP' + e
           ASize( aPendingEnd, Len(aPendingEnd)-1 )
        enddo
        cCreate += '   END MENUBAR' + e
     endif
  ```

- [ ] **Step 2: Build and verify code generation**

  ```bash
  cd /home/anto/HarbourBuilder && ./build_linux.sh && ./bin/hbbuilder_linux
  ```
  1. Create a form with TMainMenu containing a "File" popup → "New" item (Ctrl+N, handler mnuNew) + separator + "Exit" (Alt+F4, handler mnuExit).
  2. Press Ctrl+S to save. Open the generated .prg file in the code editor — it should contain:
  ```harbour
  COMPONENT ::oMainMenu1 TYPE CT_MAINMENU OF Self  // TMainMenu
  DEFINE MENUBAR
     DEFINE POPUP "File"
        MENUITEM "New" ACTION mnuNew() ACCEL "Ctrl+N"
        MENUSEPARATOR
        MENUITEM "Exit" ACTION mnuExit() ACCEL "Alt+F4"
     END POPUP
  END MENUBAR
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add source/hbbuilder_linux.prg
  git commit -m "feat: emit DEFINE MENUBAR block in RegenerateFormCode() for CT_MAINMENU"
  ```

---

## Task 9: Code parsing (RestoreFormFromCode)

**Files:**
- Modify: `source/hbbuilder_linux.prg`

- [ ] **Step 1: Add DEFINE MENUBAR parser in RestoreFormFromCode()**

  Find in `RestoreFormFromCode()` the `COMPONENT` parser block (around line 1776):
  ```harbour
  // Parse non-visual components: COMPONENT ::oName TYPE nType OF Self
  if Left( Upper( cTrim ), 10 ) == "COMPONENT "
     ...
     loop
  endif
  ```

  Immediately after that `endif / loop` block, add the MENUBAR parser:
  ```harbour
  // Parse DEFINE MENUBAR block for TMainMenu
  if Upper( AllTrim( cTrim ) ) == "DEFINE MENUBAR"
     // Collect all nodes until END MENUBAR
     local cMenuSerial := "", nMenuLevel := 0, nLastParent := -1
     local aParentStack := {}, nFirstNode := .T.
     local jj := i + 1
     do while jj <= Len( aLines )
        local cML := AllTrim( aLines[jj] )
        local cMLU := Upper( cML )
        if cMLU == "END MENUBAR"
           exit
        elseif Left( cMLU, 12 ) == "DEFINE POPUP"
           // Extract caption
           local nQ1 := At( '"', cML )
           local nQ2 := nQ1 > 0 ? At( '"', SubStr( cML, nQ1+1 ) ) : 0
           local cCap := nQ1>0 .and. nQ2>0 ? SubStr( cML, nQ1+1, nQ2-1 ) : ""
           local nPar := Len( aParentStack ) > 0 ? ATail(aParentStack) : -1
           if ! nFirstNode; cMenuSerial += "|"; endif
           cMenuSerial += cCap + Chr(1) + Chr(1) + Chr(1) + "1" + Chr(1) + ;
                          LTrim(Str(nMenuLevel)) + Chr(1) + LTrim(Str(nPar))
           AAdd( aParentStack, Len( HB_ATokens(cMenuSerial,"|") ) - 1 )
           nMenuLevel++
           nFirstNode := .F.
        elseif cMLU == "END POPUP"
           nMenuLevel--
           if Len( aParentStack ) > 0
              ASize( aParentStack, Len(aParentStack)-1 )
           endif
        elseif Left( cMLU, 11 ) == "MENUSEPARAT"
           local nPar2 := Len( aParentStack ) > 0 ? ATail(aParentStack) : -1
           if ! nFirstNode; cMenuSerial += "|"; endif
           cMenuSerial += "---" + Chr(1) + Chr(1) + Chr(1) + "1" + Chr(1) + ;
                          LTrim(Str(nMenuLevel)) + Chr(1) + LTrim(Str(nPar2))
           nFirstNode := .F.
        elseif Left( cMLU, 8 ) == "MENUITEM"
           // MENUITEM "Caption" ACTION handler() ACCEL "Ctrl+X"
           local nQ3 := At( '"', cML )
           local nQ4 := nQ3>0 ? At( '"', SubStr(cML,nQ3+1) ) : 0
           local cCap2 := nQ3>0 .and. nQ4>0 ? SubStr(cML,nQ3+1,nQ4-1) : ""
           local cHndl := ""
           local cAccl := ""
           local nAct := At( "ACTION ", cMLU )
           if nAct > 0
              cHndl := SubStr( cML, nAct + 7 )
              local nSpc := At( " ", cHndl )
              if nSpc > 0; cHndl := Left(cHndl,nSpc-1); endif
              // Strip trailing ()
              if Right(cHndl,2)=="()"; cHndl := Left(cHndl,Len(cHndl)-2); endif
           endif
           local nAccl := At( 'ACCEL "', cML )
           if nAccl > 0
              cAccl := SubStr( cML, nAccl+7 )
              local nQ5 := At( '"', cAccl )
              if nQ5>0; cAccl := Left(cAccl,nQ5-1); endif
           endif
           local nPar3 := Len(aParentStack)>0 ? ATail(aParentStack) : -1
           if ! nFirstNode; cMenuSerial += "|"; endif
           cMenuSerial += cCap2 + Chr(1) + cAccl + Chr(1) + cHndl + Chr(1) + ;
                          "1" + Chr(1) + LTrim(Str(nMenuLevel)) + Chr(1) + LTrim(Str(nPar3))
           nFirstNode := .F.
        endif
        jj++
     enddo
     i := jj  // skip past END MENUBAR
     // Find the most recently created CT_MAINMENU child and set its aMenuItems
     if hCtrl != 0 .and. UI_GetType(hCtrl) == 132 .and. ! Empty(cMenuSerial)
        UI_SetProp( hCtrl, "aMenuItems", cMenuSerial )
     else
        // Find last non-visual child of type CT_MAINMENU
        local nCC := UI_GetChildCount( hForm )
        local jjC
        for jjC := nCC to 1 step -1
           local hC := UI_GetChild( hForm, jjC )
           if UI_GetType(hC) == 132
              UI_SetProp( hC, "aMenuItems", cMenuSerial )
              exit
           endif
        next
     endif
     loop
  endif
  ```

- [ ] **Step 2: Build and verify round-trip**

  ```bash
  cd /home/anto/HarbourBuilder && ./build_linux.sh && ./bin/hbbuilder_linux
  ```
  1. Create a form with TMainMenu: add File → New (Ctrl+N, mnuNew), separator, Exit (Alt+F4, mnuExit).
  2. Save, close the project, reopen it.
  3. Select TMainMenu — inspector should show `(3 nodes) ...`.
  4. Double-click `aMenuItems` — Menu Items Editor shows all three nodes with correct captions, shortcuts, and handlers.

- [ ] **Step 3: Commit**

  ```bash
  git add source/hbbuilder_linux.prg
  git commit -m "feat: parse DEFINE MENUBAR block in RestoreFormFromCode() for TMainMenu persistence"
  ```

---

## Task 10: End-to-end validation and ChangeLog

**Files:**
- Modify: `ChangeLog.txt`

- [ ] **Step 1: Validate all 7 success criteria**

  1. **Drop:** drag TMainMenu onto form → non-visual icon appears below canvas, Object Inspector shows `MainMenu1`.
  2. **Editor:** double-click icon → Menu Items Editor opens; add File popup, New item (Ctrl+N, mnuNew), separator, Exit (Alt+F4, mnuExit); OK saves, inspector updates to `(3 nodes) ...`.
  3. **Persistence:** save → reopen project → TMainMenu has all nodes intact.
  4. **Code generation:** generated .prg has correct DEFINE MENUBAR / DEFINE POPUP / MENUITEM / MENUSEPARATOR blocks.
  5. **Runtime:** press F5 → form shows native GTK3 menu bar; click File → Exit → (add test handler `function mnuExit() ; MsgBox("bye") ; return nil` in code editor to verify it fires).
  6. **Sub-menus:** add a sub-popup under a popup → ▶ arrow visible at runtime.
  7. **No regressions:** existing forms without TMainMenu still run correctly.

- [ ] **Step 2: Add ChangeLog entry**

  Add at the top of `ChangeLog.txt`:
  ```
  2026-04-24g
  - feat: TMainMenu non-visual component for Linux IDE
    - CT_MAINMENU (132) registered as non-visual component in Standard palette
    - HBMenuNode/HBMainMenu structs with flat node array (MAX_MENU_NODES=128)
    - aMenuItems property (type 'M') serialized as pipe+SOH format
    - Menu Items Editor dialog in inspector: hierarchy tree + properties pane
    - Supports popups, items, separators, sub-menus, shortcuts, OnClick handlers
    - RegenerateFormCode emits DEFINE MENUBAR/POPUP/MENUITEM/MENUSEPARATOR blocks
    - RestoreFormFromCode parses DEFINE MENUBAR block on project reload
    - HBMainMenu_Attach() creates native GTK3 menu bar at runtime (HBForm_Run)
  ```

- [ ] **Step 3: Final commit**

  ```bash
  git add ChangeLog.txt
  git commit -m "feat: complete TMainMenu component for Linux IDE (CT_MAINMENU=132)"
  ```
