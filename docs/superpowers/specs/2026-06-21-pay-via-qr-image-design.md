# Design — Pay via QR image (P2P workaround)

> Date: 2026-06-21 · Branch: `feat/scanpay-mvp` · Status: approved, pre-implementation

## Problem

UPI apps reject **externally-initiated `upi://pay` intents for person-to-person
(personal VPA) payments**, while accepting the *same* VPA when it is processed
*inside* the app. Confirmed on the real S21 FE (RZCW40EKBPE):

- **PhonePe** (the device default handler) blocks every external P2P intent with a
  "You can pay up to ₹2,000 with QR codes via gallery" sheet — with an amount,
  without an amount, even a textbook-clean adb-fired URI. It will not proceed.
- **WhatsApp Pay** external receiver (`IndiaUpiPayIntentReceiverActivity`) rejects
  the same intent with **"Invalid UPI ID"** (no debit) — yet its in-app
  **"Pay with UPI"** button (WhatsApp processing the QR image in-chat) **completed
  a ₹5 payment** to the exact same VPA `aaryakhodke11@oksbi`.
- This proves the VPA is valid; the rejection is about the **external-intent path**,
  not the payee. It is an NPCI anti-fraud wall, not a ScanPay bug. Merchant QRs
  (signed, `mc`/`orgid`) are exempt and still pay fine via intent.

Because this user's **main rear lens is dead**, they also cannot use the UPI apps'
own in-app scanners — which is the entire reason ScanPay exists. The only P2P path
seen to complete is feeding the QR as an **image** to a UPI app's gallery/image flow
(PhonePe's gallery path explicitly allows ≤ ₹2,000; WhatsApp's image detection worked).

## Goal

Let a friend (P2P) payment complete despite the intent wall, by turning the scanned
payment into a **freshly re-encoded QR image** that the user hands to a UPI app's
gallery/image path. Keep the existing intent "Pay" for merchants (it works).

Non-goals: bypassing the UPI apps' ₹2,000 gallery cap; making the external intent
itself work for P2P (not possible); any network call (zero-network holds).

## Flow

Scan → Verify sheet (unchanged: raw VPA, safety shield, amount pad) → **two pay
paths, both always shown**:

1. **Pay** — existing `upi://pay` intent (`launchUpiUri`). Works for merchants.
2. **Pay via QR image** — new section with **Save QR to gallery** and **Share QR**.

The handed-off image is a **fresh QR re-encoded from the exact payment string**
`buildUpiUri(req, amount)` (the existing, D10-correct builder — passes signed QRs
byte-for-byte, injects `am` for open-amount). Not the blurry ultrawide frame:
re-encoding is crisp, guaranteed scannable, and carries the entered amount.

After saving/sharing, the user opens their UPI app's **scan-from-gallery** (PhonePe /
GPay / Paytm) or shares to WhatsApp, picks the QR, and completes with their PIN.

## Components

- **`lib/pay/gallery_cap.dart`** — pure Dart: `galleryCapExceeded(double amount) ->
  bool`, cap `₹2,000`. **Unit-tested** (TDD).
- **`lib/pay/qr_image.dart`** — platform/IO glue (device-verified, like the camera):
  - `Future<Uint8List> renderUpiQrPng(String upiUri)` — `qr_flutter`
    `QrPainter(...).toImageData()`.
  - `Future<void> saveQrToGallery(Uint8List png, {String filename})` — `gal`
    (Android 10+ scoped-storage friendly).
  - `Future<void> shareQr(Uint8List png, {String text})` — write to temp/cache file,
    `share_plus` `SharePlus.instance.share(...)` with an `XFile`.
- **`lib/pay/verify_sheet.dart`** — add the image-pay section below the existing Pay
  button: two buttons, a cap note, hard-block over cap, and history logging.

## Cap handling (hard-block over ₹2,000)

- Always show a small note: *"Gallery/image payments are capped at ₹2,000 by UPI apps."*
- When `galleryCapExceeded(amount)` is true, **disable both image buttons** with copy:
  *"Over ₹2,000 — use the Pay button or lower the amount."* The intent **Pay** button
  stays enabled (its own ₹5,000 large-amount guard is unchanged).
- For an open-amount QR with no amount entered yet (`amount == 0`), image buttons are
  disabled (nothing to encode) — same as the existing Pay button.

## History

Saving or sharing the QR logs the same `ScanEntry` the intent path logs (vpa, name,
amount, category, time, note) so the attempt appears in the scan log. Still a scan
log, not a payment ledger (D9) — no success is implied; the user marks "paid"
manually as today.

## Error handling

- Gallery-permission denial → amber snackbar, no crash.
- QR render failure → amber snackbar.
- Share dismissed/cancelled → no-op.

## New dependencies (all offline — zero-network holds)

`qr_flutter`, `gal`, `share_plus`. None makes network calls; QR rendering is pure
local painting, gallery save is MediaStore, share is the system share sheet.

## Testing

- **Unit (TDD):** `galleryCapExceeded` (boundary at exactly 2000, over, under, zero).
  `buildUpiUri` already covered.
- **Device-verified (can't unit-test plugins/IO here):** QR renders, saves to gallery,
  shares; and the make-or-break — a real payment completes.

## De-risk gate (build this FIRST, per project workflow)

Before any Verify-sheet polish, build the **minimum**: generate a QR from
`buildUpiUri` and save/share it. Then on the S21 FE verify a real **₹10 to the
friend completes** via PhonePe gallery-scan and/or WhatsApp image. **Only if that
passes** do we wire the polished two-button section, cap copy, and history logging.
If the gallery path also won't complete a P2P payment, stop and rethink — do not
invest in UI.

## Risks / watch-items

- PhonePe gallery-scan may still add friction even ≤ ₹2,000 (the cap sheet *says* it
  is allowed; WhatsApp image path is the proven fallback). The de-risk gate catches
  this before UI work.
- `gal` requires `READ/WRITE` media handling on older Android; minSdk 24. Verify the
  save works without a permission dead-end; fall back to share-only if gallery save
  is unreliable.
- Re-encoded QR must round-trip the signed merchant string unchanged if ever used for
  a merchant QR (it will, since it encodes the same `buildUpiUri` output) — but image
  path is aimed at P2P; merchants keep using intent.
