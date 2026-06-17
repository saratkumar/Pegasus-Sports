import 'package:http/http.dart' as http;
import 'dart:convert';

class EmailService {
  static Future<void> sendBookingEmail({
    required String email,
    required String className,
    required String classTime,
  }) async {
    try {
      print('SENDING EMAIL TO: $email FOR CLASS: $className AT $classTime');

      final response = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'service_id': 'service_g0q5hfl',
          'template_id': 'template_2r5pqup',
          'user_id': 'Ort5sgLfVKcJY8t5F',
          'accessToken': 'NvcX-qpDAzBVmKRmnPcIJ',
          'template_params': {
            'name': 'Fitness Booking',
            'email': email,
            'class_name': className,
            'class_time': classTime,
          },
        }),
      );

      print('EMAIL RESPONSE: ${response.statusCode} ${response.body}');
    } catch (e) {
      print('EMAIL ERROR: $e');
    }
  }
}