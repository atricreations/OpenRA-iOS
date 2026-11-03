# Bug list & TODO (OpenRA iOS)

Running list — we fix these as we go. Update the `[x]` boxes and the **Status** log
here as items land. Verification: rendering bugs via the autonomous sim loop
(`scripts/sim-deploy.sh` → screenshot); input bugs via sim touch injection / on-device.

## Bugs
- [ ] **1. Radar ignores taps.** The in-game map radar does not respond to taps (no
  camera-pan / click-to-move via the radar), while normal UI buttons work. Touch→mouse
  synthesis is otherwise functional (menu buttons fire).
- [ ] **2. Shroud / fog-of-war: white pixels at segment edges.** White specks / artifacts
  along the edges of shroud (black, unexplored) and fog (translucent gray) segments.
- [ ] **3. Some building icons are hard to read.** A number of building icons (build
  panel / on-map) are illegible — too small, low-contrast, or wrong tint.
- [ ] **4. Respect the phone's silent switch.** Audio plays even when the device is
  silenced; the app should honor iOS ringer/silent settings.

## Features / enhancements
- [ ] **5. Virtual trackball for mouse movement.** Add an on-screen trackball above the
  bottom-left control cluster for pointer movement, with **momentum (inertia)** and
  **haptics** on drag.

## Status log
- (update as items are tackled: date, root cause, fix, verification)
