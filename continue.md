# Continue — ScanPay session handoff

> Living doc. Update at the end of each working session so the next one starts
> cheap and accurate. Newest status at the top.

## Where we are (2026-06-20)

**Phase 1 (native ultrawide camera) is code-complete and waiting on the on-device
gate.** Everything else is intentionally NOT built yet — we de-risk the camera first.

- Branch: `feat/scanpay-mvp` (off `main`).
- `flutter analyze` clean. `flutter test` green (4 tests, `pickUltrawide`).
- Debug APK build: see "Build status" below.
- App currently boots straight into the **camera probe** ([lib/scan/camera_probe.dart](lib/scan/camera_probe.dart)),
  not the real UI. That is deliberate — it's the diagnostic for the gate.

### THE GATE (do this next, needs the physical S21 FE)

1. Plug in the S21 FE (USB debugging on). `flutter devices` to get its id.
2. `flutter run -d <device-id>`.
3. On screen, confirm **all** of:
   - The camera list shows multiple back cameras with focal lengths.
   - The row tagged `ultrawide?` (auto-pick = shortest focal length, likely id `2`)
     shows a **live preview**, not a black frame (black = the dead main lens).
   - If the auto-pick is black/wrong, **tap other rows** until one shows a live
     ~0.5x wide view. Note that id.
   - Point at any UPI QR → the `decoded` panel prints a green `upi://pay?...` string.
4. Tell me: which camera id is the real ultrawide, and that a QR decoded.

**If the gate passes** → proceed to build the rest (see plan). **If no back camera
shows a live preview at all**, the hypothesis fails and we rethink (see Risks).

## Next steps (after the gate)

Resume the plan at Phase 2: [docs/superpowers/plans/2026-06-20-scanpay.md](docs/superpowers/plans/2026-06-20-scanpay.md).
Order: UPI parse → security validation → categories → uri builder → repos →
verify sheet → reticle → scan screen (replaces probe) → intake → history/favorites
UI → onboarding/settings → nav. All of that is device-independent and TDD'd.
Persist the confirmed ultrawide camera id (PrefKeys.cameraId) so the real scan
screen skips enumeration.

## Build status

- `flutter build apk --debug` → **PASSED** (EXIT=0). Kotlin compiles, Camera2 + ML Kit
  link, APK assembles. No native compile surprises expected on-device.
- Note: run `flutter`/build commands in the **foreground PowerShell** shell. The Bash
  tool and background shells intermittently lack the user PATH (`flutter` at
  `C:\flutter\bin`). PowerShell finds it reliably.

## Risks / watch-items

- **Ultrawide reachability is the whole hypothesis.** Pure Camera2 opens the physical
  id directly (most reliable). If even that can't get a live ultrawide preview, options
  are: try the id as a *physical* sub-camera of logical "0", or accept the device can't
  expose it outside the stock app.
- ML Kit `InputImage` rotation is set to the sensor orientation; if decoding is flaky,
  revisit rotation handling in [CameraController.kt](android/app/src/main/kotlin/com/scanpay/scanpay/CameraController.kt).
- Ultrawide is usually **fixed-focus, may lack flash** — controls must stay
  capability-aware (already modeled in `CameraInfo`).

## Handy commands

```bash
flutter analyze
flutter test
flutter devices
flutter run -d <id>        # the gate
flutter build apk --debug  # compile-check Kotlin without a device
```
