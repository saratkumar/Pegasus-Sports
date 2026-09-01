/// Client-side preview only, shown before payment — the actual charge is
/// always computed and enforced server-side in functions/index.js
/// (createPaymentIntent). This exists purely so the checkout sheet can show
/// the customer the fee/total before they tap "Confirm & Pay".
///
/// MIRRORS functions/index.js CARD_FEE_TIERS/computeCardFee — keep the rates
/// and formula identical, or this preview will drift from what the customer
/// is actually charged.
const _cardFeeTiers = {
  'domestic': {
    'visa_mc': (percent: 0.034, fixed: 0.50),
    'amex': (percent: 0.034, fixed: 0.50),
  },
  'international': {
    'visa_mc': (percent: 0.044, fixed: 0.50),
    'amex': (percent: 0.044, fixed: 0.50),
  },
};

({double feeAmount, double grossAmount}) estimateCardFee({
  required double netAmount,
  required String cardRegion,
  required String cardBrand,
}) {
  final tier = _cardFeeTiers[cardRegion]?[cardBrand];
  if (tier == null) {
    throw ArgumentError('Unknown card tier: $cardRegion/$cardBrand');
  }
  final rawGross = (netAmount + tier.fixed) / (1 - tier.percent);
  final grossAmount = (rawGross * 100).ceilToDouble() / 100;
  final feeAmount = ((grossAmount - netAmount) * 100).roundToDouble() / 100;
  return (feeAmount: feeAmount, grossAmount: grossAmount);
}
