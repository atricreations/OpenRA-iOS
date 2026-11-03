> **This project is vibed — support the original creators.**
>
> This is a community port of [OpenRA](https://github.com/OpenRA/OpenRA) (C&C: Red Alert 1)
> to iOS. OpenRA is open source (GPLv3); the original Red Alert 1 is by Westwood/EA.
> Please support the original creators and the OpenRA team.

# OpenRA for iOS

A port of [OpenRA](https://github.com/OpenRA/OpenRA) (C&C: Red Alert 1, mod `ra`) to
**iOS**, targeting the **iPhone Duo** (iOS 27+, A20 Pro, foldable). Landscape-only and
touch-friendly, with haptics. The engine already ships full OpenGL ES 3.0 support
(`Graphics.GLProfile=Embedded`), so the rendering path is nearly a no-op — the real port
work is platform plumbing (SDL2/FreeType/Lua native libs), an iOS `IPlatform`, touch
input, and AOT-compliant assembly loading.

## Useful findings — porting SDL + OpenGL ES games to iOS

Hard-won, non-obvious issues from getting a real SDL2 / OpenGL ES game to render and
respond to touch on iOS (especially the iPhone Duo foldable). Hopefully these save you
the same hours.

### 1. The iPhone Duo *simulator* renders OpenGL black — use a standard iPhone sim
The DUO simulator (a brand-new foldable device type) uses a **software (CPU) OpenGL
renderer**: it runs `glClear` (a solid color shows) but drops all textured/shaded content,
giving a black screen with **no GL error**. The *same binary* renders perfectly on a
standard iPhone simulator (hardware GL via ANGLE→Metal) and on the physical device
(hardware Metal GL).
**Takeaway:** run your GL dev loop on a **standard iPhone simulator**, not the DUO sim.
This is a DUO-simulator toolchain gap, not a bug in your app.

### 2. Black screen with a valid GL context = a 0×0 default-framebuffer viewport
On iOS GL-on-Metal the presentable drawable is **FBO 1** (not FBO 0), and the
**default-framebuffer viewport can be 0×0**. A final screen-buffer→window blit that is a
*geometry draw* gets clipped to nothing (black), even though `glClear` (which ignores the
viewport) still reaches the screen — which is why a solid-color test can pass while the
game is black.
**Fix:** force `glViewport(0, 0, surfaceWidth, surfaceHeight)` every frame.

### 3. `GL_INVALID_VALUE` (0x502) on `presentRenderbuffer:`
`presentRenderbuffer:` presents the **currently-bound** renderbuffer. Game engines usually
leave their own FBO / depth renderbuffer bound, which isn't tied to the `CAEAGLLayer` →
0x502 every frame.
**Fix:** rebind the drawable's `viewRenderbuffer` immediately before
`[context presentRenderbuffer:]`.

### 4. Multi-scene foldable: attach the window to a real `UIWindowScene`
The DUO has multiple `UIWindowScene`s. A window created during
`application(_:didFinishLaunchingWithOptions:)` (frame init) owns **no scene**, so the
window server composites nothing → black.
**Fix:** create the SDL/UIKit window with the standard `initWithWindowScene:` against the
host's **foreground-active** scene.

### 5. Touch→mouse: don't double-scale on HiDPI
Enable `SDL_HINT_TOUCH_MOUSE_EVENTS=1` so SDL synthesizes mouse events from touches. On
iOS, SDL already delivers those in **point** space (the same space the UI uses), *not*
backing-pixel space. If you then scale by `1/EffectiveWindowScale` (÷3 on a 3× device),
every tap lands N× too close to the origin and misses all widgets.
**Fix:** pass iOS mouse positions through unscaled.

### 6. You can't screenshot GL content on the physical device
`xcrun devicectl … capture screenshot` returns **false-black** images for GL content on the
device. Ground truth is the app's own framebuffer capture (render the back buffer to PNG)
or a person looking at the screen. On the **simulator**, `xcrun simctl io <udid>
screenshot` **is** reliable.

### 7. The DUO has two displays
The physical DUO exposes two displays: a primary LCD (1398×2034, usually the off/cover
panel when unfolded) and the large unfolded panel (2007×2853). A naive capture grabs the
primary (off) panel and looks black — target the active/unfolded display.

### 8. Audio is unavailable on the simulator
`AudioQueueStart` fails on the simulator (error −66681). Detect it and continue without
audio rather than crashing.

### 9. Toolchain notes
- **.NET 10 iOS** builds required **Xcode 27.1** (the .NET 10 iOS pack did not support
  27.2 at the time).
- Native **SDL2 + FreeType + Lua 5.1** were built as static `.a` archives and bundled as
  `dlopen`-ed `.dylib`s (interpreter mode) rather than linked in.

## Layout

| Path | What |
|---|---|
| `OpenRA.Game/`, `OpenRA.Mods.*/`, `OpenRA.Platforms.Default/`, `OpenRA.Launcher/`, `glsl/`, `mods/` | Vendored upstream engine (pinned commit), with small local modifications for iOS |
| `OpenRA.Platforms.iOS/` | iOS `IPlatform` (SDL2 window, SDL2-mixed sound engine, UIKit haptics, FreeType font); compiles the Default platform sources minus `DefaultPlatform.cs`/`OpenAlSoundEngine.cs` and publishes as `OpenRA.Platforms.Default.dll` |
| `OpenRA.iOS/` | The app: UIKit bootstrap, native library resolution, asset extraction, launch args |
| `OpenRA.iOS/native/<rid>/` | Bundled `*.dylib` (SDL2/FreeType/Lua) per runtime identifier; `dlopen`-ed at runtime |
| `scripts/` | `sync-upstream.sh` (re-vendor engine), `build-native-libs.sh` (Mac: SDL2/FreeType/Lua static libs), `build-dylibs.sh` (+ `fix-dylib-install-names.sh`), `package-assets.sh` (engine content zip), `sim-deploy.sh` (autonomous sim build/deploy/screenshot) |

## Local engine modifications (the "port patch set")

Applied to the vendored `OpenRA.Game` / `OpenRA.Platforms.Default`:

- `Game.PlatformFactoryOverride` — inject `IosPlatform` without dynamic platform-assembly
  loading (AOT-friendly; desktop path unchanged).
- `ObjectCreator.LoaderFactoryOverride` + `LoadAssembly` iOS branch — mod format loaders
  are registered explicitly; bundled assemblies resolve from the app image instead of
  being loaded from disk.
- `PlatformType.iOS` + `Platform.OverrideHostPlatform` — correct platform detection under
  the iOS hosting environment.
- `IHapticEngine` / `IPlatform.CreateHaptics` / `Game.Haptics` — haptics abstraction;
  `IosHapticEngine` uses `UIImpactFeedbackGenerator`.
- `PcmAudioMixer` — software-mixing float32 PCM mixer replacing OpenAL (derived from the
  NUKEHOUR port).
- `Renderer` / `IGraphicsContext.SetViewport` — force the framebuffer viewport every frame
  (see finding #2).
- `Sdl2Input.EventPosition` — pass iOS mouse/touch positions through unscaled (finding #5).
- `InternalsVisibleTo("OpenRA.iOS")` in `OpenRA.Game.csproj`.

These are modeled on the NUKEHOUR iOS patch set; see `NOTICE`.

## Building (macOS required)

The iOS projects target `net10.0-ios` and build only on macOS (Xcode 27.1 at the time of
writing). The engine projects (`net10.0`) also build on Windows/Linux for validation.

```sh
# 1. Native static libraries (SDL2, FreeType, Lua) for device + simulator
scripts/build-native-libs.sh
#    then copy the archives into the app's native dir and wrap them as dylibs:
cp native/libs/arm64-apple-ios27.0-simulator/lib*.a     OpenRA.iOS/native/iossimulator-arm64/
cp native/libs/arm64-apple-ios27.0/lib*.a               OpenRA.iOS/native/ios-arm64/
scripts/build-dylibs.sh && scripts/fix-dylib-install-names.sh

# 2. Engine content archive (glsl + mods) bundled into the app
scripts/package-assets.sh

# 3. Simulator build + install + launch + screenshot (the autonomous dev loop)
scripts/sim-deploy.sh
#    builds iossimulator-arm64 (no codesign), installs to a standard iPhone sim, launches,
#    and writes /tmp/shot.png. See finding #1 for why a standard iPhone sim, not the DUO.

# 4. Device build + codesign + install
#    dotnet build OpenRA.iOS/OpenRA.iOS.csproj -f net10.0-ios -c Release \
#        -p:RuntimeIdentifier=ios-arm64 -p:CodeSignOnBuild=true \
#        -p:CodesignKey=<SHA1> -p:CodesignProvision=<profile-guid> -p:DevelopmentTeam=<team>
#    xcrun devicectl device install app --device <UDID> bin/ios-arm64/OpenRA.iOS.app
#    xcrun devicectl device process launch --device <UDID> <bundle-id>
```

The app expects the original Red Alert 1 data (`ra.mix` …) — either bundled as a content
zip extracted at launch, or copied into the app's `Documents/OpenRA/...` area.

## Status

Renders and responds to touch on the physical iPhone Duo; the day-to-day dev loop runs
autonomously on a standard iPhone simulator (`scripts/sim-deploy.sh`, see finding #1).

## License

GPL v3 or later. See `NOTICE` for attribution of derived code.
