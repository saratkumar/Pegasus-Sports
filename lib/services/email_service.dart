import 'package:http/http.dart' as http;
import 'dart:convert';

class EmailService {
  static Future<void> sendBookingEmail({
    required String email,
    required String className,
    required String classTime,
  }) async {
    final response = await http.post(
      Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'service_id': 'service_c3f4xqd',
        'template_id': 'template_8ok497i',
        'user_id': 'TJRGXai7XBmcWxZi3',
        'accessToken': 'Xdnxx6kOkdoFnab610h80',
        'template_params': {
          'name': 'Fitness Booking',
          'email': email,
          'class_name': className,
          'class_time': classTime,
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('EmailJS ${response.statusCode}: ${response.body}');
    }
  }
}