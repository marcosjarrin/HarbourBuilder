/*
 * cocoa_inspector.m - Property inspector using Cocoa NSTableView
 * Replaces the Win32 ListView-based inspector for macOS.
 *
 * Exports: INS_Create, INS_RefreshWithData, INS_BringToFront, INS_Destroy
 *          _INSGETDATA, _INSSETDATA
 */

#import <Cocoa/Cocoa.h>
#include <hbapi.h>
#include <hbapiitm.h>
#include <hbvm.h>
#include <string.h>
#include <stdio.h>

#define MAX_ROWS 64

/* ======================================================================
 * Data model
 * ====================================================================== */

typedef struct {
   char szName[32];
   char szValue[256];
   char szCategory[32];
   char cType;       /* S=string, N=number, L=logical, C=color, F=font */
   BOOL bIsCat;      /* category header */
   BOOL bCollapsed;
   BOOL bVisible;
} IROW;

typedef struct {
   NSWindow *   window;
   NSTableView * tableView;
   NSFont *     font;
   NSFont *     boldFont;
   HB_PTRUINT   hCtrl;       /* currently inspected control handle */
   IROW         rows[MAX_ROWS];
   int          nRows;
   int          map[MAX_ROWS]; /* visible row -> rows index */
   int          nVisible;
   NSScrollView * scrollView;
} INSDATA;

/* ======================================================================
 * Table view data source / delegate
 * ====================================================================== */

@interface HBInspectorDelegate : NSObject <NSTableViewDataSource, NSTableViewDelegate>
{
@public
   INSDATA * d;
}
@end

@implementation HBInspectorDelegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
   return d ? d->nVisible : 0;
}

- (id)tableView:(NSTableView *)tableView
   objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row
{
   if( !d || row < 0 || row >= d->nVisible ) return @"";
   int nReal = d->map[row];

   if( [[col identifier] isEqualToString:@"name"] )
   {
      if( d->rows[nReal].bIsCat )
         return [NSString stringWithFormat:@"%c  %s",
            d->rows[nReal].bCollapsed ? '+' : '-',
            d->rows[nReal].szName];
      else
         return [NSString stringWithFormat:@"    %s", d->rows[nReal].szName];
   }
   else
   {
      if( d->rows[nReal].bIsCat ) return @"";
      return [NSString stringWithUTF8String:d->rows[nReal].szValue];
   }
}

- (void)tableView:(NSTableView *)tableView
   setObjectValue:(id)value forTableColumn:(NSTableColumn *)col row:(NSInteger)row
{
   if( !d || row < 0 || row >= d->nVisible ) return;
   if( ![[col identifier] isEqualToString:@"value"] ) return;

   int nReal = d->map[row];
   if( d->rows[nReal].bIsCat ) return;

   const char * szVal = [value UTF8String];
   strncpy( d->rows[nReal].szValue, szVal, sizeof(d->rows[0].szValue) - 1 );

   /* Apply value via UI_SetProp */
   PHB_DYNS pDyn = hb_dynsymFindName( "UI_SETPROP" );
   if( pDyn )
   {
      hb_vmPushDynSym( pDyn ); hb_vmPushNil();
      hb_vmPushNumInt( d->hCtrl );
      hb_vmPushString( d->rows[nReal].szName, strlen(d->rows[nReal].szName) );

      if( d->rows[nReal].cType == 'S' || d->rows[nReal].cType == 'F' )
         hb_vmPushString( szVal, strlen(szVal) );
      else if( d->rows[nReal].cType == 'N' )
         hb_vmPushInteger( atoi(szVal) );
      else if( d->rows[nReal].cType == 'L' )
         hb_vmPushLogical( strcasecmp(szVal,".T.")==0 );
      else if( d->rows[nReal].cType == 'C' )
         hb_vmPushNumInt( (HB_MAXINT) strtoul(szVal, NULL, 10) );
      else
         hb_vmPushNil();

      hb_vmDo( 3 );
   }
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)col row:(NSInteger)row
{
   if( !d || row < 0 || row >= d->nVisible ) return NO;
   int nReal = d->map[row];
   if( d->rows[nReal].bIsCat ) return NO;
   if( [[col identifier] isEqualToString:@"name"] ) return NO;
   return YES;
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn *)col row:(NSInteger)row
{
   if( !d || row < 0 || row >= d->nVisible ) return;
   int nReal = d->map[row];

   if( d->rows[nReal].bIsCat )
   {
      [cell setFont:d->boldFont];
      [cell setDrawsBackground:YES];
      [cell setBackgroundColor:[NSColor colorWithCalibratedWhite:0.90 alpha:1.0]];
   }
   else
   {
      [cell setFont:d->font];
      [cell setDrawsBackground:( row % 2 == 1 )];
      if( row % 2 == 1 )
         [cell setBackgroundColor:[NSColor colorWithCalibratedWhite:0.97 alpha:1.0]];
   }
}

/* Handle click on category row to toggle collapse */
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
   if( !d || row < 0 || row >= d->nVisible ) return NO;
   int nReal = d->map[row];

   if( d->rows[nReal].bIsCat )
   {
      d->rows[nReal].bCollapsed = !d->rows[nReal].bCollapsed;
      for( int k = nReal + 1; k < d->nRows && !d->rows[k].bIsCat; k++ )
         d->rows[k].bVisible = !d->rows[nReal].bCollapsed;

      /* Rebuild visible map */
      d->nVisible = 0;
      for( int i = 0; i < d->nRows; i++ )
      {
         if( d->rows[i].bVisible || d->rows[i].bIsCat )
            d->map[d->nVisible++] = i;
      }
      [tableView reloadData];
      return NO;
   }
   return YES;
}

@end

/* Keep delegate alive */
static HBInspectorDelegate * s_delegate = nil;

/* ======================================================================
 * Build rows from Harbour property array
 * ====================================================================== */

static void InsBuildRows( INSDATA * d, PHB_ITEM pArray )
{
   HB_SIZE nLen, i;
   char szCats[16][32];
   int nCats = 0, j;
   BOOL bNew;

   d->nRows = 0;
   if( !pArray || hb_arrayLen(pArray) == 0 ) return;

   nLen = hb_arrayLen( pArray );

   /* Collect categories */
   for( i = 1; i <= nLen && nCats < 16; i++ )
   {
      PHB_ITEM pRow = hb_arrayGetItemPtr( pArray, i );
      const char * c = hb_arrayGetCPtr( pRow, 3 );
      bNew = YES;
      for( j = 0; j < nCats; j++ )
         if( strcasecmp(szCats[j], c) == 0 ) { bNew = NO; break; }
      if( bNew ) strncpy( szCats[nCats++], c, 31 );
   }

   /* Build rows grouped by category */
   for( j = 0; j < nCats && d->nRows < MAX_ROWS - 1; j++ )
   {
      /* Category header */
      strncpy( d->rows[d->nRows].szName, szCats[j], 31 );
      d->rows[d->nRows].szValue[0] = 0;
      strncpy( d->rows[d->nRows].szCategory, szCats[j], 31 );
      d->rows[d->nRows].cType = 0;
      d->rows[d->nRows].bIsCat = YES;
      d->rows[d->nRows].bCollapsed = NO;
      d->rows[d->nRows].bVisible = YES;
      d->nRows++;

      for( i = 1; i <= nLen && d->nRows < MAX_ROWS; i++ )
      {
         PHB_ITEM pRow = hb_arrayGetItemPtr( pArray, i );
         if( strcasecmp( hb_arrayGetCPtr(pRow,3), szCats[j] ) != 0 ) continue;

         strncpy( d->rows[d->nRows].szName, hb_arrayGetCPtr(pRow,1), 31 );
         strncpy( d->rows[d->nRows].szCategory, hb_arrayGetCPtr(pRow,3), 31 );
         d->rows[d->nRows].cType = hb_arrayGetCPtr(pRow,4)[0];
         d->rows[d->nRows].bIsCat = NO;
         d->rows[d->nRows].bCollapsed = NO;
         d->rows[d->nRows].bVisible = YES;

         if( d->rows[d->nRows].cType == 'S' )
            strncpy( d->rows[d->nRows].szValue, hb_arrayGetCPtr(pRow,2), 255 );
         else if( d->rows[d->nRows].cType == 'N' )
            sprintf( d->rows[d->nRows].szValue, "%d", hb_arrayGetNI(pRow,2) );
         else if( d->rows[d->nRows].cType == 'L' )
            strcpy( d->rows[d->nRows].szValue, hb_arrayGetL(pRow,2) ? ".T." : ".F." );
         else if( d->rows[d->nRows].cType == 'C' )
            sprintf( d->rows[d->nRows].szValue, "%u", (unsigned) hb_arrayGetNInt(pRow,2) );
         else if( d->rows[d->nRows].cType == 'F' )
            strncpy( d->rows[d->nRows].szValue, hb_arrayGetCPtr(pRow,2), 255 );

         d->nRows++;
      }
   }

   /* Build visible map */
   d->nVisible = 0;
   for( int k = 0; k < d->nRows; k++ )
   {
      if( d->rows[k].bVisible || d->rows[k].bIsCat )
         d->map[d->nVisible++] = k;
   }
}

/* ======================================================================
 * Global inspector data storage
 * ====================================================================== */

static HB_PTRUINT s_insData = 0;

HB_FUNC( _INSGETDATA ) { hb_retnint( s_insData ); }
HB_FUNC( _INSSETDATA ) { s_insData = (HB_PTRUINT) hb_parnint(1); }

/* ======================================================================
 * INS_Create() --> hInsData
 * ====================================================================== */

HB_FUNC( INS_CREATE )
{
   INSDATA * d = (INSDATA *) calloc( 1, sizeof(INSDATA) );

   d->font = [NSFont systemFontOfSize:12];
   d->boldFont = [NSFont boldSystemFontOfSize:12];

   /* Create window */
   NSRect frame = NSMakeRect( 100, 100, 320, 450 );
   d->window = [[NSWindow alloc] initWithContentRect:frame
      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
      backing:NSBackingStoreBuffered
      defer:NO];
   [d->window setTitle:@"Inspector"];
   [d->window setReleasedWhenClosed:NO];
   if( [NSAppearance respondsToSelector:@selector(appearanceNamed:)] )
      [d->window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];

   /* Scroll view + table view */
   NSRect contentFrame = [[d->window contentView] bounds];
   d->scrollView = [[NSScrollView alloc] initWithFrame:contentFrame];
   [d->scrollView setHasVerticalScroller:YES];
   [d->scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

   d->tableView = [[NSTableView alloc] initWithFrame:contentFrame];
   [d->tableView setRowHeight:20];

   /* Name column */
   NSTableColumn * nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
   [nameCol setWidth:140];
   [[nameCol headerCell] setStringValue:@"Property"];
   [nameCol setEditable:NO];
   [d->tableView addTableColumn:nameCol];

   /* Value column */
   NSTableColumn * valCol = [[NSTableColumn alloc] initWithIdentifier:@"value"];
   [valCol setWidth:160];
   [[valCol headerCell] setStringValue:@"Value"];
   [valCol setEditable:YES];
   [d->tableView addTableColumn:valCol];

   /* Delegate */
   s_delegate = [[HBInspectorDelegate alloc] init];
   s_delegate->d = d;
   [d->tableView setDataSource:s_delegate];
   [d->tableView setDelegate:s_delegate];

   [d->scrollView setDocumentView:d->tableView];
   [[d->window contentView] addSubview:d->scrollView];

   [d->window orderFront:nil];

   hb_retnint( (HB_PTRUINT) d );
}

/* ======================================================================
 * INS_RefreshWithData( hInsData, hCtrl, aProps )
 * ====================================================================== */

HB_FUNC( INS_REFRESHWITHDATA )
{
   INSDATA * d = (INSDATA *)(HB_PTRUINT) hb_parnint(1);
   PHB_ITEM pArray = hb_param(3, HB_IT_ARRAY);

   if( !d ) return;

   d->hCtrl = (HB_PTRUINT) hb_parnint(2);

   if( d->hCtrl == 0 || !pArray || hb_arrayLen(pArray) == 0 )
   {
      d->nRows = 0;
      d->nVisible = 0;
      [d->tableView reloadData];
      [d->window setTitle:@"Inspector"];
      return;
   }

   /* Title from first prop (ClassName) */
   {
      PHB_ITEM pRow = hb_arrayGetItemPtr( pArray, 1 );
      const char * cls = hb_arrayGetCPtr( pRow, 2 );
      [d->window setTitle:[NSString stringWithFormat:@"Inspector: %s", cls ? cls : ""]];
   }

   InsBuildRows( d, pArray );
   [d->tableView reloadData];
}

/* ======================================================================
 * INS_BringToFront( hInsData )
 * ====================================================================== */

HB_FUNC( INS_BRINGTOFRONT )
{
   INSDATA * d = (INSDATA *)(HB_PTRUINT) hb_parnint(1);
   if( d && d->window )
      [d->window orderFront:nil];
}

/* ======================================================================
 * INS_Destroy( hInsData )
 * ====================================================================== */

HB_FUNC( INS_DESTROY )
{
   INSDATA * d = (INSDATA *)(HB_PTRUINT) hb_parnint(1);
   if( !d ) return;
   if( d->window ) [d->window close];
   free( d );
}
