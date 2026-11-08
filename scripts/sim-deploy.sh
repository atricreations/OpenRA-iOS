#!/bin/bash
# Autonomous iOS-simulator build/deploy/screenshot for OpenRA-iOS (NO physical device).
#
# Runs on the Mac. Invoke from the VM with either:
#   python tmp/mac.py simdeploy                 # one command: build->install->launch->shot->pull
#   python tmp/mac.py run scripts/sim-deploy.sh # (then manually pull /tmp/shot.png)
#
# WHY a standard iPhone sim and not the DUO sim:
#   The DUO simulator (a brand-new foldable) uses a SOFTWARE OpenGL renderer that
#   renders GL content BLACK (glClear only). Standard iPhone simulators use hardware
#   GL (ANGLE->Metal) and render OpenRA perfectly. So the autonomous dev loop targets
#   a standard iPhone sim; the physical DUO is reserved for foldable-specific sign-off.
#   This is a DUO-simulator toolchain gap, NOT a bug in the app and NOT a general
#   iOS-development problem. (See skills/ios-build-deploy/SKILL.md.)
#
# Env overrides: SIM_UDID, SIM_WAIT, BUNDLE, DISPLAY (multi-display sims only).
export PATH="$HOME/.dotnet:$PATH"
export DOTNET_ROOT="$HOME/.dotnet"

REPO=/Users/anthonytricarichi/OpenRA-iOS
BUNDLE=${BUNDLE:-com.anthonytricarichipersonalteam.SignGen}
SIM=${SIM_UDID:-84EF56EC-65F7-4839-9B99-AE44D7AB995D}   # iPhone 17, iOS 27.0 (standard, single display)
WAIT=${SIM_WAIT:-10}
DISPLAY_ARG=""        # for a multi-display sim, set e.g. DISPLAY_ARG="--display 3"
APP=bin/iossimulator-arm64/OpenRA.iOS.app

cd "$REPO" || { echo "CD_FAILED"; exit 1; }

echo "=== [1/5] package assets (mods/ + glsl/ -> openra-data.zip) ==="
# Regenerate the bundled engine-content archive from the CURRENT mods/ + glsl/
# so mod (yml) edits reach the app. dotnet build does NOT rebuild this zip.
bash "$REPO/scripts/package-assets.sh" || { echo "PACKAGE_ASSETS_FAILED"; exit 1; }

echo "=== [2/5] build (iossimulator-arm64, no codesign) ==="
dotnet build OpenRA.iOS/OpenRA.iOS.csproj -f net10.0-ios -c Release \
  -p:RuntimeIdentifier=iossimulator-arm64 -p:CodesignDisable=true \
  > /tmp/simdeploy_build.log 2>&1
brc=$?
echo "BUILD_EXIT=$brc"
if [ "$brc" -ne 0 ]; then
  echo "BUILD_FAILED (see /tmp/simdeploy_build.log):"
  tail -25 /tmp/simdeploy_build.log
  exit 1
fi
[ -d "$APP" ] || { echo "APP_MISSING: $APP"; exit 1; }

echo "=== [3/5] ensure simulator booted ==="
xcrun simctl bootstatus "$SIM" 2>&1 | tail -2

echo "=== [4/5] install + force re-extract + launch ==="
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null
xcrun simctl install "$SIM" "$APP" 2>&1 | tail -2
# AssetExtractor only re-extracts openra-data.zip when the bundle-version stamp
# mismatches; clear it so mod/asset edits in the freshly-installed bundle take
# effect without bumping the version.
CONTAINER=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data 2>/dev/null)
if [ -n "$CONTAINER" ]; then
  rm -f "$CONTAINER/Documents/OpenRA/Game/.extracted_version"
  echo "Cleared extract stamp under: $CONTAINER"
fi
xcrun simctl launch "$SIM" "$BUNDLE" 2>&1 | tail -1

echo "=== [5/5] wait + screenshot ==="
sleep "$WAIT"
# $DISPLAY_ARG is empty for a standard single-display sim; quote it so an empty
# var expands to nothing (not a literal empty argument).
xcrun simctl io "$SIM" screenshot /tmp/shot.png $DISPLAY_ARG 2>&1 | tail -1
ls -l /tmp/shot.png 2>&1
echo "SHOT=/tmp/shot.png"
echo "SIM_DEPLOY_DONE"
