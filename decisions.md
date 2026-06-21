# Decisions — ScanPay

> Architecture decision record. Each entry: the decision, why, and what would
> reverse it. Keeps future sessions from re-litigating settled choices.

## D1 — Camera is 100% native (pure Camera2), no Dart camera plugin
**Decision:** Reach the ultrawide by opening the **physical camera id** directly with
Android Camera2 (Kotlin), streaming frames to ML Kit and a Flutter `Texture`. No
`mobile_scanner`, no `camera`, no CameraX.
**Why:** The S21 FE's main rear lens is physically dead. `mobile_scanner`'s `wide`
selection is proven broken on this device (flutter/flutter #173406) — it binds to the
dead lens. A "fallback to the dead lens" is worthless. Pure Camera2 is the most direct,
reliable way to open a specific physical id that higher-level abstractions miss. We
skipped CameraX too because selecting a physical sub-camera through it is exactly the
layer that fails.
**Reverses if:** On-device testing shows Camera2 also cannot get a live ultrawide
preview (then the lens may only be reachable as a physical sub-camera of logical "0",
or not at all outside the stock app).

## D2 — De-risk the camera FIRST, before any app flow
**Decision:** Build only a camera **probe** screen first; gate on real-device
verification that we reach the 0.5x ultrawide and decode a QR; only then build the rest.
**Why:** The camera is the one make-or-break risk and the entire point of the app.
Building flow on top of an unproven camera (the original "Dart-first scaffold" idea)
risks throwing it all away. Everything above the camera is device-independent.
**Reverses if:** Never, really — this is the cheap path.

## D3 — Scan → Verify sheet → confirm → pay (never auto-launch)
**Decision:** Decoding a QR opens a Verify sheet (payee, raw VPA, safety shield, amount
pad, app choice). The `upi://pay` intent only fires on explicit confirm.
**Why:** Security + UX. Auto-firing on decode sends real money to whoever a wrong/
malicious QR names, with no review; and since most QRs are open-amount, an in-app amount
pad pre-fills the pay app (fewer taps). One convergence point for all entry paths
(scan, share/paste, favorite) = one place to enforce validation.
**Reverses if:** User explicitly wants zero-confirm speed for trusted fixed-amount QRs
(was offered "Smart auto" and chose the always-verify sheet).

## D4 — Security has teeth, and the app makes ZERO network calls
**Decision:** Strict UPI validation in one place (`upi_validator.dart`): block
`upi://collect`/mandate (money pulled FROM the user), validate VPA + amount + currency,
always show the raw VPA (monospace) so a spoofed display name can't hide the payee,
large-amount guard (default ₹5000). No HTTP client, no analytics — nothing leaves the
device.
**Why:** It touches money. "Secure" was a stated top pillar.

## D5 — Deferred features (architecture leaves room, not built)
Biometric app-lock, one-tap re-pay from history, home-screen/quick-tile launcher.
**Why:** User reviewed the feature menu and did not select these for the MVP. Keeping
scope tight (YAGNI). Favorites/Quick-Pay, in-app amount pad, and share/paste-in ARE in.

## D6 — Beep on lock defaults OFF
User preference. Haptic on lock stays; sound is an opt-in toggle in settings.

## D7 — Plain state management
`setState` / light `ChangeNotifier`. No Provider/Riverpod/Bloc/DI. Scope is small and
the camera is the only complex stateful piece.

## D8 — Local-only persistence via shared_preferences
Favorites + scan history (JSON, history capped at 200) + settings. Wrapped in repo
classes so a real DB can swap in later. No backend, no accounts.

## D9 — History is a scan log, not a payment ledger (honesty)
The OS never reports payment success, so "paid" is a manual mark and spend totals are
labeled partial. UI copy must never imply confirmed payments. Non-negotiable.

## D10 — Pay from the EXACT scanned QR, never a rebuilt one
**Decision:** The launcher fires the original scanned `upi://pay` string verbatim
(`UpiRequest.raw`). For a fixed-amount QR we pass it through byte-for-byte; for an
open-amount QR we keep every original parameter and only inject `am` (+ `cu` if
absent). We do **not** reconstruct the URI from the parsed display fields.
**Why:** A real UPI scanner transmits the whole QR. The first cut rebuilt the URI
from 7 parsed fields, which dropped the merchant signature (`sign`), `mode`, `orgid`,
and re-encoded the VPA's `@` to `%40`. On-device this made verified-merchant payments
fail at PIN entry with *"receiver not accepting payments"* while the same QR worked in
other apps — the dropped `sign`/`mode` is what the payee bank validates. Parsed fields
stay for display/validation only.
**Reverses if:** Never for the signature — it must survive. Amount injection for
open-amount QRs is the only mutation allowed.

## D11 — History rows: explicit Paid toggle + delete, not whole-row tap
**Decision:** Each scan row has a labelled **Mark paid / Paid** pill and a **delete**
button (delete is undoable via a snackbar). The whole-row-tap-to-toggle is gone.
**Why:** Two on-device bugs. (1) `_reload()` passed an arrow closure to `setState`
that returned a `Future`; `setState` rejects that, so the rebuild aborted and taps
appeared dead. (2) The only feedback was a 10px mist→lime text flip — invisible. An
explicit control with clear state + haptic fixes both, and delete lets the user clear
failed/abandoned scans. Still a scan log, not a ledger (D9 holds).

## D12 — P2P payments go through a re-encoded QR image, not the intent
**Decision:** For person-to-person (personal VPA) payments, ScanPay re-encodes the
payment string (`buildUpiUri`, D10) into a fresh **QR image** and hands it to a UPI
app's **gallery-scan / share** flow (Save to gallery + Share). The `upi://pay` intent
("Pay" button) stays for **merchant** QRs. Image buttons hard-block over ₹2,000.
**Why:** Confirmed on-device (S21 FE) that UPI apps **wall off externally-initiated
`upi://pay` intents for P2P**. PhonePe blocks every external P2P intent ("₹2,000 via
gallery" sheet, won't proceed) regardless of amount, even a clean adb-fired URI;
WhatsApp's external receiver returns "Invalid UPI ID" with no debit — yet its in-app
"Pay with UPI" paid the *same* VPA. So the VPA is valid; the external-intent path is
the wall (NPCI anti-fraud). This user can't fall back to the apps' own scanners (dead
main lens), and the only P2P path seen to complete is feeding the QR as an image to a
gallery/image flow (PhonePe gallery ≤₹2,000; WhatsApp image worked). The earlier
"informational, just dismiss" read (continue.md bug #2) was wrong.
**Reverses if:** UPI apps later accept external P2P intents again, or a tested app
honours them — then a chooser to that app replaces the image dance. The ₹2,000 cap and
honesty copy (D9) stay regardless.

## Package / identifier facts
- Dart package name: `scanpay` (imports are `package:scanpay/...`).
- Android applicationId + Kotlin package: `com.scanpay.scanpay` (generated by
  `flutter create --org com.scanpay --project-name scanpay`; the plan's `com.scanpay.app`
  was a placeholder — real path is `.../kotlin/com/scanpay/scanpay/`).
- minSdk 24, ML Kit `com.google.mlkit:barcode-scanning:17.3.0`.
- Plugins: `android_intent_plus`, `image_picker`, `shared_preferences`,
  `permission_handler`.
