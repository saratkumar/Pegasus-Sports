import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Local test mode: `flutter run --dart-define=USE_EMULATOR=true` points the
/// app at the Firebase Local Emulator Suite (`firebase emulators:start`)
/// instead of production, so testing never touches live data. Off by
/// default — release builds never pass the flag.
const useEmulator = bool.fromEnvironment('USE_EMULATOR');

/// Must run right after Firebase.initializeApp and before any Firestore,
/// Auth or Functions call. No-op unless [useEmulator].
Future<void> connectToEmulatorsIfEnabled() async {
  if (!useEmulator) return;
  // The Android emulator reaches the host PC at 10.0.2.2.
  final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : 'localhost';
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  // Cloud Functions run in the local functions emulator. Card payments and
  // the Google Sheet activity log are switched off there (IS_EMULATOR in
  // functions/index.js); coach photo uploads still go to the real Drive
  // folder, named "TEST - …". If the functions emulator isn't running,
  // calls fail fast instead of reaching production.
  FirebaseFunctions.instanceFor(region: 'asia-southeast1')
      .useFunctionsEmulator(host, 5001);
  debugPrint('Using Firebase emulators on $host (test mode — not production)');
}
