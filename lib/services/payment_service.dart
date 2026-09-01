import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

class PaymentService {
  // Safe to include in client code. Swap pk_test_ → pk_live_ for production.
  // Get yours from: https://dashboard.stripe.com/test/apikeys
  static const _publishableKey =
      'pk_test_51Tps5X5GDQ6NbhM7JIa90Yh2ce52faber57nbE9GJB4kZFS7QpxjF4nWO0RxNmWcs8kPNWAFX4vG2WcGKt5irYzu00nf4mQiQu';

  // Cloud Functions are deployed to asia-southeast1 (see functions/index.js
  // setGlobalOptions) — the default FirebaseFunctions.instance targets
  // us-central1 and would silently fail to find any of these functions.
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static bool _initialized = false;

  /// Initializes the Stripe SDK on first use instead of at app startup, so
  /// clients who never open the payment flow don't pay its memory/CPU cost.
  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    FirebaseCrashlytics.instance.log('processPayment: applying Stripe settings');
    Stripe.publishableKey = _publishableKey;
    await Stripe.instance.applySettings().timeout(const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException(
            'Stripe.applySettings did not complete within 10s'));
    _initialized = true;
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
    required String planName,
    required double netAmount,
    required String currency,
    required String cardRegion,
    required String cardBrand,
  }) async {
    await _ensureInitialized();

    // Breadcrumbs, not error reports — the known failure mode here (see
    // memberships_screen.dart's _confirm()) is the Stripe sheet silently
    // never appearing, with no exception thrown at all, so there's nothing
    // for Crashlytics to catch on its own. These persist across app
    // restarts and get attached to the next thing that IS reported, so if
    // a user hits the hang and force-quits, the timeouts below (or
    // whatever they trigger next) will show exactly which step it stuck
    // on instead of just "payment failed" with no context.
    FirebaseCrashlytics.instance.log('processPayment: calling createPaymentIntent');
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

    FirebaseCrashlytics.instance.log('processPayment: initializing payment sheet');
    await Stripe.instance
        .initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: clientSecret,
            merchantDisplayName: 'PSAS',
            // Required for redirect-based payment methods (PayNow and other
            // automatic_payment_methods surfaced for SG, see functions/
            // index.js createPaymentIntent) — without it, the SDK has no way
            // to detect the user returned to the app after completing
            // payment elsewhere (bank app/QR/Safari), and
            // presentPaymentSheet() hangs indefinitely even though the
            // payment itself succeeded. Must match the CFBundleURLSchemes
            // entry in ios/Runner/Info.plist.
            returnURL: 'psasbooking-stripe://stripe-redirect',
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

    FirebaseCrashlytics.instance.log('processPayment: presenting payment sheet');
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
    FirebaseCrashlytics.instance.log('processPayment: payment sheet completed');

    return (
      paymentIntentId: paymentIntentId,
      netAmount: serverNetAmount,
      feeAmount: feeAmount,
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
