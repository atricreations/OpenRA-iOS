#!/usr/bin/env bash
#
# build-dylibs.sh - Build the runtime dylibs for the interpreter-mode app host.
#
# Why dylibs: the app host runs managed code in the interpreter
# (UseInterpreter=true, LinkMode=None). In that mode the SDK never links
# static NativeReferences into the main executable - the host stays a small
# interpreter stub with zero SDL/FreeType/Lua symbols (verified with nm),
# so DllImport("SDL2") dies with EntryPointNotFoundException. NUKEHOUR avoids
# the problem by running full AOT; until our Phase 8 AOT switch we ship
# dylibs in the app bundle's Frameworks/ folder and dlopen them at runtime
# (see NativeLibraryResolver.cs).
#
# SDL2: we force-load ALL objects of the static archive
#   (native/<target>/libSDL2.a) into the dylib. Historically the Phase 2
#   archive's SDL_uikitvideo.o was missing (SDL.c's SDL_IsTablet references
#   SDL_IsIPad, which only that object emits), so the stub below supplies it.
#   The stub is linked conditionally: archives rebuilt after the
#   SDL_config.h.in UIKIT-placeholder fix in build-native-libs.sh already
#   define SDL_IsIPad, and linking the stub alongside would duplicate it.
# FreeType / Lua: their Phase 2 archives are complete; wrap them one-shot.
#
# Output: OpenRA.iOS/native/<target>/{libSDL2,libfreetype,liblua51}.dylib
#
# Run on macOS with the Xcode command line tools. Requires the Phase 2
# archives from build-native-libs.sh to already be in place.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_DIR="$REPO_ROOT/OpenRA.iOS/native"
STUB_SRC="$REPO_ROOT/native/sdl_isipad_stub.m"
IOS_MIN="27.0"

# target-dir | xcode-sdk | clang --target triplet
TARGETS=(
    "iossimulator-arm64|iphonesimulator|arm64-apple-ios$IOS_MIN-simulator"
    "ios-arm64|iphoneos|arm64-apple-ios$IOS_MIN"
)

# Frameworks referenced by the force-loaded SDL2 objects (mirrors the
# <Frameworks> metadata of the static NativeReference in the csproj).
SDL2_FRAMEWORKS=( -framework AVFoundation -framework AudioToolbox -framework CoreAudio
                  -framework CoreBluetooth -framework CoreGraphics -framework CoreHaptics
                  -framework CoreMotion -framework Foundation -framework GameController
                  -framework Metal -framework OpenGLES -framework QuartzCore -framework UIKit )

build_dylibs() {
    local dir="$1" sdk="$2" triple="$3"
    local out sdkpath
    out="$NATIVE_DIR/$dir"
    mkdir -p "$out"

    local a
    for a in libSDL2.a libfreetype.a liblua51.a; do
        [ -f "$out/$a" ] || { echo "error: $out/$a missing; run build-native-libs.sh first" >&2; exit 1; }
    done

    sdkpath="$(xcrun --sdk "$sdk" --show-sdk-path)"
    [ -n "$sdkpath" ] || { echo "error: SDK '$sdk' not found (is Xcode installed?)" >&2; exit 1; }

    echo ""
    echo "=============================================================="
    echo "== $triple (sdk: $sdk) =="
    echo "=============================================================="

    # Compile the SDL_IsIPad shim only when the archive lacks the symbol
    # (no grep -q: its early exit would SIGPIPE nm under set -o pipefail).
    local stub_obj=""
    local stub_args=()
    if ! nm "$out/libSDL2.a" 2>/dev/null | grep "T _SDL_IsIPad" > /dev/null; then
        [ -f "$STUB_SRC" ] || { echo "error: stub $STUB_SRC missing" >&2; exit 1; }
        stub_obj="$(mktemp)"
        echo "-- archive lacks SDL_IsIPad; compiling stub"
        clang --target="$triple" -isysroot "$sdkpath" -fobjc-arc \
            -c "$STUB_SRC" -o "$stub_obj"
        stub_args=("$stub_obj")
    else
        echo "-- archive defines SDL_IsIPad; skipping stub"
    fi

    echo "-- libSDL2.dylib"
    clang -dynamiclib -o "$out/libSDL2.dylib" \
        -Wl,-force_load,"$out/libSDL2.a" \
        ${stub_args[@]+"${stub_args[@]}"} \
        -install_name "@rpath/libSDL2.dylib" \
        -isysroot "$sdkpath" -target "$triple" "${SDL2_FRAMEWORKS[@]}"

    echo "-- libfreetype.dylib"
    clang -dynamiclib -o "$out/libfreetype.dylib" \
        -Wl,-force_load,"$out/libfreetype.a" \
        -install_name "@rpath/libfreetype.dylib" \
        -isysroot "$sdkpath" -target "$triple"

    echo "-- liblua51.dylib"
    clang -dynamiclib -o "$out/liblua51.dylib" \
        -Wl,-force_load,"$out/liblua51.a" \
        -install_name "@rpath/liblua51.dylib" \
        -isysroot "$sdkpath" -target "$triple"

    rm -f "$stub_obj"

    # Export guards. No grep -q: its early exit SIGPIPEs nm, which
    # set -o pipefail would report as a pipeline failure.
    echo "-- exports"
    if ! nm -gU "$out/libSDL2.dylib" | grep " _SDL_Init$" > /dev/null; then
        echo "error: SDL_Init not exported by libSDL2.dylib" >&2; exit 1
    fi
    # SDL_IsIPad is internal to SDL (absent from SDL.h): clang emits it as a
    # private-external symbol, so it never reaches the dylib export table.
    # Nothing dlsym()s it from managed code - the public API that wraps it,
    # SDL_IsTablet, is what must be exported.
    if ! nm -gU "$out/libSDL2.dylib" | grep " _SDL_IsTablet$" > /dev/null; then
        echo "error: SDL_IsTablet not exported by libSDL2.dylib" >&2; exit 1
    fi
    if ! nm "$out/libSDL2.dylib" | grep "_SDL_IsIPad" > /dev/null; then
        echo "error: SDL_IsIPad missing from libSDL2.dylib entirely" >&2; exit 1
    fi
    if ! nm -gU "$out/libfreetype.dylib" | grep " _FT_Init_FreeType$" > /dev/null; then
        echo "error: FT_Init_FreeType not exported" >&2; exit 1
    fi
    # Sentinels are the entry points Eluant actually dlopens (lua_newstate,
    # luaL_openlibs); lua_open does not exist in Lua 5.1.
    if ! nm -gU "$out/liblua51.dylib" | grep " _lua_newstate$" > /dev/null; then
        echo "error: lua_newstate not exported by liblua51.dylib" >&2; exit 1
    fi
    if ! nm -gU "$out/liblua51.dylib" | grep " _luaL_openlibs$" > /dev/null; then
        echo "error: luaL_openlibs not exported by liblua51.dylib" >&2; exit 1
    fi
    ls -l "$out"/*.dylib
}

main() {
    echo "OpenRA iOS native dylib build"
    for spec in "${TARGETS[@]}"; do
        IFS='|' read -r dirname sdk triple <<< "$spec"
        build_dylibs "$dirname" "$sdk" "$triple"
    done
    echo ""
    echo "All dylibs built under: $NATIVE_DIR"
}

main "$@"
