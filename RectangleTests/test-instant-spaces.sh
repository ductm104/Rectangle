#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/rectangle-instant-spaces.XXXXXX")
trap 'rm -f "$build_dir/tests"; rmdir "$build_dir"' EXIT
xcrun clang -Wall -Wextra -Werror RectangleTests/InstantSpacesTests.c \
    Rectangle/InstantSpaces/event_serialize.c \
    -framework Cocoa -framework Carbon -o "$build_dir/tests"
"$build_dir/tests"
