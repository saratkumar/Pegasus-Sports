import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'config_service.dart';

class PaymentService {
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
      ),
    );

    // Throws StripeException with code Canceled if user dismisses
    await Stripe.instance.presentPaymentSheet();

    // Extract PI ID from client secret: "pi_xxx_secret_yyy" → "pi_xxx"
    return clientSecret.split('_secret_').first;
  }
}
