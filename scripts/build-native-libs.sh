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
# target-dir | xcode-sdk | clang --target triplet | autotools --host triplet
# (SDL2/FreeType configure scripts detect iOS from the *-apple-darwin host and
# the -isysroot in CFLAGS, so the real iOS triple goes only into CFLAGS)
TARGETS=(
    "arm64-apple-ios$IOS_MIN|iphoneos|arm64-apple-ios$IOS_MIN|arm64-apple-darwin"
    "arm64-apple-ios$IOS_MIN-simulator|iphonesimulator|arm64-apple-ios$IOS_MIN-simulator|arm64-apple-darwin"
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
    # FreeType 2.13+ publishes on GNU Savannah (SourceForge is unreliable)
    download "https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.gz" \
        "$CACHE_DIR/freetype-${FREETYPE_VERSION}.tar.gz"
    download "https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz" \
        "$CACHE_DIR/lua-${LUA_VERSION}.tar.gz"

    for name in "SDL2-${SDL2_VERSION}" "freetype-${FREETYPE_VERSION}" "lua-${LUA_VERSION}"; do
        if [ ! -d "$SRC_DIR/$name" ]; then
            tar -xzf "$CACHE_DIR/$name.tar.gz" -C "$SRC_DIR"
        fi
    done
}

# build_lib <target-dir-name> <sdk> <clang-target-triplet> <configure-host>
build_lib() {
    local out="$1" sdk="$2" triple="$3" cfg_host="$4"
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
    # SDL2's configure routes to the iOS branch only when the --host string
    # contains "-ios-" (e.g. arm64-apple-ios-simulator). Canonical device
    # triplets (arm64-apple-ios27.0) don't match that pattern, so extend the
    # case pattern in the vendored configure (idempotent sed).
    local sdl_cfg="$SRC_DIR/SDL2-${SDL2_VERSION}/configure"
    if ! grep -qF -- '*-ios-*|*-*-ios*)' "$sdl_cfg"; then
        sed -i '' 's/\*-ios-\*)/-*-ios-*|*-*-ios*)/' "$sdl_cfg"
    fi
    # The SDL_config.h.in template has no #undef placeholder for
    # SDL_VIDEO_DRIVER_UIKIT, so autoconf's AC_DEFINE for it (configure.ac iOS
    # branch) never reaches the generated SDL_config.h. Every src/video/uikit/*.m
    # is guarded by that macro and then compiles to an empty object, and SDL
    # silently falls back to the GL-less "offscreen" driver at runtime
    # ("OpenGL support is either not configured in SDL ... (offscreen)").
    # Add the placeholder so configure can fill it in (idempotent).
    local sdl_tpl="$SRC_DIR/SDL2-${SDL2_VERSION}/include/SDL_config.h.in"
    if ! grep -qF '#undef SDL_VIDEO_DRIVER_UIKIT' "$sdl_tpl"; then
        sed -i '' '/^#undef SDL_VIDEO_DRIVER_COCOA$/a\
#undef SDL_VIDEO_DRIVER_UIKIT
' "$sdl_tpl"
    fi
    # SDL 2.32's SDL_MousePostInit creates the dummy default cursor with
    # degenerate masks (0xFF, 0xFF, 0xFF, 0xFF) that map to no pixel format,
    # so SDL_CreateRGBSurface fails and every SDL_Init(VIDEO) leaves a stale
    # "Unknown pixel format" error in the SDL error state. OpenRA's
    # CanCreateGLWindow treats any non-empty SDL_GetError() after
    # SDL_CreateWindow as a failure, so all GL profiles were rejected.
    # Use proper RGBA8888 masks so the dummy cursor is created (restoring the
    # intended mouse grab/focus behavior) and no error is set (idempotent).
    local sdl_mouse="$SRC_DIR/SDL2-${SDL2_VERSION}/src/events/SDL_mouse.c"
    if ! grep -qF 'SDL_CreateRGBSurface(0, 1, 1, 32, 0xFF, 0xFF, 0xFF, 0xFF)' "$sdl_mouse"; then
        sed -i '' 's/SDL_CreateRGBSurface(0, 1, 1, 32, 0xFF, 0xFF, 0xFF, 0xFF)/SDL_CreateRGBSurface(0, 1, 1, 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000)/' "$sdl_mouse"
    fi
    # SDLEAGLContext's dealloc detaches the GL view via
    # [SDL_uikitview setSDLWindow:nil], mutating the UIKit view hierarchy.
    # Dealloc runs on whichever thread releases the last EAGL context
    # reference - for OpenRA that is the render thread inside
    # SDL_GL_DeleteContext - and iOS aborts the process on off-main-thread
    # UI changes (NSInternalInconsistencyException). Guard setSDLWindow: so
    # GL context teardown on a worker thread no longer aborts (idempotent).
    local sdl_view="$SRC_DIR/SDL2-${SDL2_VERSION}/src/video/uikit/SDL_uikitview.m"
    if ! grep -qF 'Off-main-thread UI work guard' "$sdl_view"; then
        python3 - "$sdl_view" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = '''- (void)setSDLWindow:(SDL_Window *)window
{
    SDL_WindowData *data = nil;

    if (window == sdlwindow) {
        return;
    }'''
assert s.count(anchor) == 1, "setSDLWindow: anchor not found"
guard = '''- (void)setSDLWindow:(SDL_Window *)window
{
    SDL_WindowData *data = nil;

    /* Off-main-thread UI work guard: this method also runs from
     * SDLEAGLContext's dealloc, on whichever thread releases the last EAGL
     * context reference (a render thread in SDL_GL_DeleteContext). UIKit
     * aborts on view hierarchy changes off the main thread; skip them
     * there - the owning window's main-thread teardown removes the view. */
    if (![NSThread isMainThread]) {
        return;
    }

    if (window == sdlwindow) {
        return;
    }'''
s = s.replace(anchor, guard)
open(p, 'w').write(s)
print("patched SDL_uikitview.m")
PYEOF
    fi
    # presentRenderbuffer presents the *currently-bound* renderbuffer. OpenRA
    # leaves its own FBO depth renderbuffer bound after drawing, which is not
    # tied to the CAEAGLLayer, so presentRenderbuffer failed with
    # GL_INVALID_VALUE (0x502) and the screen stayed black. Rebind the
    # drawable's renderbuffer right before presenting (idempotent).
    local sdl_glview="$SRC_DIR/SDL2-${SDL2_VERSION}/src/video/uikit/SDL_uikitopenglview.m"
    if ! grep -qF 'GL_INVALID_VALUE (0x502). Rebind the' "$sdl_glview"; then
        python3 - "$sdl_glview" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "    [context presentRenderbuffer:GL_RENDERBUFFER];"
assert s.count(anchor) == 1, "presentRenderbuffer anchor not found"
fix = """    /* presentRenderbuffer presents the currently-bound renderbuffer. Cross-
     * platform engines (OpenRA) bind their own FBO depth renderbuffers and
     * leave that bound; that renderbuffer is not tied to the CAEAGLLayer, so
     * presentRenderbuffer failed with GL_INVALID_VALUE (0x502). Rebind the
     * drawable's renderbuffer before presenting. */
    glBindRenderbuffer(GL_RENDERBUFFER, viewRenderbuffer);

    [context presentRenderbuffer:GL_RENDERBUFFER];"""
s = s.replace(anchor, fix)
open(p, 'w').write(s)
print("patched SDL_uikitopenglview.m")
PYEOF
    fi
    # Scene-attach: a UIWindow created with the frame initializer and attached
    # to a scene afterward is not composited on scene-based hosts (its
    # CAEAGLLayer drawable is never shown -> black). Find the host's active
    # window scene and create the window with initWithWindowScene: so the
    # window server displays it; prefer the foreground-active scene (correct
    # for the iPhone Duo's multiple scenes) (idempotent).
    local sdl_win="$SRC_DIR/SDL2-${SDL2_VERSION}/src/video/uikit/SDL_uikitwindow.m"
    if ! grep -qF 'Scene-attach' "$sdl_win"; then
        python3 - "$sdl_win" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
decl_anchor = "        SDL_Window *other;\n        UIWindow *uiwindow;"
assert s.count(decl_anchor) == 1, "window decl anchor not found"
s = s.replace(decl_anchor,
    "        SDL_Window *other;\n        UIWindow *uiwindow;\n        UIWindowScene *hostScene = nil;")
create_anchor = """        /* ignore the size user requested, and make a fullscreen window */
        /* !!! FIXME: can we have a smaller view? */
        uiwindow = [[SDL_uikitwindow alloc] initWithFrame:data.uiscreen.bounds];"""
assert s.count(create_anchor) == 1, "create window anchor not found"
create_fix = """        /* ignore the size user requested, and make a fullscreen window */
        /* Scene-attach: in scene-based host apps, a UIWindow created with the
         * frame initializer and attached to a scene afterward is not
         * composited by the window server (its CAEAGLLayer drawable is never
         * shown -> black screen). Find the host's active window scene FIRST
         * and create the window directly with it (initWithWindowScene:) so
         * the window server actually displays it. Fall back to the frame
         * initializer if no scene is connected yet. */
        if (@available(iOS 13.0, tvOS 13.0, *)) {
            for (UIScene *candidate in [UIApplication sharedApplication].connectedScenes) {
                if ([candidate isKindOfClass:[UIWindowScene class]]) {
                    hostScene = (UIWindowScene *)candidate;
                    if (candidate.activationState == UISceneActivationStateForegroundActive) {
                        break;
                    }
                }
            }
        }

        if (hostScene != nil) {
            uiwindow = [[SDL_uikitwindow alloc] initWithWindowScene:hostScene];
            uiwindow.frame = hostScene.coordinateSpace.bounds;
            window->x = 0;
            window->y = 0;
            window->w = (int)hostScene.coordinateSpace.bounds.size.width;
            window->h = (int)hostScene.coordinateSpace.bounds.size.height;
        } else {
            /* !!! FIXME: can we have a smaller view? */
            uiwindow = [[SDL_uikitwindow alloc] initWithFrame:data.uiscreen.bounds];
        }"""
s = s.replace(create_anchor, create_fix)
open(p, 'w').write(s)
print("patched SDL_uikitwindow.m")
PYEOF
    fi
    local sdl_build="$SRC_DIR/build-sdl2-$triple"
    rm -rf "$sdl_build"
    mkdir -p "$sdl_build"
    echo "-- SDL2 $SDL2_VERSION (host: $triple)"
    (cd "$sdl_build" && \
        CC="clang --target=$triple" \
        # -fobjc-arc: the .m sources (uikit video, coreaudio, MFI joystick)
        # require ARC; clang ignores the flag for plain C files.
        CFLAGS="$sysroot_flags -O3 -fPIC -fobjc-arc" \
        LDFLAGS="$sysroot_flags" \
        "$sdl_cfg" \
            --host="$triple" \
            --prefix=/usr/local \
            --disable-shared \
            --enable-static \
            --disable-everything \
            --enable-video \
            --enable-audio \
            --disable-hidapi \
            --disable-power \
            > configure.log 2>&1) \
        || { tail -50 "$sdl_build/configure.log"; exit 1; }
    (cd "$sdl_build" && make -j"$(sysctl -n hw.ncpu)" > build.log 2>&1) \
        || { tail -50 "$sdl_build/build.log"; exit 1; }
    local sdl_lib
    sdl_lib="$(find "$sdl_build" -name 'libSDL2.a' | head -1)"
    [ -n "$sdl_lib" ] || { echo "error: libSDL2.a not found under $sdl_build" >&2; exit 1; }
    cp "$sdl_lib" "$out/libSDL2.a"

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
            --host="$cfg_host" \
            --prefix=/usr/local \
            --disable-shared \
            --enable-static \
            --disable-docs \
            --disable-html-doc \
            --disable-man-doc \
            --disable-pdf-doc \
            --without-zlib \
            --without-bzip2 \
            --without-harfbuzz \
            > configure.log 2>&1) || { tail -50 "$ft_build/configure.log"; exit 1; }
    (cd "$ft_build" && make -j"$(sysctl -n hw.ncpu)" > build.log 2>&1) \
        || { tail -50 "$ft_build/build.log"; exit 1; }
    # FreeType may drop the lib into objs/ or src/ depending on version
    local ft_lib
    ft_lib="$(find "$ft_build" -name 'libfreetype.a' | head -1)"
    cp "$ft_lib" "$out/libfreetype.a"

    # ---------------- Lua 5.1 ----------------
    local lua_src="$SRC_DIR/lua-${LUA_VERSION}/src"
    # system() is unavailable on iOS (and not allowed by the App Store);
    # stub os.execute to fail. Idempotent patch.
    if ! grep -qF 'system() is unavailable on iOS' "$lua_src/loslib.c"; then
        sed -i '' 's|  lua_pushinteger(L, system(luaL_optstring(L, 1, NULL)));|  #if defined(TARGET_OS_IPHONE)\
    (void)L;  /* system() is unavailable on iOS */\
    lua_pushinteger(L, -1);\
  #else\
    lua_pushinteger(L, system(luaL_optstring(L, 1, NULL)));\
  #endif|' "$lua_src/loslib.c"
    fi
    echo "-- Lua $LUA_VERSION"
    (cd "$lua_src" && \
        make clean > /dev/null 2>&1 || true)
    # Lua 5.1 has no 'static' target (5.2+ only); 'all' builds liblua.a
    # plus the lua/luac test binaries. The Makefile hardcodes CC/CFLAGS,
    # so override both on the command line (same pattern as its built-in
    # 'aix' target). POSIX + dlopen: iOS has dlopen; LUA_USE_MACOSX would
    # select NSLinkModule, which is unavailable on iOS.
    (cd "$lua_src" && \
        make all \
            CC="clang --target=$triple" \
            CFLAGS="$sysroot_flags -O2 -Wall -fPIC -DLUA_USE_POSIX -DLUA_USE_DLOPEN" \
            MYLDFLAGS="$sysroot_flags" \
            > "$SRC_DIR/lua-build-$triple.log" 2>&1) \
        || { tail -50 "$SRC_DIR/lua-build-$triple.log"; exit 1; }
    cp "$lua_src/liblua.a" "$out/liblua51.a"

    echo "-- done: $out"
    ls -l "$out"
}

main() {
    echo "OpenRA iOS native library build"
    echo "Device min iOS: $IOS_MIN"
    fetch_sources
    for spec in "${TARGETS[@]}"; do
        IFS='|' read -r dirname sdk triple cfg_host <<< "$spec"
        build_lib "$OUT_ROOT/$dirname" "$sdk" "$triple" "$cfg_host"
    done
    echo ""
    echo "All native libraries built under: $OUT_ROOT"
    echo ""
    echo "Next: copy into the app project and enable the NativeReference"
    echo "entries in OpenRA.iOS/OpenRA.iOS.csproj:"
    echo "  cp -R \"$OUT_ROOT\"/* OpenRA.iOS/native/"
}

main "$@"
