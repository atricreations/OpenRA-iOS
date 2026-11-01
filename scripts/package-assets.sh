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
mkdir -p "$(dirname "$DEST")"

# The engine looks for glsl/ and mods/ under its "engine directory"
# (Platform.EngineDir), which the iOS launcher points at
# Documents/OpenRA/Game. Reproduce that layout inside the zip.
mkdir -p "$STAGE/glsl" "$STAGE/mods"
cp -R "$REPO_ROOT/glsl/." "$STAGE/glsl/"
cp -R "$REPO_ROOT/mods/." "$STAGE/mods/"

# "global mix database.dat" maps the classic/CRC hashes inside .mix archives
# to member filenames. The engine's MixLoader loads it via
# context.TryOpen("global mix database.dat"), which searches the mounted
# ^EngineDir package. Without it, mix members (temperat.pal, mouse.shp, ...)
# have no resolvable name and load as "File not found". It lives at the engine
# root upstream, so stage it at the zip root (=> engine dir root on extract).
cp "$REPO_ROOT/global mix database.dat" "$STAGE/"

echo "Packing $(du -sh "$STAGE" | cut -f1) of engine content..."
rm -f "$DEST"
if command -v zip > /dev/null 2>&1; then
    (cd "$STAGE" && zip -qry "$DEST" glsl mods "global mix database.dat")
elif command -v bsdtar > /dev/null 2>&1; then
    # macOS ships bsdtar; -a picks the zip format from the .zip extension.
    # (ditto cannot archive multiple sources in one call.)
    (cd "$STAGE" && bsdtar -a -c -f "$DEST" glsl mods "global mix database.dat")
else
    echo "error: need 'zip' or 'bsdtar' to build the asset archive" >&2
    exit 1
fi

echo "Wrote $DEST ($(du -h "$DEST" | cut -f1))"
echo "First-launch extraction target: Documents/OpenRA/Game/"
