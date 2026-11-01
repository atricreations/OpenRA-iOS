#!/bin/sh
#
# fix-dylib-install-names.sh - Point the app executable's references to the
# bundled native dylibs at the dylibs' real location inside the bundle.
#
# The dotnet iOS SDK, when given <NativeReference Kind="Dynamic"> dylibs,
# physically places them at the app bundle root (next to the mono runtime
# dylibs) but records the executable's LC_LOAD_DYLIB references using a
# macOS-style "@executable_path/Contents/MonoBundle/<name>" path that does
# not exist on iOS. dyld then refuses to launch the app ("Library not
# loaded"). This script rewrites each reference to "@executable_path/<name>"
# (or the dylib's actual sub-path) so it resolves.
#
# It reads the current reference from `otool -L` rather than assuming the
# SDK's exact string, so it stays correct if the SDK's layout changes.
#
# Usage: fix-dylib-install-names.sh <path-to-.app>

set -eu

APP="$1"
EXE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist" 2>/dev/null || echo OpenRA.iOS)
EXE="$APP/$EXE_NAME"

for name in libSDL2.dylib libfreetype.dylib liblua51.dylib; do
    dylib=$(find "$APP" -name "$name" -print -quit)
    if [ -z "$dylib" ]; then
        echo "warn: $name not found in $APP, skipping" >&2
        continue
    fi

    # Path relative to the bundle root (where the executable lives).
    rel="${dylib#"$APP"/}"
    newref="@executable_path/$rel"

    # The reference the SDK actually recorded in the executable.
    cur=$(xcrun otool -L "$EXE" 2>/dev/null | awk -v n="$name" 'index($0, n) { print $1; exit }')
    if [ -z "$cur" ]; then
        echo "note: executable has no reference to $name (not linked); nothing to fix" >&2
        continue
    fi

    if [ "$cur" != "$newref" ]; then
        echo "fix: $name: $cur -> $newref"
        xcrun install_name_tool -change "$cur" "$newref" "$EXE"
    else
        echo "ok: $name already references $newref"
    fi
done

echo "done"
