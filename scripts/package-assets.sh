#!/usr/bin/env bash
#
# package-assets.sh - Build OpenRA.iOS/Content/openra-data.zip from the
# vendored engine content (glsl + mods). The iOS app extracts this zip into
# Documents/OpenRA/Game on first launch (see AssetExtractor.cs).
#
# The original Red Alert game data (ra.mix et al.) is NOT included here:
# it ships separately as ra-content.zip in Support (the engine's standard
# "content directory" flow) so it stays out of the app bundle and out of
# the codebase entirely.
#
# Usage: scripts/package-assets.sh
# Output: OpenRA.iOS/Content/openra-data.zip

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

DEST="$REPO_ROOT/OpenRA.iOS/Content/openra-data.zip"

# The engine looks for glsl/ and mods/ under its "engine directory"
# (Platform.EngineDir), which the iOS launcher points at
# Documents/OpenRA/Game. Reproduce that layout inside the zip.
mkdir -p "$STAGE/glsl" "$STAGE/mods"
cp -R "$REPO_ROOT/glsl/." "$STAGE/glsl/"
cp -R "$REPO_ROOT/mods/." "$STAGE/mods/"

echo "Packing $(du -sh "$STAGE" | cut -f1) of engine content..."
rm -f "$DEST"
if command -v ditto > /dev/null 2>&1; then
    # macOS-native; stores glsl/ and mods/ at the archive root
    (cd "$STAGE" && ditto -c -k --keepParent glsl mods "$DEST")
elif command -v zip > /dev/null 2>&1; then
    (cd "$STAGE" && zip -qry "$DEST" glsl mods)
else
    echo "error: need 'ditto' (macOS) or 'zip' to build the asset archive" >&2
    exit 1
fi

echo "Wrote $DEST ($(du -h "$DEST" | cut -f1))"
echo "First-launch extraction target: Documents/OpenRA/Game/"
