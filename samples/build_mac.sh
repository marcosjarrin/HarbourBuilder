#!/bin/bash
# build_mac.sh - Build test_design_mac for macOS using Harbour + Cocoa
#
# Usage: ./build_mac.sh

set -e

HBDIR="/Users/usuario/harbour"
HBBIN="$HBDIR/bin/darwin/clang"
HBINC="$HBDIR/include"
HBLIB="$HBDIR/lib/darwin/clang"
PROJDIR="$(cd "$(dirname "$0")/.." && pwd)"
PROG="test_design_mac"

cd "$(dirname "$0")"

echo "[1/4] Compiling ${PROG}.prg..."
"$HBBIN/harbour" ${PROG}.prg -n -w -q \
   -I"$HBINC" \
   -I"$PROJDIR/include" \
   -I"$PROJDIR/harbour" \
   -o${PROG}.c

echo "[2/4] Compiling ${PROG}.c..."
clang -c -O2 -Wno-unused-value \
   -I"$HBINC" \
   ${PROG}.c -o ${PROG}.o

echo "[3/4] Compiling Cocoa sources..."
clang -c -O2 -fobjc-arc \
   -I"$HBINC" \
   "$PROJDIR/backends/cocoa/cocoa_core.m" -o cocoa_core.o

clang -c -O2 -fobjc-arc \
   -I"$HBINC" \
   "$PROJDIR/backends/cocoa/cocoa_inspector.m" -o cocoa_inspector.o

echo "[4/4] Linking ${PROG}..."
clang++ -o ${PROG} \
   ${PROG}.o cocoa_core.o cocoa_inspector.o \
   -L"$HBLIB" \
   -lhbvm -lhbrtl -lhbcommon -lhbcpage -lhblang \
   -lhbmacro -lhbpp -lhbrdd -lhbcplr -lhbdebug \
   -lhbct -lhbextern \
   -lrddntx -lrddnsx -lrddcdx -lrddfpt \
   -lhbhsx -lhbsix -lhbusrrdd \
   -lgtcgi -lgttrm -lgtstd \
   -framework Cocoa \
   -lm -lpthread

echo ""
echo "-- ${PROG} built successfully --"
echo "Run with: ./${PROG}"
