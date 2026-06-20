# CLAUDE.md — ScanPay

Project context for AI sessions. Read [continue.md](continue.md) for current status
and [decisions.md](decisions.md) for *why* things are the way they are before changing
anything. The full spec is [initial-request.md](initial-request.md); the build plan is
[docs/superpowers/plans/2026-06-20-scanpay.md](docs/superpowers/plans/2026-06-20-scanpay.md).

## What this is
A Flutter **Android** app that lets a Samsung **S21 FE with a dead main rear lens** scan
UPI QR codes by forcing the **working ultrawide lens** (native Camera2), then review and
pay via an installed UPI app (PhonePe/GPay/Paytm) over an Android intent. Local-only,
no backend, no accounts, **zero network calls**.

## Non-negotiables (don't violate without asking)
- **Camera is native-only.** Do NOT add `mobile_scanner` or `camera`. Ultrawide is
  reached by opening the physical camera id (shortest focal length among back cameras)
  via Camera2. See [decisions.md](decisions.md) D1.
- **Never auto-fire a payment.** Every pay goes through the Verify sheet + explicit
  confirm. Block `upi://collect`/mandate. Always show the raw VPA. (D3, D4)
- **Zero network.** No HTTP client, no analytics SDK. It's a stated security property.
- **Honesty copy.** History is a *scan log, not a payment ledger*; "paid" is manual;
  spend totals are labeled partial; favorites only hold scanned/typed payees. (D9)
- **Beep on lock defaults OFF.** Haptic stays.

## Workflow expectations (this user)
- De-risk the make-or-break first; stop at a real-device gate and let the user test
  before building more. Don't build the whole app speculatively.
- TDD the pure-Dart logic (parse/validate/categories/repos): failing test → code → pass.
- Native camera can't be unit-tested here — it verifies on the physical S21 FE.
- Branch off `main`; commit per task; don't push unless asked.
- Keep [continue.md](continue.md) and [decisions.md](decisions.md) current at session end.

## Identifiers & toolchain
- Dart package: `scanpay` → imports are `package:scanpay/...`.
- Android applicationId / Kotlin package: `com.scanpay.scanpay`
  (native files: `android/app/src/main/kotlin/com/scanpay/scanpay/`).
- Flutter 3.44+, Dart 3.12+, minSdk 24, ML Kit `barcode-scanning:17.3.0`.
- Platform shells: PowerShell (primary) and a Bash tool. **Background commands do NOT
  inherit the user PATH** (no `flutter`/`tail` there) — run `flutter`/build commands in
  the **foreground** shell.

## Commands
```bash
flutter analyze            # must be clean
flutter test               # all green before commit
flutter devices            # find the S21 FE
flutter run -d <id>        # on-device (the camera gate)
flutter build apk --debug  # compile-check Kotlin (foreground only)
```

## Code map (current + planned)
```
lib/
  main.dart                  -> currently boots the camera PROBE (Phase-1 gate)
  theme/tokens.dart          dark palette + theme
  scan/lens_controller.dart  CameraInfo, pickUltrawide, LensController, NativeLens
  scan/camera_probe.dart     diagnostic screen (enumerate/preview/decode) — temporary
  # planned post-gate: pay/upi.dart, pay/upi_validator.dart, pay/categories.dart,
  # pay/launcher.dart, pay/verify_sheet.dart, data/prefs.dart, favorites/, history/,
  # scan/reticle.dart, scan/scan_screen.dart (replaces probe), settings/, onboarding/
android/app/src/main/kotlin/com/scanpay/scanpay/
  CameraController.kt        Camera2 enumerate + open physical id + ML Kit decode
  MainActivity.kt            method/event channel wiring (scanpay/camera, scanpay/barcodes)
```

## Theme tokens (use these, never hard-code colors)
ink `#0B0E11` bg · slate `#161B22` surface · slateSoft `#1F2630` border · mist `#8B98A5`
muted · cloud `#E6EDF3` text · lime `#B6FF3A` scan accent · amber `#FFB627` lock/torch ·
alertRed `#FF5C5C` errors/blocked. Monospace for wordmark, VPA, amounts, small labels.
