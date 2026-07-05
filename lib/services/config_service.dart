import 'dart:convert';
import 'package:http/http.dart' as http;

class ConfigService {
  // After deploying your Apps Script, paste the /exec URL here.
  // Apps Script → Deploy → New deployment → Web app → Execute as Me → Anyone → Deploy
  static const _scriptUrl = 'https://script.google.com/macros/s/AKfycbw2X5iVPGyTJTsV-e3epeOjeIMztjo5s1ZcVWWWqiEQqhz6znHVv_-4wN0kykQl4Adg/exec';

  static Map<String, String>? _cache;

  static Future<Map<String, String>> _fetch() async {
    if (_cache != null) return _cache!;
    final response = await http
        .get(Uri.parse(_scriptUrl))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Config fetch failed: ${response.statusCode}');
    }
    final raw = jsonDecode(response.body) as Map<String, dynamic>;
    _cache = raw.map((k, v) => MapEntry(k, v.toString()));
    return _cache!;
  }

  static Future<String> get(String key) async {
    final config = await _fetch();
    final value = config[key];
    if (value == null || value.isEmpty) {
      throw Exception('Config key "$key" not found in Google Sheet');
    }
    return value;
  }

  static void clearCache() => _cache = null;

  /// Records a transaction row to the Transactions sheet via the same Apps Script.
  static Future<void> recordTransaction({
    required String invoiceNumber,
    required String paymentIntentId,
    required String clientName,
    required String clientEmail,
    required String planName,
    required int credits,
    required double amount,
    required String currency,
    required String date,
  }) async {
    final uri = Uri.parse(_scriptUrl).replace(queryParameters: {
      'action': 'record_transaction',
      'invoiceNumber': invoiceNumber,
      'txId': paymentIntentId,
      'clientName': clientName,
      'clientEmail': clientEmail,
      'planName': planName,
      'credits': credits.toString(),
      'amount': amount.toStringAsFixed(2),
      'currency': currency,
      'date': date,
    });
    await http.get(uri).timeout(const Duration(seconds: 10));
  }
}
