#!/bin/bash
# Build and run save/load test battery
set -e

HBDIR="/Users/usuario/harbour"
HBBIN="$HBDIR/bin/darwin/clang"
HBINC="$HBDIR/include"
HBLIB="$HBDIR/lib/darwin/clang"
PROJDIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$(dirname "$0")"

echo "Compiling test_save_load.prg..."
"$HBBIN/harbour" test_save_load.prg -n -w -q \
   -I"$HBINC" -I"$PROJDIR/harbour" \
   -otest_save_load.c

echo "Compiling C..."
clang -c -O2 -Wno-unused-value -I"$HBINC" \
   test_save_load.c -o test_save_load.o

echo "Compiling cocoa_core.m..."
clang -c -O2 -fobjc-arc -I"$HBINC" \
   "$PROJDIR/backends/cocoa/cocoa_core.m" -o cocoa_core.o 2>/dev/null

echo "Linking..."
clang++ -o test_save_load \
   test_save_load.o cocoa_core.o \
   -L"$HBLIB" \
   -lhbvm -lhbrtl -lhbcommon -lhbcpage -lhblang \
   -lhbmacro -lhbpp -lhbrdd -lhbcplr -lhbdebug \
   -lhbct -lhbextern -lhbsqlit3 \
   -lrddntx -lrddnsx -lrddcdx -lrddfpt \
   -lhbhsx -lhbsix -lhbusrrdd \
   -lgtcgi -lgttrm -lgtstd \
   -framework Cocoa -framework UniformTypeIdentifiers \
   -lm -lpthread -lsqlite3

echo ""
echo "Running tests..."
echo ""
./test_save_load
