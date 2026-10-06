import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/crash_log.dart';

class PaymentService {
  // Cloud Functions are deployed to asia-southeast1 (see functions/index.js
  // setGlobalOptions) — the default FirebaseFunctions.instance targets
  // us-central1 and would silently fail to find any of these functions.
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static String? _appliedKey;

  /// Initializes the Stripe SDK on first use instead of at app startup, so
  /// clients who never open the payment flow don't pay its memory/CPU cost.
  /// [publishableKey] comes from the server (createPaymentIntent returns the
  /// STRIPE_PUBLISHABLE_KEY secret) rather than being compiled in, so it
  /// always matches the server's secret key and switching Stripe between
  /// test and live needs no app release. Re-applied only if it changed.
  static Future<void> _ensureInitialized(String publishableKey) async {
    if (_appliedKey == publishableKey) return;
    crashLog('processPayment: applying Stripe settings');
    Stripe.publishableKey = publishableKey;
    await Stripe.instance.applySettings().timeout(const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException(
            'Stripe.applySettings did not complete within 10s'));
    _appliedKey = publishableKey;
  }

  /// Creates the PaymentIntent server-side (via the `createPaymentIntent`
  /// Cloud Function — the Stripe secret key never touches the client) →
  /// shows the payment sheet to the user.
  ///
  /// [netAmount] is the amount the business should actually receive (after
  /// any coupon discount, before the Stripe card fee); the server grosses it
  /// up by the fee for [cardRegion]/[cardBrand] (self-declared by the
  /// customer — see stripe_fee_estimator.dart) and charges that instead, so
  /// [netAmount] still lands in full after Stripe takes its cut.
  ///
  /// Throws [StripeException] if user cancels.
  /// Throws on network/Cloud Function errors.
  /// Returns the PaymentIntent ID plus the server-computed, authoritative
  /// net/fee/gross breakdown (fee math is never trusted from the client).
  static Future<
      ({
        String paymentIntentId,
        double netAmount,
        double feeAmount,
        double grossAmount
      })> processPayment({
    required BuildContext context,
    required String planName,
    required double netAmount,
    required String currency,
    required String cardRegion,
    required String cardBrand,
  }) async {
    // The PaymentSheet below is mobile-only (flutter_stripe has no web
    // implementation of it) — the web shop pays via Stripe Checkout.
    if (kIsWeb) {
      return _processCheckout(context,
          planName: planName,
          netAmount: netAmount,
          currency: currency,
          cardRegion: cardRegion,
          cardBrand: cardBrand);
    }
    // Breadcrumbs, not error reports — the known failure mode here (see
    // memberships_screen.dart's _confirm()) is the Stripe sheet silently
    // never appearing, with no exception thrown at all, so there's nothing
    // for Crashlytics to catch on its own. These persist across app
    // restarts and get attached to the next thing that IS reported, so if
    // a user hits the hang and force-quits, the timeouts below (or
    // whatever they trigger next) will show exactly which step it stuck
    // on instead of just "payment failed" with no context.
    crashLog('processPayment: calling createPaymentIntent');
    final result = await _functions
        .httpsCallable('createPaymentIntent')
        .call({
          'netAmount': netAmount,
          'currency': currency,
          'planName': planName,
          'cardRegion': cardRegion,
          'cardBrand': cardBrand,
        })
        .timeout(const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException(
                'createPaymentIntent did not respond within 20s'));
    final data = result.data as Map;
    final clientSecret = data['clientSecret'] as String;
    final paymentIntentId = data['paymentIntentId'] as String;
    final serverNetAmount = (data['netAmount'] as num).toDouble();
    final feeAmount = (data['feeAmount'] as num).toDouble();
    final grossAmount = (data['grossAmount'] as num).toDouble();
    final publishableKey = data['publishableKey'] as String?;
    if (publishableKey == null || publishableKey.isEmpty) {
      throw StateError(
          'Payments are not configured (missing Stripe publishable key)');
    }
    await _ensureInitialized(publishableKey);

    crashLog('processPayment: initializing payment sheet');
    await Stripe.instance
        .initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: clientSecret,
            merchantDisplayName: 'PSAS',
            // Deliberately omitted. This is normally required for
            // redirect-based payment methods (PayNow and other automatic_
            // payment_methods surfaced for SG, see functions/index.js
            // createPaymentIntent) so the SDK can detect the user returning
            // to the app after paying elsewhere (bank app/QR/Safari) — but
            // setting it is a known unresolved flutter_stripe/Stripe-iOS bug
            // that makes presentPaymentSheet() hang/crash specifically on
            // TestFlight-distributed builds (works fine in local debug/
            // release): https://github.com/flutter-stripe/flutter_stripe/issues/1605
            // https://github.com/flutter-stripe/flutter_stripe/issues/1689
            // Without a returnURL, Stripe's PaymentSheet automatically hides
            // payment methods that require a redirect (e.g. PayNow), so only
            // card is offered — a worthwhile trade until upstream is fixed,
            // since redirect methods can't complete on TestFlight anyway.
            style: ThemeMode.light,
            appearance: const PaymentSheetAppearance(
              colors: PaymentSheetAppearanceColors(
                primary: Color(0xFFFF7A00),
              ),
            ),
            // PayNow (and other SG-local payment methods surfaced via
            // automatic_payment_methods) requires a Singapore billing
            // address — all customers are local, so prefill it instead of
            // asking.
            billingDetails: const BillingDetails(
              address: Address(
                city: null,
                country: 'SG',
                line1: null,
                line2: null,
                postalCode: null,
                state: null,
              ),
            ),
          ),
        )
        .timeout(const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException(
                'initPaymentSheet did not complete within 15s — the Stripe '
                'sheet likely never appeared'));

    crashLog('processPayment: presenting payment sheet');
    // This is the call that actually renders the sheet — a bounded but
    // generous timeout rather than none, since a real user filling in card
    // details can legitimately take a couple minutes. Previously unbounded,
    // which meant if the native call to show the sheet itself silently
    // failed (nothing ever rendered), the app would hang forever with no
    // way to ever recover or report it. Any timeout here is strictly safer
    // than none for that case.
    // Throws StripeException with code Canceled if user dismisses.
    await Stripe.instance.presentPaymentSheet().timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw TimeoutException(
            'presentPaymentSheet did not complete within 3 minutes — the '
            'Stripe sheet may never have rendered'));
    crashLog('processPayment: payment sheet completed');

    return (
      paymentIntentId: paymentIntentId,
      netAmount: serverNetAmount,
      feeAmount: feeAmount,
      grossAmount: grossAmount,
    );
  }

  /// Web equivalent of [processPayment]: creates a Stripe Checkout session
  /// server-side (same validation/fee math as createPaymentIntent), opens
  /// Stripe's hosted payment page in a new tab — Checkout won't render
  /// inside the iframe the shop is embedded in — and polls until it's paid.
  /// Returns the same record as the mobile flow, so the caller's
  /// confirm/invoice steps are shared. Cancelling throws the same
  /// [FailureCode.Canceled] [StripeException] the PaymentSheet does.
  static Future<
      ({
        String paymentIntentId,
        double netAmount,
        double feeAmount,
        double grossAmount
      })> _processCheckout(
    BuildContext context, {
    required String planName,
    required double netAmount,
    required String currency,
    required String cardRegion,
    required String cardBrand,
  }) async {
    final result = await _functions
        .httpsCallable('createCheckoutSession')
        .call({
          'netAmount': netAmount,
          'currency': currency,
          'planName': planName,
          'cardRegion': cardRegion,
          'cardBrand': cardBrand,
        })
        .timeout(const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException(
                'createCheckoutSession did not respond within 20s'));
    final data = result.data as Map;
    final grossAmount = (data['grossAmount'] as num).toDouble();

    if (!context.mounted) {
      throw StateError('Checkout was interrupted');
    }
    final paymentIntentId = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CheckoutDialog(
        url: data['url'] as String,
        sessionId: data['sessionId'] as String,
        grossAmount: grossAmount,
      ),
    );
    if (paymentIntentId == null) {
      throw const StripeException(
        error: LocalizedErrorMessage(
            code: FailureCode.Canceled, message: 'Checkout cancelled'),
      );
    }
    return (
      paymentIntentId: paymentIntentId,
      netAmount: (data['netAmount'] as num).toDouble(),
      feeAmount: (data['feeAmount'] as num).toDouble(),
      grossAmount: grossAmount,
    );
  }

  /// Overwrites the PaymentIntent's description (initially set to the plan
  /// name at creation, before the invoice number exists) so the Stripe
  /// Dashboard shows the invoice number instead. Best-effort — the invoice
  /// itself is already recorded in Firestore regardless of this call.
  static Future<void> setInvoiceDescription(
      String paymentIntentId, String invoiceNumber) async {
    await _functions.httpsCallable('updatePaymentDescription').call({
      'paymentIntentId': paymentIntentId,
      'description': invoiceNumber,
    });
  }

  /// Verifies the payment succeeded server-side and activates the
  /// membership — replaces trusting the client's own Firestore write.
  static Future<void> confirmMembershipPayment({
    required String paymentIntentId,
    required String planName,
    required int credits,
    required int validityDays,
  }) async {
    await _functions.httpsCallable('confirmMembershipPayment').call({
      'paymentIntentId': paymentIntentId,
      'planName': planName,
      'credits': credits,
      'validityDays': validityDays,
    });
  }

  /// Validates and redeems a 100%-off coupon server-side, then activates
  /// the membership — replaces trusting the client's own coupon validation.
  static Future<void> redeemFreeMembership({
    required String planName,
    required int credits,
    required int validityDays,
    required String couponCode,
  }) async {
    await _functions.httpsCallable('redeemFreeMembership').call({
      'planName': planName,
      'credits': credits,
      'validityDays': validityDays,
      'couponCode': couponCode,
    });
  }
}

/// "Pay securely" dialog for web Checkout. The Stripe page is opened from a
/// button tap (not automatically) so browsers treat the new tab as
/// user-initiated rather than a blocked pop-up. Polls the session every 3s
/// and pops with the PaymentIntent id once paid, or null if cancelled or
/// the session expired.
class _CheckoutDialog extends StatefulWidget {
  final String url;
  final String sessionId;
  final double grossAmount;
  const _CheckoutDialog({
    required this.url,
    required this.sessionId,
    required this.grossAmount,
  });

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  Timer? _poll;
  bool _opened = false;
  bool _checking = false;
  String? _notice;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    await launchUrl(Uri.parse(widget.url), webOnlyWindowName: '_blank');
    if (!mounted) return;
    setState(() => _opened = true);
    _poll ??= Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final res = await PaymentService._functions
          .httpsCallable('getCheckoutSession')
          .call({'sessionId': widget.sessionId});
      final d = res.data as Map;
      if (!mounted) return;
      if (d['status'] == 'complete' && d['paymentStatus'] == 'paid') {
        _poll?.cancel();
        Navigator.of(context).pop(d['paymentIntentId'] as String);
      } else if (d['status'] == 'expired') {
        _poll?.cancel();
        setState(() => _notice =
            'This payment page has expired. Please close and try again.');
      }
    } catch (_) {
      // Transient network error — the next tick retries.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pay securely with Stripe'),
      content: Text(_notice ??
          (_opened
              ? 'Complete your payment in the new tab. This window updates '
                  'automatically once the payment goes through.'
              : 'A secure Stripe page will open in a new tab to pay '
                  'SGD ${widget.grossAmount.toStringAsFixed(2)} by card, '
                  'PayNow, Apple Pay or Google Pay.')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_notice == null)
          ElevatedButton(
            onPressed: _open,
            child: Text(_opened ? 'Reopen payment page' : 'Continue to payment'),
          ),
      ],
    );
  }
}
