import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Bridges WebView session state (cookies, referer) into plain HTTP headers
/// so downloads issued outside the WebView keep working.
class WebViewCookieBridge {
  WebViewCookieBridge._();

  /// Builds `Cookie` + `Referer` headers for [url].
  ///
  /// Returns an empty map when [url] is invalid or cookies are unavailable.
  static Future<Map<String, String>> buildHeaders(
    String url, {
    String? referer,
  }) async {
    try {
      final Map<String, String> headers = <String, String>{};
      final String cookies = await getCookieHeader(url);
      if (cookies.isNotEmpty) {
        headers['Cookie'] = cookies;
      }
      final String? ref = (referer != null && referer.isNotEmpty)
          ? referer
          : _defaultReferer(url);
      if (ref != null && ref.isNotEmpty) {
        headers['Referer'] = ref;
      }
      return headers;
    } catch (_) {
      return <String, String>{};
    }
  }

  /// Returns the `Cookie` header value (`name=value; ...`) for [url],
  /// or an empty string when unavailable.
  static Future<String> getCookieHeader(String url) async {
    try {
      final List<Cookie> cookies =
          await CookieManager.instance().getCookies(url: WebUri(url));
      return cookies.map((Cookie c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  /// Falls back to `scheme://host` when no explicit referer is given.
  static String? _defaultReferer(String url) {
    try {
      final WebUri uri = WebUri(url);
      final String host = uri.host;
      if (host.isEmpty) {
        return null;
      }
      final String scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
      return '$scheme://$host';
    } catch (_) {
      return null;
    }
  }
}
