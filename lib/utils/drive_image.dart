/// Google Drive share links (`…/file/d/ID/view`, `…/open?id=ID`) point at
/// an HTML preview page, not the image, so Image.network shows nothing.
/// Rewrites them to Drive's direct image host (which also sends CORS
/// headers for the web shop); any other URL is returned unchanged. The file
/// must be shared as "Anyone with the link".
String driveDirectImageUrl(String url) {
  final u = url.trim();
  if (!u.contains('drive.google.com')) return u;
  final id = RegExp(r'/file/d/([\w-]+)').firstMatch(u)?.group(1) ??
      RegExp(r'[?&]id=([\w-]+)').firstMatch(u)?.group(1);
  return id == null ? u : 'https://lh3.googleusercontent.com/d/$id';
}
