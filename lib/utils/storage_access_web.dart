import 'dart:js_interop';

@JS('document.requestStorageAccess')
external JSPromise<JSAny?>? _requestStorageAccess();

/// Best-effort request for Safari's Storage Access API before the sign-in
/// popup — without it, Safari's cross-site iframe tracking prevention can
/// block/evict the auth session's storage entirely. Silently ignored where
/// unsupported (every non-Safari browser today, where calling the undefined
/// JS function throws) or denied.
Future<void> tryRequestStorageAccess() async {
  try {
    final promise = _requestStorageAccess();
    if (promise == null) return;
    await promise.toDart;
  } catch (_) {
    // Unsupported or denied — sign-in still proceeds via signInWithPopup.
  }
}
