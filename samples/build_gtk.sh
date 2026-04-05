#!/bin/bash
# build_gtk.sh - Build HarbourBuilder IDE for Linux using Harbour + GTK3 + Scintilla
#
# Prerequisites:
#   sudo apt install libgtk-3-dev
#   Harbour compiler installed (default: ~/harbour)
#   Scintilla/Lexilla shared libs in resources/ (see build_scintilla.sh)
#
# Usage: ./build_gtk.sh [program]
#   ./build_gtk.sh              - builds hbbuilder_linux (full IDE)
#   ./build_gtk.sh test_design_gtk  - builds test_design_gtk (simple demo)

set -e

# Harbour paths - auto-detect layout
HBDIR="${HBDIR:-$HOME/harbour}"
HBINC="$HBDIR/include"
if [ -f "$HBDIR/bin/linux/gcc/harbour" ]; then
   HBBIN="$HBDIR/bin/linux/gcc"
   HBLIB="$HBDIR/lib/linux/gcc"
elif [ -f "$HBDIR/bin/harbour" ]; then
   HBBIN="$HBDIR/bin"
   HBLIB="$HBDIR/lib"
else
   echo "ERROR: Harbour compiler not found in $HBDIR"
   echo "  Run the IDE first - it will auto-download and build Harbour."
   exit 1
fi

PROJDIR="$(cd "$(dirname "$0")/.." && pwd)"
PROG="${1:-hbbuilder_linux}"
RESDIR="$PROJDIR/resources"

cd "$(dirname "$0")"

echo "Using Harbour: $HBDIR"
echo "Building: $PROG"
echo ""

# === Step 0: Build Scintilla/Lexilla .so if not present ===
if [ ! -f "$RESDIR/libscintilla.so" ] || [ ! -f "$RESDIR/liblexilla.so" ]; then
   echo "[0/6] Building Scintilla + Lexilla shared libraries..."
   if [ -f "$PROJDIR/build_scintilla.sh" ]; then
      bash "$PROJDIR/build_scintilla.sh"
   else
      echo "WARNING: libscintilla.so / liblexilla.so not found in resources/"
      echo "  The code editor will fall back to system libraries or fail."
      echo "  Run build_scintilla.sh to build from source, or install system packages."
   fi
fi

echo "[1/6] Compiling ${PROG}.prg..."
"$HBBIN/harbour" ${PROG}.prg -n -w -q \
   -I"$HBINC" \
   -I"$PROJDIR/include" \
   -I"$PROJDIR/harbour" \
   -o${PROG}.c

echo "[2/6] Compiling ${PROG}.c..."
gcc -c -g -Wno-unused-value \
   -I"$HBINC" \
   $(pkg-config --cflags gtk+-3.0) \
   ${PROG}.c -o ${PROG}.o

echo "[3/6] Compiling GTK3 core..."
gcc -c -g \
   -I"$HBINC" \
   $(pkg-config --cflags gtk+-3.0) \
   "$PROJDIR/backends/gtk3/gtk3_core.c" -o gtk3_core.o

echo "[4/6] Compiling GTK3 inspector..."
gcc -c -g \
   -I"$HBINC" \
   $(pkg-config --cflags gtk+-3.0) \
   "$PROJDIR/backends/gtk3/gtk3_inspector.c" -o gtk3_inspector.o

echo "[5/6] Linking ${PROG}..."
gcc ${PROG}.o gtk3_core.o gtk3_inspector.o -g -o ${PROG} \
   -L"$HBLIB" \
   -Wl,--start-group \
   -lhbcommon -lhbvm -lhbrtl -lhbrdd -lhbmacro -lhblang -lhbcpage -lhbpp \
   -lhbcplr -lrddntx -lrddcdx -lrddfpt -lhbsix -lhbusrrdd -lhbct \
   -lhbsqlit3 -lsddsqlt3 -lrddsql \
   -lgttrm -lhbdebug -lhbpcre \
   $(pkg-config --libs gtk+-3.0) \
   -lm -lpthread -ldl -lrt -lsqlite3 \
   -L/usr/lib/x86_64-linux-gnu -l:libncurses.so.6 \
   -Wl,--end-group

echo "[6/6] Copying Scintilla libraries..."
if [ -f "$RESDIR/libscintilla.so" ]; then
   cp -u "$RESDIR/libscintilla.so" .
   cp -u "$RESDIR/liblexilla.so" .
   echo "  Copied libscintilla.so + liblexilla.so to build directory"
fi

echo "[7/7] Installing to bin/..."
BINDIR="$PROJDIR/bin"
mkdir -p "$BINDIR"
cp -f "${PROG}" "$BINDIR/"
if [ -f "$RESDIR/libscintilla.so" ]; then
   cp -u "$RESDIR/libscintilla.so" "$BINDIR/"
   cp -u "$RESDIR/liblexilla.so" "$BINDIR/"
fi
echo "  Installed ${PROG} + libs to bin/"

echo ""
echo "-- ${PROG} built successfully --"
echo "Run with: cd $BINDIR && LD_LIBRARY_PATH=. ./${PROG}"
