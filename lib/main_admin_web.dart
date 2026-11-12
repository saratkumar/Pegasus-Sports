import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'utils/emulator.dart';
import 'web_admin/admin_web_app.dart';

// Trimmed mirror of main.dart's startup sequence for the desktop admin
// panel: Firebase init only — NotificationService.initialize() is
// mobile-only and irrelevant here, and DeepLinkService is wired into
// FitnessBookingApp's widget tree, which this entrypoint never builds.
void main() {
  // Set once the real app is running — after that, uncaught errors are only
  // logged, never allowed to replace the whole app with the error screen.
  var appStarted = false;
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    String? startupError;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
          .timeout(const Duration(seconds: 15));
      await connectToEmulatorsIfEnabled();
    } catch (e) {
      startupError = 'Firebase.initializeApp failed:\n$e';
    }
    runApp(startupError == null
        ? const AdminWebApp()
        : _StartupErrorApp(message: startupError));
    appStarted = startupError == null;
  }, (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    if (appStarted) return;
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
