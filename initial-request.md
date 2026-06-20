# Claude Code Prompt — Build "ScanPay" Flutter App

Build a Flutter **Android** app called **ScanPay**: a UPI QR scan-and-pay utility
built for one stubborn problem. The target device is a **Samsung Galaxy S21 FE**
whose **main rear camera is physically broken**, but whose **ultrawide rear lens
still works**. The stock camera, PhonePe, GPay and Paytm all bind to the dead main
lens, so the user literally cannot scan a QR to pay. ScanPay forces the working
**ultrawide** lens, decodes the UPI QR itself, lets the user verify and set the
amount, then hands a `upi://pay` URI to an installed UPI app via an Android intent.

Primary platform is Android only. Don't spend effort on iOS/web.

> This is not a hobby toy — it's meant to be the app the user reaches for on every
> payment, on a broken phone, in front of a waiting shopkeeper. That sets the bar.

## Three pillars (every decision serves these, in order)

1. **Secure** — it touches money. Strictly validate every QR, never pay without a
   one-glance review, never fabricate or silently alter an amount, and make **zero
   network requests** (there is no backend and no data leaves the device).
2. **Fast** — cold-start straight into a live ultrawide preview that is already
   scanning. No splash. Decode-ready in well under a second on warm start. The whole
   scan→pay path is at most: point, glance, confirm.
3. **Beautiful** — dark, scanner-first, one signature element (the animated reticle),
   everything else quiet. Purposeful motion and haptics. It should feel like a
   precision instrument, not a generic-fintech form.

---

## CRITICAL REQUIREMENT — reaching the ultrawide lens (read first)

The entire app is pointless if it can't reach the **true ultrawide** physical camera,
because the main lens is dead. On the S21 FE, `mobile_scanner`'s `wide` lens selection
is known to be unreliable and can resolve to the broken main lens
(flutter/flutter #173406, "Unable to Select Ultra-Wide Camera on Samsung S21 FE").
So we treat the **native physical-camera path as primary**, not as a fallback.

Build it behind one clean interface (`LensController`) with two implementations, so
either path can drive the same UI:

### Primary — native Camera2/CameraX physical-camera shim (Kotlin)

- Enumerate `CameraManager.cameraIdList`. Among **back-facing** cameras, the ultrawide
  is the one with the **shortest entry in `LENS_INFO_AVAILABLE_FOCAL_LENGTHS`**
  (typically physical id `"2"` on the S21 FE). Select it by **physical camera id**.
  Prefer raw Camera2 to guarantee opening that physical id; use CameraX for the
  Preview + ImageAnalysis plumbing if it can target the physical id, else go full
  Camera2.
- Run an ML Kit barcode `ImageAnalysis` use case on the stream; push decoded strings
  to Dart over an **EventChannel**. Render the preview into a Flutter `Texture`.
- **MethodChannel** surface (Dart ⇄ native):
  `enumerateCameras()` → list of `{id, facing, minFocalLength, hasFlash, hasAF, zoomRange}`,
  `start(physicalId)`, `stop()`, `setTorch(bool)`, `setZoom(double)`,
  `focusAt(x, y)`. Returns a `textureId` to Dart for the `Texture` widget.
- **Remember the chosen physical id** in prefs so subsequent launches go straight to
  the known-good ultrawide with no enumeration delay.

### Secondary — pure-Dart `mobile_scanner` path

- `mobile_scanner` (latest, Flutter 3.29+) with lens selection:
  ```dart
  await controller.switchCamera(const SelectCamera(lensType: CameraLensType.wide));
  final supported = await controller.getSupportedLenses(); // Set<CameraLensType>
  ```
- A "cycle lens" control that walks the supported lenses, showing the active one in a
  chip; default to `wide`. Used as the fallback if the native path is unavailable, and
  as the fast scaffold to get end-to-end scanning working first.

### Capability-aware controls (important)

The ultrawide is frequently **fixed-focus and may have no flash** (the LED is usually
on the main module). Query the **active** camera's capabilities and **show/hide
controls accordingly** — don't render a tap-to-focus ring or torch button the active
lens can't honor. Degrade gracefully; never present a dead control.

### On-device verification

A toggleable debug readout (long-press the lens chip) printing: every enumerated
camera id, facing, focal lengths, flash/AF support, and which id is **active**. This
is how the user confirms the active camera is the real 0.5× ultrawide and not the
dead main lens.

Build order: stand up the Dart path first to get scanning working end-to-end, then
implement the native shim as the primary path behind the `LensController` seam.

---

## Core flow — scan → verify → pay

This is the heart of the app. **Decoding a QR never launches a payment directly.**
It opens a fast **Verify sheet**; the user confirms; *then* the intent fires.

```
camera (scanning)
   │  decode upi:// QR  ──►  soft lock (brackets snap amber, haptic + optional beep, sweep stops)
   ▼
┌─ Verify sheet (bottom sheet, springs up) ──────────────┐
│  • Payee name (pn)          ← large, friendly           │
│  • VPA (pa)                 ← monospace, always shown    │
│  • category pill · note (tn)                            │
│  • safety indicator         ← shield: ok / caution / stop│
│                                                          │
│  Amount:                                                 │
│    fixed (am present) → shown locked, "set by merchant"  │
│    open  (am blank)   → in-app numpad, ₹, quick +10/+50  │
│                                                          │
│  [ app selector: default UPI app  ▸ ]                    │
│  [  Pay with PhonePe  ]   ← builds upi://pay, fires intent│
└──────────────────────────────────────────────────────────┘
   confirm ─► launch UPI app (amount pre-filled) ─► log scan
   cancel  ─► back to scanning
```

The Verify sheet is the **single convergence point** for all three ways a payment
starts — a scanned QR, a shared/pasted QR or `upi://` link, and a tapped Quick-Pay
favorite. All three run the same validation, the same review, the same launch. This
keeps the security model in exactly one place.

**Why the VPA is always shown in monospace:** the friendly name (`pn`) is attacker-
controlled text. Showing the raw `pa` prevents a lookalike display name from
socially-engineering the user into paying the wrong handle.

---

## Features by screen

### Scan screen (home)
- Full-screen ultrawide camera preview (native `Texture`, or `mobile_scanner` on the
  Dart path).
- **Reticle overlay**: dimmed scrim with a clear rounded-square scan window, four
  corner brackets, and an animated sweeping line. Brackets/sweep are **signal lime**
  while scanning; on a successful lock they snap to **amber**, the sweep stops, and a
  short haptic + optional beep fire. On a rejected/unsafe QR they flash **alert red**
  with a one-line hint and scanning continues.
- **Right-side control rail** (only controls the active lens supports): torch toggle,
  scan-from-gallery, lens cycle, settings.
- **Paste UPI link chip**: if the clipboard holds a `upi://` link, show a chip to pay
  it via the Verify sheet (no camera needed).
- **Scan-from-gallery**: pick an image and decode any QR inside it (no storage
  permission beyond the system photo picker).
- **Pinch-to-zoom** (digital zoom on the ultrawide).
- **Tap-to-focus** with a focus-ring animation — *only if the active lens has AF*.
- **Quick-Pay strip** above the bottom nav: horizontally scrollable chips of saved
  payees. Tapping one opens the **Verify sheet** pre-set to that VPA (amount pad up),
  not a blind fire. An "Add" chip opens a manual-add dialog (VPA + display name +
  optional note).

### Verify sheet & payment launch
- Parse the UPI URI fields: `pa` (VPA), `pn` (name), `am` (amount, often blank),
  `cu` (currency), `tn` (note), `tr` (txn ref), `mc` (merchant category code).
- **In-app amount pad** for open-amount QRs: enter ₹ on ScanPay's own numpad and pass
  it as `am`, so the UPI app opens **pre-filled** — this is the core tap-saver. Quick
  add chips (+10 / +50 / +100). Fixed `am` is shown read-only and never altered.
- **App selector:** a default UPI app (resolve installed handlers by querying the
  `upi://pay` intent) or "Always ask" (system chooser). If a default is set and still
  installed, launch straight to it; otherwise show the chooser. Persist the choice.
- Fire `ACTION_VIEW` on the built `upi://pay` URI via `android_intent_plus` /
  `url_launcher`, with `FLAG_ACTIVITY_NEW_TASK`. Do **not** gate on `resolveActivity`
  (Android 11+ package-visibility makes it unreliable) — just launch and catch
  `ActivityNotFoundException`, showing a clear "no UPI app found" message. Add the
  `<queries>` entry for the `upi` scheme in the manifest.

### Share & paste in (pay QRs you can't point the camera at)
- Register an Android **share-target** intent filter: receiving a **shared image**
  (`image/*`) decodes any QR in it via ML Kit; receiving **shared text / a `upi://`
  link** parses it directly. Both route into the Verify sheet.
- This is a real workaround for a broken-camera phone: pay a QR sitting in a WhatsApp
  chat, a screenshot, or a webpage without needing the lens at all.

### History tab
- Bottom nav: **Scan** and **History**.
- History is built **only from QR metadata captured at scan time**. Be honest in the
  UI that this is a **scan log, not a payment ledger** — the OS never reports whether
  a payment actually succeeded.
- Each row, minimal: payee name, time, a colored **category** pill, and amount. Show
  the amount only when it was known (fixed `am`, or the amount the user typed in the
  pad); otherwise "enter amt". A user-tappable **"mark paid"** status, since
  confirmation can only ever be manual.
- A summary strip: scans this month, sum of known-amount scans (**clearly labeled
  partial**), and top category.
- **Category logic:** map `mc` (ISO 18245 MCC) when present, else keyword-match the
  payee name. Categories: Food, Travel, Shopping, Bills, Other. Reasonable Indian
  merchant keywords (swiggy/zomato→Food, petrol/uber/ola/irctc→Travel,
  blinkit/zepto/mart/kirana→Shopping, power/gas/recharge/dth→Bills).

---

## Security model (give it teeth)

ScanPay handles money, so security is a first-class feature, not a footnote.

- **Strict URI validation** (in one place, `pay/upi_validator.dart`):
  - Scheme must be `upi`; accept only **pay** intents. **Reject `upi://collect`,
    mandate/autopay, and anything that would pull money *from* the user** — show an
    alert-red "this is a request to collect money from you, not a payment" warning and
    do **not** open the pay sheet.
  - Allow-list known param keys; **ignore/strip unknown or suspicious params**.
    Enforce `cu=INR` (warn on any other currency).
  - `pa` must look like a valid VPA (`name@handle`); `am` must be a positive number
    with ≤2 decimals — reject malformed values rather than passing them through.
- **Always review before pay** — the Verify sheet is mandatory; there is no silent
  auto-launch path anywhere.
- **Large-amount guard:** if the amount ≥ a configurable threshold (default ₹5,000),
  require a second explicit confirm with the amount spelled out.
- **Show the raw VPA** (monospace) so a spoofed display name can't hide the real
  payee.
- **Zero network:** the app makes no network requests at all. State this in onboarding
  and settings ("ScanPay never connects to the internet"). Don't persist full VPAs in
  any debug log.
- **First-run rationale screen** (one tasteful screen): explains the ultrawide reason,
  the camera permission, and the no-internet guarantee — building trust before the
  first scan.

*(Deferred, see Out of scope: an optional biometric app-lock toggle. Not built now.)*

---

## Design system / theme

Dark, scanner-first, minimal. The animated reticle is the one signature element;
everything else stays quiet. Avoid generic-fintech blue. Purposeful motion + haptics.

**Palette**
- ink `#0B0E11` (bg), slate `#161B22` (surfaces), slate-soft `#1F2630` (borders)
- mist `#8B98A5` (muted text), cloud `#E6EDF3` (primary text)
- signal lime `#B6FF3A` (accent / scanning), amber `#FFB627` (lock / torch / caution)
- **alert red `#FF5C5C` (errors / rejected QR / collect-request / large-amount stop)**
  — *new; the original palette had no error color, and the security UX needs one.*
- category accents: food `#FF7A59`, travel `#4FC3F7`, shop `#B6FF3A`,
  bills `#FFB627`, other `#8B98A5`

**Type:** monospace for the `scan·pay` wordmark, lens chip, VPA, amounts, and small
labels (letter-spaced); clean sans for everything else. Rounded corners (~14–22px on
cards/windows/sheets).

**Motion & feedback**
- Reticle sweep (lime) → lock snap (amber) + haptic + optional beep (**off by
  default**, toggle in settings); reject → red flash.
- Verify sheet springs up; numpad keys have press feedback; pay confirm fires a haptic.
- A **safety shield** indicator in the Verify sheet: lime check (clean), amber caution
  (open amount / odd field), red stop (collect-request / malformed / over threshold).

**Layout & accessibility**
- Right-side control rail for torch/gallery/lens/settings. Two-tab bottom nav.
- One-handed friendly; large tap targets; amount text large and high-contrast (this is
  a daily driver on a broken phone — legibility matters).
- Designed empty/permission/no-UPI-app states, not framework defaults.

---

## Persistence

- `shared_preferences` for: chosen physical camera id, default UPI app package,
  large-amount threshold, sound-on-lock toggle (default off), favorites (JSON), and scan history
  (JSON, capped at last ~200 entries). No backend, no accounts — local only.
- Wrap prefs in a simple repository class so it's swappable for a real DB later.

---

## Packages (latest compatible)
- `mobile_scanner` — Dart-path camera + ML Kit barcode + lens selection
- `android_intent_plus` (or `url_launcher`) — fire the UPI intent
- `shared_preferences` — local persistence
- `permission_handler` — camera permission flow if needed beyond mobile_scanner
- (native path uses CameraX/Camera2 + ML Kit barcode on the Kotlin side)

No state-management or DI frameworks — plain `setState` / a light `ChangeNotifier`.

---

## Project structure (suggested)
```
lib/
  main.dart
  app.dart                   // theme, root nav
  theme/tokens.dart          // colors, text styles
  onboarding/rationale.dart  // first-run permission + no-internet trust screen
  scan/scan_screen.dart
  scan/reticle.dart          // custom painter: scrim + brackets + sweep
  scan/lens_controller.dart  // interface: capabilities, start/stop, torch, zoom, focus
  scan/native_lens.dart      // platform-channel impl (primary)
  scan/dart_lens.dart        // mobile_scanner impl (secondary/fallback)
  pay/upi.dart               // parse upi uri, category logic
  pay/upi_validator.dart     // strict validation, collect-request rejection, guards
  pay/verify_sheet.dart      // unified review + amount pad + app selector + confirm
  pay/launcher.dart          // intent launch + default-app logic
  pay/app_picker.dart        // resolve installed UPI apps, default-app dialog
  share/share_intake.dart    // incoming shared image / upi link / clipboard
  history/history_screen.dart
  history/history_repo.dart
  favorites/favorites.dart   // model + repo + add dialog
  data/prefs.dart            // shared_preferences wrapper
android/
  .../MainActivity.kt        // camera method/event channels; intent filters
  ...                        // manifest: CAMERA, <queries> upi, share-target filter
```

---

## Build / quality bar
- Target Android, minSdk 24, compileSdk current.
- Manifest: `CAMERA` permission, `<queries>` for the `upi` scheme, share-target intent
  filter (`image/*` and `text/plain`).
- Handle the camera-permission flow cleanly (rationale screen → request → graceful
  denied state).
- Null-safe, no analyzer warnings, runnable with `flutter run` on a connected S21 FE.
- Verify the **zero-network** claim (no HTTP clients, no analytics SDKs).
- After building, give me: (1) the exact commands to run it on my phone, and (2) a
  one-line note on what to check first via the debug readout — whether the **active
  camera is the true ultrawide** (0.5×, shortest focal length) and not the dead main
  lens, so I know the native path is landing correctly.

## Honesty constraints (keep these true in the UI copy)
- Don't imply the app confirms payments. It can't. History = scan log + manual "paid".
- Favorites can only store payees the user scanned or typed; the app can't read
  PhonePe contacts.
- Amount is frequently unknown (open-amount QRs); never fabricate spend totals — the
  summary is explicitly labeled partial.

## Out of scope (deferred — phase 2, do not build now)
- **Biometric app-lock** (optional toggle to open app / view history).
- **One-tap re-pay** from history and auto-promoting frequent payees into Quick Pay.
- **Quick-launch widget / quick-settings tile** that opens straight into the scanner.
- These are noted so the architecture leaves room for them, but they are not in this
  build.

---

Start with the Dart-only path to get scanning working end-to-end, then build the
**native ultrawide shim as the primary path** behind the `LensController` seam, test
the active camera on-device via the debug readout, and wire the Verify-sheet flow so
no payment ever fires without a one-glance confirm.
