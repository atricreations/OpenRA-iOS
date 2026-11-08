#!/bin/bash
# One-shot iOS DEVICE build + install + launch for OpenRA-iOS (physical DUO).
#
# Runs on the Mac. Invoke from the VM with:
#   python tmp/mac.py run OpenRA-iOS/scripts/device-deploy.sh
# (mac.py uploads this script to /tmp on the Mac and runs it; output streams back.)
#
# This is the SLOW path (device codesign + devicectl). Use it for on-device sign-off
# and for INPUT/audio verification that the simulator loop can't do (the sim can't
# reach an in-game map or toggle the hardware silent switch). For pure render checks,
# prefer scripts/sim-deploy.sh (autonomous sim loop, no device).
#
# Env overrides: DEVICE_UDID, BUNDLE.
export PATH="$HOME/.dotnet:$PATH"
export DOTNET_ROOT="$HOME/.dotnet"

REPO=/Users/anthonytricarichi/OpenRA-iOS
BUNDLE=${BUNDLE:-com.anthonytricarichipersonalteam.SignGen}
DEV=${DEVICE_UDID:-00008160-0005595C3650000A}

cd "$REPO" || { echo "CD_FAILED"; exit 1; }

echo "=== [1/4] package assets (mods/ + glsl/ -> openra-data.zip) ==="
# dotnet build does NOT rebuild the bundled engine-content archive; repack from
# the CURRENT mods/ + glsl/ so mod (yml) edits reach the device (same as sim-deploy).
bash "$REPO/scripts/package-assets.sh" || { echo "PACKAGE_ASSETS_FAILED"; exit 1; }

echo "=== [2/4] build (ios-arm64, codesign) ==="
dotnet build OpenRA.iOS/OpenRA.iOS.csproj -f net10.0-ios -c Release \
  -p:RuntimeIdentifier=ios-arm64 \
  > /tmp/devdeploy_build.log 2>&1
brc=$?
echo "BUILD_EXIT=$brc"
if [ "$brc" -ne 0 ]; then
  echo "BUILD_FAILED (see /tmp/devdeploy_build.log):"
  tail -30 /tmp/devdeploy_build.log
  exit 1
fi

# Locate the produced app bundle (the RID folder name is the source of truth).
APP=$(find bin -maxdepth 3 -name "OpenRA.iOS.app" -path "*ios-arm64*" -type d 2>/dev/null | head -1)
echo "APP=$APP"
[ -n "$APP" ] && [ -d "$APP" ] || { echo "APP_MISSING: no ios-arm64 OpenRA.iOS.app under bin/"; exit 1; }

echo "=== [3/4] install on device ==="
# Plain reinstall (no uninstall): AssetExtractor re-extracts when its fingerprint
# (app version + SHA256 of openra-data.zip) mismatches the stored stamp, so fresh
# mod/asset edits still land without wiping the data container -- and a plain
# reinstall keeps the developer profile trusted (no re-trust prompt on the device).
xcrun devicectl device install app --device "$DEV" "$APP" 2>&1 | tail -6

echo "=== [4/4] launch ==="
xcrun devicectl device process launch --device "$DEV" "$BUNDLE" 2>&1 | tail -3
echo "DEVICE_DEPLOY_DONE"
