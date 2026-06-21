# Continue — ScanPay session handoff

> Living doc. Update at the end of each working session so the next one starts
> cheap and accurate. Newest status at the top.

## Where we are (2026-06-21, later) — P2P intent wall CONFIRMED; image-pay designed

On-device debugging (S21 FE, RZCW40EKBPE) settled the "₹2,000 gallery" report. It is
**not informational and not dismissable** — it's a hard wall:

- **UPI apps reject externally-initiated `upi://pay` intents for P2P (personal VPA).**
  Proven with adb, ScanPay out of the loop: PhonePe blocks *every* external P2P intent
  (with amount, without amount, even a textbook-clean URI). WhatsApp's external receiver
  returns **"Invalid UPI ID"** (no debit) — while its in-app **"Pay with UPI"** button
  paid the *same* VPA `aaryakhodke11@oksbi` (₹5 completed). So the VPA is valid; the
  external-intent path is what's walled (NPCI anti-fraud). **Not a ScanPay bug.**
- Merchant QRs (signed) are exempt — they still pay via intent. Only **friend (P2P)**
  payments hit the wall. And this user can't use the apps' own scanners (dead lens).
- **Decision:** add a **Pay-via-QR-image** path — re-encode the payment as a fresh QR,
  hand it to a UPI app's gallery/share flow (PhonePe gallery allows ≤₹2,000; WhatsApp
  image worked). Design approved + committed:
  [docs/superpowers/specs/2026-06-21-pay-via-qr-image-design.md](docs/superpowers/specs/2026-06-21-pay-via-qr-image-design.md).
  See D12. **Next:** writing-plans → de-risk gate (real ₹10 completes via gallery)
  before any UI polish.

## Where we are (2026-06-21) — first real-pay test, 3 bugs fixed

User installed the app and tried real payments. Three bugs reported and fixed
(all **device-independent, TDD'd; 40 tests green, analyze clean**):

1. **Merchant payment rejected ("receiver not accepting payments").** Root cause:
   we rebuilt the `upi://pay` URI from parsed fields, **dropping the merchant
   signature (`sign`), `mode`, `orgid`** and re-encoding `@`→`%40`. Fixed by paying
   from the **exact scanned QR** (`UpiRequest.raw`): fixed-amount QRs pass through
   byte-for-byte; open-amount QRs keep every param and only inject `am`. See D10.
2. **₹10 to a friend showed PhonePe's "pay up to ₹2,000 via gallery" sheet.**
   ⚠️ **This original read was WRONG** — see the newer 2026-06-21 block at the top. It
   is a hard block, not informational: PhonePe (and WhatsApp's external receiver) reject
   external `upi://` P2P intents outright. Fix is the Pay-via-QR-image path (D12), not
   anything in the intent. No app-picker appeared because PhonePe is the system default
   handler (the "preferred UPI app" chooser still isn't built — and wouldn't help P2P).
3. **History tab.** (a) Top slid under the status-bar clock → wrapped in `SafeArea`.
   (b) "tap to confirm" did nothing → real bug: `_reload()` passed an arrow closure
   to `setState` that returned a `Future`, which `setState` rejects, aborting the
   rebuild. Replaced whole-row tap with an explicit **Mark paid / Paid** pill (+
   haptic) and added an undoable **delete** button. See D11.

**Awaiting (device gate):** re-test a real merchant scan→verify→pay now that the QR
is passed through intact, and confirm the friend P2P case past PhonePe's ₹2,000 sheet.
Build/install was about to run when the user paused to connect the phone.

**Still to build:** Quick-Pay favorites strip + add dialog; share-target + gallery +
clipboard intake; full app-picker (default UPI app) + settings + onboarding.

## Where we are (2026-06-20)

**✅ GATE PASSED on the real S21 FE (SM G990E, id RZCW40EKBPE, Android 16).**
The native ultrawide hypothesis is proven end-to-end:
- Enumerated 4 cameras. Auto-pick landed **cam 2 = back, 1.74mm = the ultrawide**
  (the only working back lens; cam 0 main @5.40mm and cam 1 front are physically dead).
- Live preview renders into the Flutter Texture from cam 2.
- ML Kit decoded QR codes from that feed (59 hits in testing).
- → **The working ultrawide physical camera id on this device is `"2"`.** Persist it
  as `PrefKeys.cameraId` so the real scan screen skips enumeration.

**Since the gate, the full scan→pay loop is built, tested, rebranded, and installed:**
- Device-independent core (parse, validate, categories, uri-builder, prefs, favorites,
  history repos) — all TDD, **34 tests green, analyze clean**.
- Scan→**Verify sheet** (raw VPA, safety shield, amount numpad, large-amount guard)→
  launch UPI intent→log to history. Reticle (lime/amber/red) is the signature element.
- Two-tab nav (Scan / History). History is a scan-log with manual mark-paid + partial
  summary.
- **Rebranded to "Ultrawide"** — launcher name, `ultra·wide` wordmark, custom adaptive
  icon (lime wide-reticle on ink). Internal Dart package stays `scanpay`.
- Debug APK built + installed on the S21 FE.

**Awaiting:** on-device test of a real UPI scan→verify→pay (grant camera first).

**Still to build (post pay-test):** Quick-Pay favorites strip + add dialog; share-target
+ gallery + clipboard intake; full app-picker (default UPI app) + settings + onboarding.
The retired `lib/scan/camera_probe.dart` is kept as a camera diagnostic (not on the boot
path).

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
