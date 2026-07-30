import 'dart:async';
import 'package:app_links/app_links.dart';

/// Handles the app's custom `pegasus://` URL scheme — currently just the
/// `pegasus://renew` link used by the renewal reminder email's "Renew My
/// Plan" button (see functions/emailTemplates.js). No Universal/App Links
/// verification or web fallback: if the app isn't installed, the tap simply
/// does nothing, which is an accepted tradeoff to avoid needing a hosted
/// domain-verification page for a single deep link.
class DeepLinkService {
  static final _appLinks = AppLinks();
  static StreamSubscription<Uri>? _sub;

  /// Calls [onRenewLink] once for every `pegasus://renew` link received,
  /// whether it cold-started the app or arrived while it was already
  /// running. Safe to call more than once — an existing subscription is
  /// cancelled first. Call [dispose] when the owning widget is torn down.
  static Future<void> listenForRenewLink(void Function() onRenewLink) async {
    await _sub?.cancel();

    final initial = await _appLinks.getInitialLink();
    if (initial != null && _isRenewLink(initial)) onRenewLink();

    _sub = _appLinks.uriLinkStream.listen((uri) {
      if (_isRenewLink(uri)) onRenewLink();
    });
  }

  static bool _isRenewLink(Uri uri) =>
      uri.scheme == 'pegasus' && uri.host == 'renew';

  static void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
