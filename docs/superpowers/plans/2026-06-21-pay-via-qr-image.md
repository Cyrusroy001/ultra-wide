# Pay via QR image (P2P workaround) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let person-to-person UPI payments complete by re-encoding the scanned payment into a fresh QR image the user hands to a UPI app's gallery/share flow, since UPI apps wall off external `upi://pay` intents for P2P.

**Architecture:** A pure cap-check (`gallery_cap.dart`) and an IO module (`qr_image.dart`: render QR → PNG, save to gallery, share) are added. `VerifySheet` gains a second pay path — **Save QR** / **Share QR** buttons (always shown, hard-disabled over ₹2,000) that call injected callbacks. `ScanScreen` wires those callbacks to `qr_image` + history logging. The intent "Pay" button is untouched (merchants still work).

**Tech Stack:** Flutter/Dart; `qr_flutter` (offline QR render), `gal` (gallery save), `share_plus` + `path_provider` (share a temp PNG). Reuses `buildUpiUri` (D10) and `ScanEntry`.

## Global Constraints

- **Zero network** — no HTTP/analytics; every new dep is offline-only (D4). Verbatim non-negotiable.
- **Never auto-fire a payment** — image path also requires an explicit button tap; no auto-launch (D3/D4).
- **Honesty copy (D9)** — history stays a scan log; nothing implies the payment succeeded. The ₹2,000 cap note is required copy.
- **Hard-block over ₹2,000** on the image path (buttons disabled); intent "Pay" stays enabled with its existing ₹5,000 guard.
- **Reuse `buildUpiUri` (D10)** — never rebuild a pay URI from parsed fields. Pass `amount: null` for fixed-amount QRs, the entered amount for open ones.
- **Theme tokens only** — `AppTokens.*`; never hard-code colors. Monospace (`AppTokens.mono`) for VPA/amounts.
- **Dart package `scanpay`** — imports are `package:scanpay/...`.
- **Toolchain** — Flutter 3.44+, Dart 3.12+, minSdk 24. Run `flutter`/build commands in the **foreground PowerShell** shell (background shells lack the user PATH).
- **Image-pay buttons are `OutlinedButton`** (not `FilledButton`) so existing `find.byType(FilledButton)` tests stay valid.

---

### Task 1: Gallery cap (pure logic)

**Files:**
- Create: `lib/pay/gallery_cap.dart`
- Test: `test/pay/gallery_cap_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `const double galleryCap = 2000.0;` and `bool galleryCapExceeded(double amount)` — true when `amount > 2000`.

- [ ] **Step 1: Write the failing test**

```dart
// test/pay/gallery_cap_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:scanpay/pay/gallery_cap.dart';

void main() {
  group('galleryCapExceeded (UPI gallery/image path caps at ₹2,000)', () {
    test('under the cap is allowed', () {
      expect(galleryCapExceeded(10), isFalse);
      expect(galleryCapExceeded(1999.99), isFalse);
    });
    test('exactly ₹2,000 is allowed (boundary)', () {
      expect(galleryCapExceeded(2000), isFalse);
    });
    test('over ₹2,000 is blocked', () {
      expect(galleryCapExceeded(2000.01), isTrue);
      expect(galleryCapExceeded(5000), isTrue);
    });
    test('zero is not "exceeded" (separate empty-amount guard handles it)', () {
      expect(galleryCapExceeded(0), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/pay/gallery_cap_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'scanpay' ... gallery_cap.dart` / "galleryCapExceeded isn't defined".

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/pay/gallery_cap.dart

/// UPI apps cap QR-via-gallery / image payments at ₹2,000 (confirmed on-device:
/// PhonePe's "pay up to ₹2,000 with QR codes via gallery"). The image-pay path
/// is hard-blocked above this; the intent "Pay" path is not. See D12.
const double galleryCap = 2000.0;

/// True when [amount] is above the ₹2,000 gallery/image cap. Exactly 2000 is OK.
bool galleryCapExceeded(double amount) => amount > galleryCap;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/pay/gallery_cap_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/pay/gallery_cap.dart test/pay/gallery_cap_test.dart
git commit -m "feat(pay): gallery cap check (₹2,000) for the image-pay path"
```

---

### Task 2: QR image IO module (render / save / share)

**Files:**
- Modify: `pubspec.yaml` (via `flutter pub add`)
- Create: `lib/pay/qr_image.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks (takes a ready `upi://` string).
- Produces:
  - `Future<Uint8List> renderUpiQrPng(String upiUri, {double size = 1024, double quietZone = 48})`
  - `Future<void> saveQrToGallery(Uint8List png, {String filename = 'ultrawide_upi_qr'})`
  - `Future<void> shareQr(Uint8List png, {required String text})`

> No unit test: this is plugin/IO + `dart:ui` rendering, not unit-testable in the headless test env (same status as the native camera). It is exercised by the **Task 4 device gate**. Keep this module imported only by `scan_screen.dart` so `VerifySheet` widget tests don't pull in plugins.

- [ ] **Step 1: Add the dependencies (foreground PowerShell)**

Run: `flutter pub add qr_flutter gal share_plus path_provider`
Expected: pubspec updated, `flutter pub get` resolves with no version conflicts. All four are offline (no network at runtime) — zero-network holds.

- [ ] **Step 2: Write the module**

```dart
// lib/pay/qr_image.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Renders [upiUri] to a PNG QR with a WHITE background and a quiet-zone border
/// so any UPI app's gallery scanner can read it. Black modules on white — never
/// transparent (transparent gaps make scanners fail). Pure local rendering,
/// no network.
Future<Uint8List> renderUpiQrPng(
  String upiUri, {
  double size = 1024,
  double quietZone = 48,
}) async {
  final painter = QrPainter(
    data: upiUri,
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square, color: Color(0xFF000000)),
    dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square, color: Color(0xFF000000)),
  );

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
  canvas.drawRect(
      Rect.fromLTWH(0, 0, size, size), Paint()..color = const Color(0xFFFFFFFF));
  canvas.translate(quietZone, quietZone);
  painter.paint(canvas, Size(size - quietZone * 2, size - quietZone * 2));

  final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// Saves [png] to the device gallery (MediaStore). Throws on permission denial;
/// the caller surfaces a snackbar.
Future<void> saveQrToGallery(Uint8List png,
    {String filename = 'ultrawide_upi_qr'}) async {
  await Gal.putImageBytes(png, name: filename);
}

/// Writes [png] to a temp file and opens the system share sheet so the user can
/// send the QR to a UPI app (e.g. WhatsApp). [text] is the accompanying message.
Future<void> shareQr(Uint8List png, {required String text}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/ultrawide_upi_qr.png');
  await file.writeAsBytes(png);
  await SharePlus.instance
      .share(ShareParams(text: text, files: [XFile(file.path)]));
}
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/pay/qr_image.dart`
Expected: "No issues found!" (If `SharePlus.instance`/`ShareParams` is flagged, the resolved `share_plus` is older — switch to `Share.shareXFiles([XFile(file.path)], text: text)` and re-run.)

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/pay/qr_image.dart
git commit -m "feat(pay): qr_image module — render UPI QR PNG, save to gallery, share"
```

---

### Task 3: VerifySheet image-pay section

**Files:**
- Modify: `lib/pay/verify_sheet.dart`
- Test: `test/pay/verify_sheet_test.dart` (add three tests; leave existing three intact)

**Interfaces:**
- Consumes: `galleryCapExceeded` (Task 1); `buildUpiUri` + `ScanEntry` + `categorize` (existing); `OnPay` typedef (existing).
- Produces: `VerifySheet` gains optional `OnPay? onSaveQr` and `OnPay? onShareQr`. When provided, two `OutlinedButton`s labelled **'Save QR'** / **'Share QR'** appear; enabled only when `_amount > 0 && !galleryCapExceeded(_amount)`. Both call the callback with `(buildUpiUri(...), ScanEntry(...))`.

- [ ] **Step 1: Write the failing tests** (append to `test/pay/verify_sheet_test.dart`, inside `main()`)

```dart
  testWidgets('image-pay buttons are disabled until a valid amount is entered',
      (tester) async {
    final verdict = validateUpi('upi://pay?pa=anand@okhdfc&pn=Anand');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VerifySheet(
          verdict: verdict,
          onPay: (_, _) async {},
          onSaveQr: (_, _) async {},
          onShareQr: (_, _) async {},
        ),
      ),
    ));

    OutlinedButton saveBtn() =>
        tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Save QR'));
    expect(saveBtn().onPressed, isNull); // no amount yet

    await tester.tap(find.text('5'));
    await tester.pump();
    expect(saveBtn().onPressed, isNotNull); // ₹5 is valid and under the cap
  });

  testWidgets('over ₹2,000 disables image-pay and warns, intent Pay stays enabled',
      (tester) async {
    final verdict = validateUpi('upi://pay?pa=anand@okhdfc&pn=Anand');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VerifySheet(
          verdict: verdict,
          onPay: (_, _) async {},
          onSaveQr: (_, _) async {},
          onShareQr: (_, _) async {},
        ),
      ),
    ));

    for (final d in ['3', '0', '0', '0']) {
      await tester.tap(find.text(d));
    }
    await tester.pump();

    expect(find.textContaining('Over ₹2,000'), findsOneWidget);
    expect(
        tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Save QR')).onPressed,
        isNull);
    // The intent path is the only FilledButton and must remain usable.
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });

  testWidgets('Save QR calls onSaveQr with the built upi uri and the scan entry',
      (tester) async {
    String? gotUri;
    var gotVpa = '';
    double gotAmount = -1;
    final verdict = validateUpi('upi://pay?pa=anand@okhdfc&pn=Anand');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VerifySheet(
          verdict: verdict,
          onPay: (_, _) async {},
          onSaveQr: (u, e) async {
            gotUri = u;
            gotVpa = e.vpa;
            gotAmount = e.amount;
          },
          onShareQr: (_, _) async {},
        ),
      ),
    ));

    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Save QR'));
    await tester.pump();

    expect(gotUri, contains('pa=anand@okhdfc'));
    expect(gotUri, contains('am=5.00'));
    expect(gotVpa, 'anand@okhdfc');
    expect(gotAmount, 5);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/pay/verify_sheet_test.dart`
Expected: FAIL — `No named parameter with the name 'onSaveQr'` (compile error). The three pre-existing tests are unaffected once it compiles.

- [ ] **Step 3: Add the import and constructor params**

In `lib/pay/verify_sheet.dart`, add the import near the others:

```dart
import 'gallery_cap.dart';
```

Add the two fields to the constructor (after `this.largeAmountThreshold = 5000,`):

```dart
    this.onSaveQr,
    this.onShareQr,
```

And declare them (after `final double largeAmountThreshold;`):

```dart
  /// Optional second pay path: re-encode to a QR image and save / share it,
  /// for P2P payees that reject external upi:// intents. Null → section hidden.
  final OnPay? onSaveQr;
  final OnPay? onShareQr;
```

- [ ] **Step 4: Extract the shared uri+entry builder (DRY) and refactor `_confirmAndPay`**

In `_VerifySheetState`, add this helper:

```dart
  (String, ScanEntry) _uriAndEntry() {
    final req = widget.verdict.request!;
    final uri = buildUpiUri(req, amount: _isFixed ? null : _amount);
    final entry = ScanEntry(
      vpa: req.payeeVpa,
      name: req.payeeName,
      amount: _amount,
      category: categorize(merchantCode: req.merchantCode, payeeName: req.payeeName),
      timeMillis: DateTime.now().millisecondsSinceEpoch,
      note: req.note,
    );
    return (uri, entry);
  }
```

Replace the tail of `_confirmAndPay` (the block that builds `uri`/`entry` and calls `widget.onPay`) with:

```dart
    final (uri, entry) = _uriAndEntry();
    await widget.onPay(uri, entry);
```

- [ ] **Step 5: Add the image-pay section to `build` and its widgets**

In `build`, replace `_payButton(req.payeeName),` with:

```dart
          _payButton(req.payeeName),
          if (widget.onSaveQr != null && widget.onShareQr != null) ...[
            const SizedBox(height: 14),
            _imagePaySection(),
          ],
```

Add these methods to `_VerifySheetState`:

```dart
  Widget _imagePaySection() {
    final overCap = galleryCapExceeded(_amount);
    final ready = _amount > 0 && !overCap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(color: AppTokens.slateSoft, height: 1),
        const SizedBox(height: 12),
        const Text('Paying a person? Pay with a QR image',
            style: TextStyle(
                color: AppTokens.cloud, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(
          overCap
              ? 'Over ₹2,000 — use the Pay button or lower the amount.'
              : 'Gallery/image payments are capped at ₹2,000 by UPI apps.',
          style: TextStyle(
              color: overCap ? AppTokens.amber : AppTokens.mist, fontSize: 11),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    ready ? () => _imagePay(widget.onSaveQr!) : null,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Save QR'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    ready ? () => _imagePay(widget.onShareQr!) : null,
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Share QR'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _imagePay(OnPay action) async {
    final (uri, entry) = _uriAndEntry();
    await action(uri, entry);
  }
```

- [ ] **Step 6: Run the full pay test suite**

Run: `flutter test test/pay/`
Expected: PASS — the 3 new VerifySheet tests, the 3 existing VerifySheet tests, plus `launcher`/`upi`/`categories`/`gallery_cap` all green.

- [ ] **Step 7: Commit**

```bash
git add lib/pay/verify_sheet.dart test/pay/verify_sheet_test.dart
git commit -m "feat(pay): VerifySheet 'Save QR'/'Share QR' image-pay path (cap-blocked at ₹2,000)"
```

---

### Task 4: Wire ScanScreen + device gate (de-risk)

**Files:**
- Modify: `lib/scan/scan_screen.dart`

**Interfaces:**
- Consumes: `renderUpiQrPng`, `saveQrToGallery`, `shareQr` (Task 2); `VerifySheet.onSaveQr`/`onShareQr` (Task 3); existing `widget.history`, `_toast`.
- Produces: a fully wired image-pay path on the live scanner. No new public API.

> Glue over plugins → verified on the **physical S21 FE**, not in unit tests. This task is also the **make-or-break gate**: if a real P2P payment won't complete via the gallery/share image even here, STOP and rethink before any further polish (per the spec's de-risk gate).

- [ ] **Step 1: Add the import**

In `lib/scan/scan_screen.dart`, near the other `../pay/...` imports:

```dart
import '../pay/qr_image.dart';
```

- [ ] **Step 2: Add the two handlers** (after `_onPay`)

```dart
  Future<void> _onSaveQr(String uri, ScanEntry entry) async {
    try {
      final png = await renderUpiQrPng(uri);
      await saveQrToGallery(png);
      await widget.history?.add(entry);
      if (!mounted) return;
      Navigator.of(context).maybePop();
      _toast('QR saved to gallery — open your UPI app → Scan → gallery to pay.');
    } catch (_) {
      if (!mounted) return;
      _toast('Could not save the QR image.');
    }
  }

  Future<void> _onShareQr(String uri, ScanEntry entry) async {
    try {
      final png = await renderUpiQrPng(uri);
      await widget.history?.add(entry);
      await shareQr(png, text: 'Pay ${entry.name ?? entry.vpa} via this UPI QR');
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      _toast('Could not share the QR image.');
    }
  }
```

- [ ] **Step 3: Pass the handlers into the sheet**

In `_openSheet`, extend the `VerifySheet(...)` call:

```dart
      builder: (_) => VerifySheet(
        verdict: verdict,
        onPay: _onPay,
        onSaveQr: _onSaveQr,
        onShareQr: _onShareQr,
        largeAmountThreshold: widget.largeAmountThreshold,
      ),
```

- [ ] **Step 4: Static checks + full suite**

Run: `flutter analyze`
Expected: "No issues found!"
Run: `flutter test`
Expected: all green (40 prior + 8 new = 48).

- [ ] **Step 5: Build, install, and run on the S21 FE (foreground PowerShell)**

Run: `flutter devices` (confirm `RZCW40EKBPE`)
Run: `flutter run -d RZCW40EKBPE`

- [ ] **Step 6: DEVICE GATE — verify a real P2P payment completes**

On the phone, scan the friend's QR, enter ₹10, then:
1. **Save QR** → confirm a toast + the QR appears in the gallery. Open PhonePe (or GPay) → Scan → gallery icon → pick the saved QR → confirm it reaches **PIN entry and completes** (≤ ₹2,000).
2. Re-scan, **Share QR** → pick WhatsApp → send to the friend's chat → tap **Pay with UPI** → confirm it **completes**.
3. Enter ₹2,500 → confirm both image buttons are **disabled** with the "Over ₹2,000" warning, while **Pay** stays enabled.

Record the outcome in this checkbox. **If neither save nor share completes a payment, STOP** — do not proceed to Step 7; report back so we can rethink (the gallery path may be more restricted than observed).

- [ ] **Step 7: Commit + update the handoff docs**

Only after the gate passes:

```bash
git add lib/scan/scan_screen.dart
git commit -m "feat(scan): wire Save QR / Share QR image-pay path into the scanner"
```

Then update `continue.md` (top status block) with the gate result — which apps completed the P2P image payment — and mark the pay-via-QR-image feature done.

---

## Self-Review

**Spec coverage:**
- Re-encoded fresh QR (not camera frame) → Task 2 `renderUpiQrPng`. ✓
- Both Save-to-gallery and Share → Task 2 + Task 3 buttons. ✓
- Always show both paths → Task 3 `build` (section rendered whenever callbacks present; production always passes them). ✓
- Hard-block over ₹2,000, intent Pay stays enabled → Task 1 + Task 3 (`ready` gate, FilledButton untouched). ✓
- Honesty copy / cap note → Task 3 copy strings; no success implied (history entry only). ✓
- History logging on image action → Task 4 handlers call `widget.history?.add(entry)`. ✓
- Error handling (gallery denial, render fail, share cancel) → Task 4 try/catch + toast. ✓
- Zero-network deps → Task 2 Step 1 note. ✓
- De-risk gate first → Task 4 Steps 5-6 with STOP condition. ✓
- Reuse `buildUpiUri` (D10) → Task 3 `_uriAndEntry`. ✓

**Placeholder scan:** No TBD/TODO; every code step has full code. ✓

**Type consistency:** `OnPay = Future<void> Function(String, ScanEntry)` used for `onPay`/`onSaveQr`/`onShareQr` and the handlers' signatures match. `renderUpiQrPng`/`saveQrToGallery`/`shareQr` signatures identical across Task 2 (definition), Task 4 (use). `galleryCapExceeded(double)` identical across Task 1/Task 3. `_uriAndEntry()` returns `(String, ScanEntry)` consumed by both `_confirmAndPay` and `_imagePay`. ✓
