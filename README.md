# OpenRA for iOS

A port of [OpenRA](https://github.com/OpenRA/OpenRA) (C&C: Red Alert 1, mod `ra`)
to iOS, targeting the iPhone Duo (iOS 27+, A20 Pro, foldable). Landscape-only,
touch-friendly, with haptics and (later) two-finger gesture controls.

The engine already has full OpenGL ES 3.0 support upstream
(`Graphics.GLProfile=Embedded`), which makes the rendering path nearly a
no-op; the port work is platform plumbing (SDL2/FreeType/Lua native libs),
an iOS `IPlatform`, touch input, and AOT-compliant assembly loading.

See `../REPORT.md` and `../SCAFFOLDING_PLAN.md` (workspace root) for the full
investigation and the phased execution plan.

## Layout

| Path | What |
|---|---|
| `OpenRA.Game/`, `OpenRA.Mods.*/`, `OpenRA.Platforms.Default/`, `OpenRA.Launcher/`, `glsl/`, `mods/` | Vendored upstream engine (pinned commit), with small local modifications for iOS |
| `OpenRA.Platforms.iOS/` | iOS `IPlatform` (SDL2 window, SDL2-mixed sound engine, UIKit haptics, FreeType font); compiles the Default platform sources minus `DefaultPlatform.cs`/`OpenAlSoundEngine.cs` and publishes as `OpenRA.Platforms.Default.dll` |
| `OpenRA.iOS/` | The app: UIKit bootstrap, native library resolution, asset extraction, launch args |
| `scripts/` | `sync-upstream.sh` (re-vendor engine), `build-native-libs.sh` (Mac: SDL2/FreeType/Lua static libs), `package-assets.sh` (engine content zip) |

## Local engine modifications (the "port patch set")

Applied to the vendored `OpenRA.Game` / `OpenRA.Platforms.Default`:

- `Game.PlatformFactoryOverride` — inject `IosPlatform` without dynamic
  platform-assembly loading (AOT-friendly; desktop path unchanged).
- `ObjectCreator.LoaderFactoryOverride` + `LoadAssembly` iOS branch — mod
  format loaders are registered explicitly; bundled assemblies resolve from
  the app image instead of being loaded from disk.
- `PlatformType.iOS` + `Platform.OverrideHostPlatform` — correct platform
  detection under the iOS hosting environment.
- `IHapticEngine` / `IPlatform.CreateHaptics` / `Game.Haptics` — haptics
  abstraction; `IosHapticEngine` uses `UIImpactFeedbackGenerator`.
- `PcmAudioMixer` — software software-mixing float32 PCM mixer replacing
  OpenAL (derived from the NUKEHOUR port).
- `InternalsVisibleTo("OpenRA.iOS")` in `OpenRA.Game.csproj`.

These are modeled on the NUKEHOUR iOS patch set; see `NOTICE`.

## Building (macOS required)

The iOS projects target `net10.0-ios` and can only be built on macOS.
The engine projects (`net10.0`) also build on Windows/Linux for validation.

```sh
# 1. Native static libraries (SDL2, FreeType, Lua) for device + simulator
scripts/build-native-libs.sh
cp -R native/libs/* OpenRA.iOS/native/
#    then uncomment the NativeReference entries in OpenRA.iOS/OpenRA.iOS.csproj

# 2. Engine content archive (glsl + mods) bundled into the app
scripts/package-assets.sh

# 3. Build for the simulator (first iteration)
dotnet build OpenRA.iOS/OpenRA.iOS.csproj -c Release \
    -p:TargetPlatformIdentifier=ios -p:RuntimeIdentifier=ios-arm64 \
    -p:UseInterpreter=true

# 4. Run in the iOS simulator
open -a Simulator && ios-deploy --bundle bin/ios-arm64/Release/10.0/OpenRA.iOS.app
#    (or just drag the .app onto the Simulator; `dotnet build` emits a runnable .app)
```

The app expects the original Red Alert data (`ra.mix` ...) as a
`ra-content.zip` inside the app's Documents/Support area, or you can copy
`ra.mix` into `Documents/OpenRA/Support/ra` over USB (File app / Finder
sharing). See `SCAFFOLDING_PLAN.md` Phase 5 for the content flow.

## Status

Phase 1 (scaffolding) — see `SCAFFOLDING_PLAN.md` for the full phased plan
and per-phase acceptance criteria.

## License

GPL v3 or later. See `NOTICE` for attribution of derived code.
