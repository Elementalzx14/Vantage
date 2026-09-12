#!/usr/bin/env bash
set -euo pipefail
root="$PWD"
src="$root/build/ios-cores/src/fceumm"
testdir="$root/build/native-test"
mkdir -p "$testdir"
# A separate checkout prevents native test objects from contaminating the iOS build.
git clone --no-hardlinks "$src" "$testdir/fceumm"
make -C "$testdir/fceumm" -f Makefile.libretro -j4 platform=osx
python3 tool/make_test_rom.py "$testdir/input-test.nes"
clang++ -std=c++17 -O2 -Ipackages/vantage_emulator/ios/Classes \
  test/native/core_host_test.cpp -o "$testdir/core_host_test"
"$testdir/core_host_test" "$testdir/fceumm/fceumm_libretro.dylib" "$testdir/input-test.nes" "$testdir"
