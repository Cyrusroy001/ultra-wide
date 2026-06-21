/// UPI apps cap QR-via-gallery / image payments at ₹2,000 (confirmed on-device:
/// PhonePe's "pay up to ₹2,000 with QR codes via gallery"). The image-pay path
/// is hard-blocked above this; the intent "Pay" path is not. See D12.
const double galleryCap = 2000.0;

/// True when [amount] is above the ₹2,000 gallery/image cap. Exactly 2000 is OK.
bool galleryCapExceeded(double amount) => amount > galleryCap;
