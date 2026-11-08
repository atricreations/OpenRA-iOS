# Bug list & TODO (OpenRA iOS)

Running list — we fix these as we go. Update the `[x]` boxes and the **Status log**
here as items land. Verification: pure rendering bugs via the autonomous sim loop
(`scripts/sim-deploy.sh` → screenshot); input / audio / in-game bugs on the physical DUO
via `scripts/device-deploy.sh` (the sim can't reach an in-game map or toggle the hardware
silent switch).

## Bugs
- [x] **1. Radar ignores taps.** The in-game map radar does not respond to taps (no
  camera-pan / click-to-move via the radar), while normal UI buttons work. **FIXED (verified).**
  - **Root cause (revised this round):** two things combine.
    1. **The radar is disabled at game start** (standard RA1 behavior): the player owns no
       `ProvidesRadar` building, so `IngameRadarDisplayLogic` keeps `radarEnabled=false`, the
       minimap shows the faction "no-radar" placeholder, and a disabled radar ignores taps
       (`HandleMouseInput` returns before centering). This is why the on-device radar "did
       nothing" — there was no radar to tap yet.
    2. **Touch taps map to the Classic action button.** When the radar *is* enabled, the
       original gate `Down && mi.Button != world.OrderGenerator.ActionButton` never fires for a
       touch tap (synthesized on the action button), so it never centered.
  - **Fix:** (a) *User decision — keep RA1 behavior:* the radar stays off until a radar is built
       (a temporary force-enable used for testing was reverted). (b) `RadarWidget.HandleMouseInput`:
       recompute `mapRect` from the live `RenderOrigin` every input so the hit-test matches where
       the minimap is actually drawn (incl. disabled/animation states); make **any** `Down` on the
       radar center the camera (drag-to-move still works); clear `ViewportCenterProvider` so e.g.
       `CameraOvalMover` on shellmap maps stops re-centering and fighting the call.
  - **Verified:** with the radar force-enabled, a tap at (660,90) reached `HandleMouseInput`
       (`mapRect` contains the point, `hasRadar=true`) and **the camera panned** (idb_r3: the
       viewport rect jumped to the tapped cell, player dot moved). In the clean build the radar
       correctly shows the disabled placeholder until a radar is built.
- [x] **2. Shroud / fog-of-war: 1px lines at cell edges.** Horizontal 1px lines across the
  shrouded region, periodic at the 24px shroud-cell size (confirmed on the physical DUO
  screen, not a capture artifact). **FIXED (verified on-device).**
  - **Root cause (confirmed 2026-11-08):** iOS (GL-on-Metal) leaves a **1px coverage gap at the
    boundaries of the per-cell shroud/fog quads** (`ShroudRenderer` → `TerrainSpriteLayer`
    vertex buffer; exact 24×24 quads at integer world-buffer positions). The rasterizer does
    not write the boundary row for every cell, so the terrain underneath shows through as a 1px
    line at the shroud-cell period. The upstream `Sprite` UV `Inset` (1/128 px per edge) guards
    *sampling* outside the sprite rect, not *coverage* — zeroing it on iOS changed nothing.
  - **Ruled out (on-device evidence):** shroud **palette** (GPU atlas row == CPU palette
    byte-for-byte); **UV inset** (zeroed on iOS, no change); world→screen **filter** (lines
    persist with both `Nearest` and `Linear`); per-pixel **alpha** (world-buffer alpha = 255
    everywhere). Note: the raw `worldBuffer` readback did not match the presented pixels on this
    device (opaque black + bright 24px edges vs the soft dark cloud on screen), so the fix was
    judged on the physical screen, not the readback.
  - **Fix:** `ShroudRenderer` draws each shroud/fog cell sprite **1px larger on iOS**
    (`cellOverlapScale = 1 + 1/TileSize`, set in `WorldLoaded`, applied to both
    `shroudLayer.Update`/`fogLayer.Update`), so every cell overlaps its neighbors by 1px and no
    boundary row can be uncovered. Visually neutral: opaque-black-over-opaque-black in shrouded
    interiors; the extra row is near-transparent art at feathered edges.
  - **Verified on-device (2026-11-08):** user started a skirmish on the DUO — the horizontal
    lines are gone.
- [ ] **3. Some building icons are hard to read.** A number of building icons (build panel /
  on-map) are illegible — too small, low-contrast, or wrong tint.
  - **Root cause (needs in-game shot to confirm):** production-palette icons are drawn with
    `DrawSpriteCentered` into a fixed `IconSize` (64×48 pt) rect. On the high-res DUO that
    upscales the source sprite; linear texture filtering would blur it. A screenshot is needed
    to tell blur (filtering) from wrong tint (palette) from clipping (offset).
  - **Status:** needs an in-game screenshot of the build panel to confirm the cause.
- [x] **4. Respect the phone's silent switch.** Audio plays even when the device is silenced;
  the app should honor iOS ringer/silent settings. **FIXED (verified on-device).**
  - **Fix (committed 1f85a70):** `AVAudioSession` category `Playback` (ignores the silent
    switch) → `Ambient` (respects it, and mixes with other audio). Kept `MixWithOthers`.
  - **Why the one-shot set wasn't enough:** SDL's native CoreAudio backend re-sets the category
    to `Playback` after audio init, so a single `Ambient` set got overridden (user: "silence does
    not work"). Added a **background-thread re-assert** in `AppDelegate`: a 1 Hz timer for the
    first 60 s re-sets `Ambient` (and logs the live category to `audio.log`) so it survives any
    SDL override (the game loop blocks the main run loop, so it can't be an `NSTimer`).
  - **Verified on-device (2026-11-07):** user toggled the DUO's silent switch in-game and
    confirmed audio mutes — the re-assert holds the `Ambient` category through SDL's override.
- [x] **5. Skirmish lobby overflows the landscape window (Start Game / Disconnect off-screen).**
  On the 874×402 pt landscape window the 900×600 `SERVER_LOBBY` centered vertically overflowed
  top and bottom, pushing the chat box and the `START_GAME_BUTTON` / `DISCONNECT_BUTTON`
  (both at `PARENT_HEIGHT-…`) below the visible area — so a game could not be started on the
  phone. **FIXED (verified).**
  - **Root cause:** `mods/common/chrome/lobby.yaml` `Background@SERVER_LOBBY` is a fixed
    `Width: 900, Height: 600` centered on the window; on a 402-pt-tall window the bottom 198 pt
    (incl. the bottom button row) is clipped.
  - **Fix (rescale to fit, per user decision):** `Height: 600` → `Height: WINDOW_HEIGHT` (fills
    the window; the Y-centering then resolves to 0) and shrank `Container@LOBBYCHAT`
    `Height: 259` → `62` so the chat sits in the bottom strip below the tabs instead of
    overlapping the middle panels. All controls now fit: player slots, Players/Options/Music
    tabs, Slot Admin, Change Map, chat, **Start Game**, **Back**.
  - **Verified:** navigated to the Skirmish lobby — every control is on-screen; tapping the real
    **Start Game** loaded the map and started the game (nav6 → nav8).

## Features / enhancements
- [x] **6. Virtual trackball (camera pan).** On-screen trackball above the bottom-left
  control cluster that pans the in-game camera/map, with **momentum (inertia)** and **haptics**
  on drag. **FIXED (verified on-device).**
  - **Design decision (user):** the first pass moved the UI *cursor*, but on touch that does
    nothing useful (no hover to gain, and edge-scroll is disabled on iOS via
    `Game.ViewportEdgeScroll=False`), so there was **no way to pan the map at all**. Per the user
    the trackball now **pans the camera** (relative/joystick metaphor: push right → the view pans
    right) — the primary way to navigate on touch, where keyboard / edge-scroll / middle-drag are
    unavailable.
  - **Implemented:** `TrackballWidget` (`OpenRA.Mods.Common/Widgets/TrackballWidget.cs`), wired
    into `mods/common/chrome/ingame.yaml` `WORLD_ROOT` at bottom-left. Gets its `WorldRenderer`
    via `[ObjectCreator.UseCtor]` (the same ctor-injection `ViewportControllerWidget` uses). Drag
    → `worldRenderer.Viewport.Scroll(delta * Sensitivity, false)` (screen-px deltas, clamped to
    map bounds); release velocity decays per tick in `Tick()` (`Friction`) for a flick-to-glide
    momentum. `Game.Haptics.Play(LightningStrike)` on press/drag (no-op off iOS). Hidden off-iOS
    via `Initialize` (`IsVisible = () => Visible && Platform.IsIOS`). Tuned on-device: 120×120 pt
    disc, `Sensitivity: 1.725`.
  - **Why it was invisible at first (root cause):** the device data container persists across
    reinstalls, and `AssetExtractor` only re-extracts when its stamp mismatches — so the old
    (trackball-less) `openra-data.zip` stayed loaded even after a fresh install. Fixed once by a
    clean install, then permanently by a content-hash stamp (see Round 6).
  - **Verified on-device:** disc renders bottom-left; dragging pans the map in the pushed
    direction; flick glides with momentum. User confirmed the 120 pt size and `Sensitivity 1.725`
    speed feel right.

## Status log
- **Round 7 (shroud lines root-caused + fixed; diagnostics stripped).**
  (a) **Bug #2 closed:** the 24px-periodic horizontal lines in the shroud are a **1px coverage
  gap at the per-cell shroud/fog quad boundaries on iOS GL-on-Metal** — not a palette issue
  (GPU atlas row == CPU palette byte-for-byte), not the UV inset (zeroing it on iOS changed
  nothing), not the world→screen filter (Nearest vs Linear both showed the lines). Fix:
  `ShroudRenderer` grows each cell sprite by 1px on iOS (`cellOverlapScale = 1 + 1/TileSize`),
  so neighboring cells overlap and no boundary row is uncovered. Verified on the DUO: lines
  gone.
  (b) **Diagnostics stripped:** removed the TEMP `PaletteDebugWidget` (+ its `ingame.yaml`
  block), `Renderer.DebugWorldBuffer` (and the iOS `Nearest` world-buffer filter experiment,
  reverted to `Linear`), `WorldRenderer.DebugHardwarePalette`, and the `ShroudRenderer` debug
  accessors. Only the `cellOverlapScale` fix remains in `ShroudRenderer`.
- **Round 6 (trackball verified on-device + device deploy loop made fast/robust).**
  (a) **Trackball (Bug #6) verified on the DUO.** It was invisible in-game at first — root cause
  was **stale asset extraction**: the device data container persists across reinstalls and
  `AssetExtractor` skipped re-extraction (stamp matched), so the old trackball-less mods stayed
  loaded. A clean install (uninstall → install) forced a fresh extract and the disc appeared.
  Then, per the user, the trackball was changed from moving the UI *cursor* to **panning the
  camera** (`worldRenderer.Viewport.Scroll`, relative/joystick metaphor + flick momentum) — the
  useful control on touch, since edge-scroll is off (`Game.ViewportEdgeScroll=False`) and there was
  otherwise no way to pan. Tuned to a 120 pt disc + `Sensitivity: 1.725`; user confirmed it feels
  right. (Note: Round 5's "build clean" was from **stale Mac-repo builds** — the true device build
  only succeeded this round after the files were `put` to the Mac and a `using OpenRA.Graphics;`
  / `using OpenRA.Primitives;` fix landed.)
  (b) **Device deploy loop fixed so it's fast and no longer needs re-trust.** The clean-uninstall
  approach made iOS drop the developer-profile trust on every deploy (launch error 3: "profile has
  not been explicitly trusted"), forcing a manual Settings → Trust step each time. Replaced it:
  `AssetExtractor` now fingerprints **app version + SHA256 of `openra-data.zip`** (`ComputeAssetStamp`),
  so a re-packaged archive re-extracts **without** a version bump, and `device-deploy.sh` does a
  **plain install (no uninstall)**. A plain reinstall keeps the profile trusted, so deploys now
  build → install → launch with no manual step and fresh assets whenever the zip changes.
  (c) **Silent switch (Bug #4) confirmed closed on-device:** user toggled the DUO's silent switch
  in-game and audio mutes — the `AppDelegate` background re-assert holds the `Ambient` category
  through SDL's CoreAudio override.
- **Round 4 (radar closed, lobby rescaled, deploy pipeline fixed, debug stripped).**
  (a) **Radar (Bug #1) closed:** confirmed the radar is *disabled at game start* (RA1: no radar
  building) so there's nothing to tap; the touch tap-handling fix (any-Down centers, `mapRect`
  from the live `RenderOrigin`, clear `ViewportCenterProvider`) was verified — a tap with the radar
  force-enabled panned the camera (idb_r3). Per the user the radar default **keeps RA1 behavior**
  (off until a radar is built); the temp force-enable was reverted.
  (b) **Lobby overflow (new Bug #5) fixed:** `lobby.yaml` `SERVER_LOBBY` rescaled to
  `Height: WINDOW_HEIGHT` and the chat box shrunk to 62 pt so all controls (slots, tabs, Change
  Map, chat, **Start Game**, **Back**) fit the 874×402 window; verified by reaching the lobby and
  starting a game.
  (c) **Deploy pipeline fix (important):** mod yml/asset edits were *not* reaching the app — they
  ship inside `openra-data.zip` (`scripts/package-assets.sh`), which a plain `dotnet build` does not
  regenerate, and `AssetExtractor` only re-extracts when the bundle-version stamp changes.
  `sim-deploy.sh` now repacks the zip from `mods/`+`glsl/` before build and clears
  `.extracted_version` after install, so mod changes take effect.
  (d) **Debug stripped:** removed all TEMP on-screen/file diagnostics (`Sdl2Input` `[IOSINPUT]`,
  `Widget` `[UI]`/`[OUTER]`, `ButtonWidget` `[BTN]`, the `RadarWidget` readout + bitmap font + file
  logs); those four files now match HEAD apart from the intended fixes. Build is clean, no
  on-screen debug in-game.
  (e) **Kept (functional, not debug):** the radar touch fix, the Bug #4 `Ambient` re-assert, and two
  **profile workarounds** — `PlayerDatabase` `Profile=http://127.0.0.1:1/` (dead port) +
  `LoadLocalPlayerProfileLogic` `minimalProfile=()=>true` — which stop the forum
  CONNECTION_ERROR/LINK_ACCOUNT panel from covering the Singleplayer button; both need a proper fix
  before shipping (bundled default profile / non-blocking profile check).
- **Round 5 (trackball feature + profile workarounds properly fixed).**
  (a) **Bug #6 virtual trackball implemented:** `TrackballWidget` (new,
  `OpenRA.Mods.Common/Widgets/TrackballWidget.cs`) wired into `mods/common/chrome/ingame.yaml`
  `WORLD_ROOT` bottom-left. Drag → drives the UI pointer via `Ui.HandleInput(Move)` with a
  re-entrancy guard so the self-injected move can't feed back into the ball while it holds mouse
  focus; release velocity decays per tick (momentum); `Game.Haptics` impact on press/drag; hidden
  off-iOS via `IsVisible = () => Visible && Platform.IsIOS`. Build clean. In-game sim confirm
  pending (sim main-menu tap nav flaky this session).
  (b) **Profile workarounds replaced with a real setting:** new `GameSettings.MinimalProfile`
  (default `true`). `LocalPlayerProfile` ctor now takes `minimalProfile` and **skips the forum
  network lookup entirely** when set (no more dead-port `127.0.0.1:1` URL — `PlayerDatabase.Profile`
  restored to the real `https://forum.openra.net/profile/`); `LoadLocalPlayerProfileLogic` reads the
  setting instead of a hardcoded `()=>true`. User can set `MinimalProfile: false` in
  `settings.yaml` to restore the full forum-profile panels. Build clean.
- **Round 3 (crash fix + radar/shroud diagnostics read).** The Round-2 build **crashed on
  startup**: `SIGABRT` on the *"OpenRA Logging Thread"* — the `Log.Write(...)` diagnostics
  (esp. the audio one firing from the background `System.Threading.Timer` thread) aborted
  OpenRA's async logging thread. **Fix:** removed both `Log.Write` calls (radar tap + audio
  re-assert); the on-screen debug boxes remain (a file log is unreliable from the sandboxed
  container anyway). After redeploy the app **runs** (process alive, startup trace reaches
  "Calling Game.InitializeAndRun", no new crash). On-device shot read: shroud channel =
  **Indexed8** (green), `hasRadar`=**true**, `WorldInteractionController`=**not null**, tap
  inside `mapRect` but the drawn minimap sits in the upper-left ⇒ radar issue is the oversized
  `mapRect`/coord mapping, not the hit-test or enable-state.
- **Round 2 (radar + shroud + silence diagnostics).** Round-1 fixes did **not** work (user:
  "radar still doesn't work", "silence does not work"); the shroud screenshot confirms a
  **light/white** shroud. Added **on-screen** diagnostics (file logs can't be pulled off the
  sandboxed app container over `devicectl`): radar hit-rect (red) + last tap (yellow) + shroud
  channel indicator (magenta = RGBA / green = Indexed8) in `RadarWidget.Draw`; a background-thread
  1 Hz / 60 s `Ambient` re-assert in `AppDelegate` (logs the live category). Deployed via
  `scripts/device-deploy.sh`. Pending: user screenshot (radar hit-rect + shroud channel) and a
  silent-switch confirm.
- **#4 (silence)** — fixed: `AVAudioSession` `Playback` → `Ambient` (committed 1f85a70).
  On-device confirm pending (silent switch).
- **#1 (radar)** — root-caused to the `mapRect` hit-test (local vs absolute coords). Hardened
  `RadarWidget.HandleMouseInput` to recompute `mapRect` from the live `RenderOrigin` and added
  a `Log.Write("radar", ...)` diagnostic. Built into the device via `scripts/device-deploy.sh`.
  On-device tap test pending.
- **#2 (shroud)** / **#3 (icons)** — root-caused to the shroud/fog sprite palette and the
  production-palette icon scaling/filtering respectively; both need an in-game screenshot to
  confirm the exact cause before the targeted fix.
