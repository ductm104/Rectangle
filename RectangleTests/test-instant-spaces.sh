#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/rectangle-instant-spaces.XXXXXX")
trap 'rm -f "$build_dir/tests" "$build_dir/app-switch-tests" "$build_dir/ISS.o" "$build_dir/event_serialize.o"; rmdir "$build_dir"' EXIT
xcrun clang -Wall -Wextra -Werror RectangleTests/InstantSpacesTests.c \
    Rectangle/InstantSpaces/event_serialize.c \
    -framework Cocoa -framework Carbon -o "$build_dir/tests"
"$build_dir/tests"
xcrun clang -Wall -Wextra -Werror -c Rectangle/InstantSpaces/ISS.c -o "$build_dir/ISS.o"
xcrun clang -Wall -Wextra -Werror -c Rectangle/InstantSpaces/event_serialize.c -o "$build_dir/event_serialize.o"
xcrun swiftc -import-objc-header RectangleTests/InstantSpacesTestBridge.h \
    Rectangle/InstantSpaces/InstantSpacesManager.swift RectangleTests/InstantSpacesAppSwitchTests.swift \
    "$build_dir/ISS.o" "$build_dir/event_serialize.o" \
    -framework Cocoa -framework Carbon -o "$build_dir/app-switch-tests"
"$build_dir/app-switch-tests"
