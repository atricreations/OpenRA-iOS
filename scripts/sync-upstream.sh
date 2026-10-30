#!/usr/bin/env bash
#
# sync-upstream.sh - Re-vendor the OpenRA engine source from the read-only
# upstream clone into this repository, preserving local modifications.
#
# Usage:
#   scripts/sync-upstream.sh [path-to-upstream-clone]
#
# Defaults to ../OpenRA (the local read-only clone). The upstream clone must
# be checked out at the commit recorded in UPSTREAM_COMMIT (or use
# scripts/pin-upstream.sh to update it).
#
# Local modifications (the port's engine patches) are preserved: before the
# sync, the engine directories are backed up to a temp dir, and after the
# re-vendor, the files listed in LOCAL_ENGINE_CHANGES are restored. Run
# `scripts/record-local-changes.sh` after making engine edits to refresh that
# list (it diffs against the upstream clone).
#
# This is a deliberately dumb, auditable script: it copies, it never deletes
# the upstream clone, and it prints exactly what it did.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="${1:-$(cd "$REPO_ROOT/.." && pwd)/OpenRA}"

if [ ! -d "$UPSTREAM/.git" ]; then
    echo "error: $UPSTREAM is not a git checkout of OpenRA" >&2
    exit 1
fi

UPSTREAM_COMMIT="$(git -C "$UPSTREAM" rev-parse HEAD)"
UPSTREAM_SHORT="$(git -C "$UPSTREAM" rev-parse --short HEAD)"
echo "Syncing engine from $UPSTREAM @ $UPSTREAM_COMMIT"

# Engine source directories to vendor (everything except .git, bin, obj)
ENGINE_DIRS=(
    OpenRA.Game
    OpenRA.Mods.Common
    OpenRA.Mods.Cnc
    OpenRA.Mods.D2k
    OpenRA.Platforms.Default
    OpenRA.Launcher
    OpenRA.WindowsLauncher
)

# Root-level engine files to vendor
ENGINE_FILES=(Directory.Build.props glsl mods)

# Engine files this project has modified locally. These are restored after
# the copy so the port's patches survive the sync.
LOCAL_ENGINE_CHANGES=(
    OpenRA.Game/Game.cs
    OpenRA.Game/Platform.cs
    OpenRA.Game/ObjectCreator.cs
    OpenRA.Game/Graphics/PlatformInterfaces.cs
    OpenRA.Game/Sound/HapticFeedback.cs
    OpenRA.Game/Sound/PcmAudioMixer.cs
    OpenRA.Game/OpenRA.Game.csproj
    OpenRA.Platforms.Default/DefaultPlatform.cs
)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Backing up locally modified engine files..."
mkdir -p "$WORK/backup"
for f in "${LOCAL_ENGINE_CHANGES[@]}"; do
    if [ -f "$REPO_ROOT/$f" ]; then
        mkdir -p "$WORK/backup/$(dirname "$f")"
        cp "$REPO_ROOT/$f" "$WORK/backup/$f"
    fi
done

echo "Copying engine directories..."
for d in "${ENGINE_DIRS[@]}"; do
    rm -rf "$REPO_ROOT/$d"
    mkdir -p "$REPO_ROOT/$d"
    (cd "$UPSTREAM/$d" && tar cf - --exclude='./bin' --exclude='./obj' .) | (cd "$REPO_ROOT/$d" && tar xf -)
done

echo "Copying engine root files..."
rm -rf "$REPO_ROOT/glsl"
(cd "$UPSTREAM" && tar cf - glsl) | (cd "$REPO_ROOT" && tar xf -)
for f in "${ENGINE_FILES[@]}"; do
    [ "$f" = "glsl" ] && continue
    cp -f "$UPSTREAM/$f" "$REPO_ROOT/$f"
done

echo "Restoring local engine modifications..."
for f in "${LOCAL_ENGINE_CHANGES[@]}"; do
    if [ -f "$WORK/backup/$f" ]; then
        mkdir -p "$REPO_ROOT/$(dirname "$f")"
        cp "$WORK/backup/$f" "$REPO_ROOT/$f"
    fi
done

echo ""
echo "Done. Record the new upstream commit:"
echo "  git -C \"$REPO_ROOT\" commit -am \"engine: sync upstream $UPSTREAM_SHORT\""
echo "Verify the restored patches are intact:"
echo "  git -C \"$REPO_ROOT\" diff --stat"
