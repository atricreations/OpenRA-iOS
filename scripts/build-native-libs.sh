#!/usr/bin/env bash
#
# build-native-libs.sh - Build the iOS native dependencies as static libraries.
#
# Builds:
#   SDL2     2.32.10  (matches OpenRA-SDL2-CS 1.0.44)
#   FreeType 2.14.1   (matches OpenRA-Freetype6 1.0.12)
#   Lua      5.1.5    (matches OpenRA-Eluant 1.0.23)
#
# for each of the targets:
#   arm64-apple-ios27.0              (device, iPhone Duo)
#   arm64-apple-ios27.0-simulator    (Apple silicon simulator)
#
# Output: native/libs/<target>/libSDL2.a, libfreetype.a, liblua51.a
#
# Requirements: macOS with Xcode command line tools (xcrun, clang).
# Run from the repository root or anywhere; paths are resolved relative to
# this script.
#
# Notes:
#   * Static libraries are linked into the app executable (see
#     OpenRA.iOS/OpenRA.iOS.csproj NativeReference entries), so nothing
#     native is shipped inside the .ipa bundle and no dyld loading happens
#     at runtime. OpenRA.iOS's NativeLibraryResolver falls back to the main
#     executable image for symbol resolution.
#   * SDL2 is built with Cocoa video + CoreAudio only. Joystick/hidapi is
#     disabled for now; re-enable if gamepad support is wanted.
#   * Expect to iterate on this script once it runs on a real Mac (SDK
#     quirks, exact configure flags). It is written to fail loudly and
#     print the failing command.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$REPO_ROOT/native/src"
OUT_ROOT="$REPO_ROOT/native/libs"
CACHE_DIR="${NATIVE_SRC_CACHE:-$HOME/.cache/openra-ios-native-src}"

IOS_MIN="27.0"
TARGETS=(
    "arm64-apple-ios$IOS_MIN|iphoneos|arm64-apple-ios$IOS_MIN"
    "arm64-apple-ios$IOS_MIN-simulator|iphonesimulator|arm64-apple-ios$IOS_MIN-simulator"
)

SDL2_VERSION="2.32.10"
FREETYPE_VERSION="2.14.1"
LUA_VERSION="5.1.5"

mkdir -p "$SRC_DIR" "$OUT_ROOT" "$CACHE_DIR"

download() {
    local url="$1" dest="$2"
    if [ ! -f "$dest" ]; then
        echo "Downloading $url"
        curl -fSL --retry 3 -o "$dest.part" "$url"
        mv "$dest.part" "$dest"
    fi
}

fetch_sources() {
    download "https://github.com/libsdl-org/SDL/releases/download/release-${SDL2_VERSION}/SDL2-${SDL2_VERSION}.tar.gz" \
        "$CACHE_DIR/SDL2-${SDL2_VERSION}.tar.gz"
    download "https://sourceforge.net/projects/freetype/files/freetype2/${FREETYPE_VERSION}/freetype-${FREETYPE_VERSION}.tar.gz/download" \
        "$CACHE_DIR/freetype-${FREETYPE_VERSION}.tar.gz"
    download "https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz" \
        "$CACHE_DIR/lua-${LUA_VERSION}.tar.gz"

    for name in "SDL2-${SDL2_VERSION}" "freetype-${FREETYPE_VERSION}" "lua-${LUA_VERSION}"; do
        if [ ! -d "$SRC_DIR/$name" ]; then
            tar -xzf "$CACHE_DIR/$name.tar.gz" -C "$SRC_DIR"
        fi
    done
}

# build_lib <target-dir-name> <sdk> <clang-target-triplet>
build_lib() {
    local out="$1" sdk="$2" triple="$3"
    local sdkpath sysroot_flags

    sdkpath="$(xcrun --sdk "$sdk" --show-sdk-path)"
    if [ -z "$sdkpath" ]; then
        echo "error: SDK '$sdk' not found (is Xcode installed?)" >&2
        exit 1
    fi
    sysroot_flags="-isysroot $sdkpath"
    mkdir -p "$out"
    echo ""
    echo "=============================================================="
    echo "Building for $triple (sdk: $sdk)"
    echo "=============================================================="

    # ---------------- SDL2 ----------------
    local sdl_build="$SRC_DIR/build-sdl2-$triple"
    rm -rf "$sdl_build"
    mkdir -p "$sdl_build"
    echo "-- SDL2 $SDL2_VERSION"
    (cd "$sdl_build" && \
        CC="clang --target=$triple" \
        CFLAGS="$sysroot_flags -O3 -fPIC" \
        LDFLAGS="$sysroot_flags" \
        "$SRC_DIR/SDL2-${SDL2_VERSION}/configure" \
            --host="$triple" \
            --prefix=/usr/local \
            --disable-shared \
            --enable-static \
            --disable-everything \
            --enable-video=cocoa \
            --enable-audio=coreaudio \
            --enable-hints=video,joystick \
            --disable-x11 \
            --disable-x11-shared \
            --disable-wayland \
            --disable-alsa \
            --disable-pulse \
            --disable-jack \
            --disable-esd \
            --disable-oss \
            --disable-diskaudio \
            --disable-hidapi \
            --disable-iconv \
            --disable-iconv-text \
            --disable-power \
            --disable-sysvideo \
            --disable-video-offscreen \
            > configure.log 2>&1)
    (cd "$sdl_build" && make -j"$(sysctl -n hw.ncpu)" > build.log 2>&1) \
        || { tail -50 "$sdl_build/build.log"; exit 1; }
    cp "$sdl_build/lib/.libs/libSDL2.a" "$out/libSDL2.a"

    # ---------------- FreeType ----------------
    local ft_build="$SRC_DIR/build-freetype-$triple"
    rm -rf "$ft_build"
    mkdir -p "$ft_build"
    echo "-- FreeType $FREETYPE_VERSION"
    (cd "$ft_build" && \
        CC="clang --target=$triple" \
        CFLAGS="$sysroot_flags -O3 -fPIC" \
        LDFLAGS="$sysroot_flags" \
        "$SRC_DIR/freetype-${FREETYPE_VERSION}/configure" \
            --host="$triple" \
            --prefix=/usr/local \
            --disable-shared \
            --enable-static \
            --disable-docs \
            --disable-html-doc \
            --disable-man-doc \
            --disable-pdf-doc \
            --without-zlib \
            --without-bzip2 \
            --without-png \
            --without-harfbuzz \
            --without-freetype-module \
            > configure.log 2>&1) || { tail -50 "$ft_build/configure.log"; exit 1; }
    (cd "$ft_build" && make -j"$(sysctl -n hw.ncpu)" > build.log 2>&1) \
        || { tail -50 "$ft_build/build.log"; exit 1; }
    # FreeType may drop the lib into objs/ or src/ depending on version
    local ft_lib
    ft_lib="$(find "$ft_build" -name 'libfreetype.a' | head -1)"
    cp "$ft_lib" "$out/libfreetype.a"

    # ---------------- Lua 5.1 ----------------
    echo "-- Lua $LUA_VERSION"
    (cd "$SRC_DIR/lua-${LUA_VERSION}/src" && \
        make clean > /dev/null 2>&1 || true)
    (cd "$SRC_DIR/lua-${LUA_VERSION}/src" && \
        make "static" \
            MYCC="clang --target=$triple" \
            MYCFLAGS="$sysroot_flags -O3 -fPIC -DLUA_USE_MACOSX" \
            MYLDFLAGS="$sysroot_flags" \
            > "$SRC_DIR/lua-build-$triple.log" 2>&1) \
        || { tail -50 "$SRC_DIR/lua-build-$triple.log"; exit 1; }
    cp "$SRC_DIR/lua-${LUA_VERSION}/src/liblua5.1.a" "$out/liblua51.a"

    echo "-- done: $out"
    ls -l "$out"
}

main() {
    echo "OpenRA iOS native library build"
    echo "Device min iOS: $IOS_MIN"
    fetch_sources
    for spec in "${TARGETS[@]}"; do
        IFS='|' read -r dirname sdk triple <<< "$spec"
        build_lib "$OUT_ROOT/$dirname" "$sdk" "$triple"
    done
    echo ""
    echo "All native libraries built under: $OUT_ROOT"
    echo ""
    echo "Next: copy into the app project and enable the NativeReference"
    echo "entries in OpenRA.iOS/OpenRA.iOS.csproj:"
    echo "  cp -R \"$OUT_ROOT\"/* OpenRA.iOS/native/"
}

main "$@"
