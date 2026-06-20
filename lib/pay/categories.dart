enum PayCategory { food, travel, shopping, bills, other }

const _mcc = <PayCategory, Set<String>>{
  PayCategory.food: {'5811', '5812', '5813', '5814'},
  PayCategory.travel: {'4111', '4121', '4131', '4511', '5541', '5542', '7512'},
  PayCategory.shopping: {'5311', '5331', '5399', '5411', '5651'},
  PayCategory.bills: {'4812', '4814', '4900'},
};

const _keywords = <PayCategory, List<String>>{
  PayCategory.food: ['swiggy', 'zomato', 'restaurant', 'cafe', 'food'],
  PayCategory.travel: ['petrol', 'fuel', 'uber', 'ola', 'irctc', 'rail', 'metro'],
  PayCategory.shopping: ['blinkit', 'zepto', 'mart', 'kirana', 'store', 'shop'],
  PayCategory.bills: ['power', 'electric', 'gas', 'recharge', 'dth', 'broadband'],
};

/// Maps a merchant-category-code (ISO 18245) when present, else keyword-matches
/// the payee name, else falls back to [PayCategory.other].
PayCategory categorize({String? merchantCode, String? payeeName}) {
  if (merchantCode != null) {
    for (final e in _mcc.entries) {
      if (e.value.contains(merchantCode)) return e.key;
    }
  }
  if (payeeName != null) {
    final n = payeeName.toLowerCase();
    for (final e in _keywords.entries) {
      if (e.value.any(n.contains)) return e.key;
    }
  }
  return PayCategory.other;
}
