#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

installed_app="${RECTANGLE_APP_PATH:-/Applications/Rectangle.app}"
build_dir="${RECTANGLE_BUILD_DIR:-${TMPDIR:-/tmp}/rectangle-local-build}"
requirement=$(codesign -d -r- "$installed_app" 2>&1)
requirement="${requirement##*designated => }"
if [[ "$requirement" =~ certificate\ leaf\ =\ H\"([[:xdigit:]]+)\" ]]; then
    identity="${BASH_REMATCH[1]}"
else
    printf 'The installed app must have a certificate-backed signing identity. Refusing ad-hoc signing.\n' >&2
    exit 1
fi

xcodebuild -project Rectangle.xcodeproj -scheme Rectangle -configuration Release \
    -derivedDataPath "$build_dir" CODE_SIGNING_ALLOWED=NO build
app="$build_dir/Build/Products/Release/Rectangle.app"
codesign --force --deep --sign "$identity" "$app"
codesign --verify --deep --strict -R "=$requirement" "$app"
printf '\nSigned with the installed app identity: %s\n' "$app"
