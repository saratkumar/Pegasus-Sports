import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

// Crashlytics has no Flutter web implementation — every call throws
// MissingPluginException on the web shop / web admin, which aborted card
// checkout before it started. Shared code must go through these wrappers,
// which fall back to the browser console on web.

/// Breadcrumb attached to the next reported error (mobile only).
void crashLog(String message) {
  if (kIsWeb) {
    debugPrint(message);
    return;
  }
  FirebaseCrashlytics.instance.log(message);
}

/// Reports a non-fatal (or fatal) error to Crashlytics (mobile only).
void crashRecord(Object error, StackTrace? stack,
    {String? reason, bool fatal = false}) {
  if (kIsWeb) {
    debugPrint('${reason ?? 'Error'}: $error');
    return;
  }
  FirebaseCrashlytics.instance
      .recordError(error, stack, reason: reason, fatal: fatal);
}
