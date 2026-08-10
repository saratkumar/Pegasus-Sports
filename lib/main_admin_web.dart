import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'web_admin/admin_web_app.dart';

// Trimmed mirror of main.dart's startup sequence for the desktop admin
// panel: Firebase init only — NotificationService.initialize() is
// mobile-only and irrelevant here, and DeepLinkService is wired into
// FitnessBookingApp's widget tree, which this entrypoint never builds.
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    String? startupError;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      startupError = 'Firebase.initializeApp failed:\n$e';
    }
    runApp(startupError == null
        ? const AdminWebApp()
        : _StartupErrorApp(message: startupError));
  }, (error, stack) {
    runApp(_StartupErrorApp(message: 'Uncaught error:\n$error\n\n$stack'));
  });
}

class _StartupErrorApp extends StatelessWidget {
  final String message;
  const _StartupErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Text(
                message,
                style: const TextStyle(color: Colors.red, fontSize: 13, fontFamily: 'monospace'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
