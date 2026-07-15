import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'config_service.dart';

class PaymentService {
  // Safe to include in client code. Swap pk_test_ → pk_live_ for production.
  // Get yours from: https://dashboard.stripe.com/test/apikeys
  static const _publishableKey =
      'pk_test_51Tps5X5GDQ6NbhM7JIa90Yh2ce52faber57nbE9GJB4kZFS7QpxjF4nWO0RxNmWcs8kPNWAFX4vG2WcGKt5irYzu00nf4mQiQu';

  static bool _initialized = false;

  /// Initializes the Stripe SDK on first use instead of at app startup, so
  /// clients who never open the payment flow don't pay its memory/CPU cost.
  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    Stripe.publishableKey = _publishableKey;
    await Stripe.instance.applySettings();
    _initialized = true;
  }

  /// Fetches Stripe secret key from Google Sheet → creates PaymentIntent via
  /// Stripe REST API → shows payment sheet to user.
  ///
  /// Throws [StripeException] if user cancels.
  /// Throws [Exception] on network or Stripe API errors.
  /// Returns the Stripe PaymentIntent ID (pi_xxx) on success.
  static Future<String> processPayment({
    required String planName,
    required double amount,
    required String currency,
  }) async {
    await _ensureInitialized();
    final secretKey = await ConfigService.get('stripe_secret_key');

    final response = await http.post(
      Uri.parse('https://api.stripe.com/v1/payment_intents'),
      headers: {
        'Authorization': 'Bearer $secretKey',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: 'amount=${(amount * 100).round()}'
          '&currency=$currency'
          '&automatic_payment_methods[enabled]=true'
          '&description=${Uri.encodeComponent(planName)}',
    );

    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error']?['message'] ?? 'Failed to create payment');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final clientSecret = data['client_secret'] as String;

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'PSAS',
        style: ThemeMode.light,
        appearance: const PaymentSheetAppearance(
          colors: PaymentSheetAppearanceColors(
            primary: Color(0xFFFF7A00),
          ),
        ),
        // PayNow (and other SG-local payment methods surfaced via
        // automatic_payment_methods) requires a Singapore billing address —
        // all customers are local, so prefill it instead of asking.
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
    );

    // Throws StripeException with code Canceled if user dismisses
    await Stripe.instance.presentPaymentSheet();

    // Extract PI ID from client secret: "pi_xxx_secret_yyy" → "pi_xxx"
    return clientSecret.split('_secret_').first;
  }

  /// Overwrites the PaymentIntent's description (initially set to the plan
  /// name at creation, before the invoice number exists) so the Stripe
  /// Dashboard shows the invoice number instead. Best-effort — the invoice
  /// itself is already recorded in Firestore regardless of this call.
  static Future<void> setInvoiceDescription(
      String paymentIntentId, String invoiceNumber) async {
    final secretKey = await ConfigService.get('stripe_secret_key');
    await http.post(
      Uri.parse('https://api.stripe.com/v1/payment_intents/$paymentIntentId'),
      headers: {
        'Authorization': 'Bearer $secretKey',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: 'description=${Uri.encodeComponent(invoiceNumber)}',
    );
  }
}
