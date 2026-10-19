#!/bin/sh
# Unit tests: Swift Testing through `swift test`, from the Command Line Tools. Without Xcode the
# Testing module is found only through the Command Line Tools' own framework paths.
set -eu
cd "$(dirname "$0")/.."
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
exec swift test \
  -Xswiftc -F -Xswiftc "$F" \
  -Xlinker -F -Xlinker "$F" \
  -Xlinker -rpath -Xlinker "$F" \
  -Xlinker -rpath -Xlinker "$L" "$@"
