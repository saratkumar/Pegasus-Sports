import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'app_toast.dart';

/// Logs the real error to Crashlytics (so it's visible in the Firebase
/// Console without depending on a user relaying a raw exception string) and
/// shows a short, human-readable [userMessage] instead of the raw exception
/// text — callers should never surface `error.toString()` directly.
void reportError(
  BuildContext context,
  Object error,
  StackTrace stackTrace, {
  required String userMessage,
  required String reason,
}) {
  FirebaseCrashlytics.instance
      .recordError(error, stackTrace, reason: reason, fatal: false);
  if (context.mounted) {
    AppToast.error(context, userMessage);
  }
}

/// A bare `Exception('...')` thrown by this app's own service layer (coupon/
/// appointment validation, etc. — see coupon_service.dart, appointment_
/// service.dart) carries a message that's already written for the user, e.g.
/// "This coupon has expired". Unlike FirebaseException/StripeException/
/// PlatformException, its toString() is exactly `Exception: <message>`, with
/// no internal code or type name — so that shape is used as the signal that
/// [error] is safe to show verbatim instead of falling back to [fallback].
String friendlyMessage(Object error, String fallback) {
  final text = error.toString();
  const prefix = 'Exception: ';
  return text.startsWith(prefix) ? text.substring(prefix.length) : fallback;
}
