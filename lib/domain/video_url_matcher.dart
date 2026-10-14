/// Pure-Dart helpers for recognising downloadable video URLs.
///
/// All members are static. This class has no dependencies (no Flutter,
/// no infrastructure) so it can be unit-tested in isolation.
class VideoUrlMatcher {
  /// Private constructor to prevent instantiation.
  const VideoUrlMatcher._();

  /// Returns true only for `.mp4` / `.webm` URLs.
  ///
  /// Rules: trims input; rejects empty strings; parses with [Uri.parse];
  /// rejects `blob:`, `data:`, `javascript:`, `about:` and `file` schemes;
  /// inspects [Uri.path] only (before query/fragment), lowercasing only
  /// the path for the extension check. Strict: query strings such as
  /// `?file=video.mp4` do NOT count. Returns false on parse errors.
  static bool isVideoUrl(String url) {
    try {
      final String trimmed = url.trim();
      if (trimmed.isEmpty) return false;
      final Uri uri = Uri.parse(trimmed);
      final String scheme = uri.scheme.toLowerCase();
      if (scheme == 'blob' ||
          scheme == 'data' ||
          scheme == 'javascript' ||
          scheme == 'about' ||
          scheme == 'file') {
        return false;
      }
      final String path = uri.path.toLowerCase();
      return path.endsWith('.mp4') || path.endsWith('.webm');
    } catch (_) {
      return false;
    }
  }

  /// Returns true for `video/mp4` and `video/webm` content types.
  ///
  /// Strips parameters after `;`, trims whitespace and lowercases before
  /// comparing. Null input returns false.
  static bool isVideoContentType(String? contentType) {
    if (contentType == null) return false;
    final String mime = contentType.split(';').first.trim().toLowerCase();
    return mime == 'video/mp4' || mime == 'video/webm';
  }

  /// Normalizes [url] for de-duplication.
  ///
  /// Lowercases scheme and host only; preserves path, query and fragment
  /// exactly (including case). Preserves the port when present. If parsing
  /// fails, returns `url.trim()`.
  static String normalizeForDedup(String url) {
    final String trimmed = url.trim();
    try {
      final Uri uri = Uri.parse(trimmed);
      if (uri.host.isEmpty) return trimmed;
      final String scheme = uri.scheme.toLowerCase();
      final String host = uri.host.toLowerCase();
      final StringBuffer buffer = StringBuffer('$scheme://');
      if (uri.userInfo.isNotEmpty) {
        buffer.write('${uri.userInfo}@');
      }
      buffer.write(host);
      if (uri.hasPort) {
        buffer.write(':${uri.port}');
      }
      buffer.write(uri.path);
      if (uri.query.isNotEmpty) {
        buffer.write('?${uri.query}');
      }
      if (uri.fragment.isNotEmpty) {
        buffer.write('#${uri.fragment}');
      }
      return buffer.toString();
    } catch (_) {
      return trimmed;
    }
  }

  /// Suggests a filesystem-friendly file name for [url].
  ///
  /// Extracts the last path segment, URL-decodes it and strips any query.
  /// When the segment is empty or has no extension, generates
  /// `video_<epoch>.mp4`. Illegal characters (`\ / : * ? " < > |`) are
  /// replaced with `_`. Ensures the result ends with `.mp4` or `.webm`,
  /// appending `.mp4` otherwise.
  static String suggestFileName(String url) {
    String segment = '';
    try {
      final Uri uri = Uri.parse(url.trim());
      if (uri.pathSegments.isNotEmpty) {
        segment = Uri.decodeComponent(uri.pathSegments.last);
      }
    } catch (_) {
      segment = '';
    }
    segment = segment.split('?').first.split('#').first.trim();
    if (segment.isEmpty || !segment.contains('.')) {
      return 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
    }
    final String sanitized = segment.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final String lower = sanitized.toLowerCase();
    if (lower.endsWith('.mp4') || lower.endsWith('.webm')) {
      return sanitized;
    }
    return '$sanitized.mp4';
  }

  /// Heuristic ad/tracker blocklist.
  ///
  /// Returns true when the lowercased full URL contains any of
  /// `doubleclick.net`, `googlesyndication.com`, `google-analytics.com`,
  /// `/pixel`, `tracking`, `beacon`, `.gif` or `1x1`. Used to reject ads.
  static bool isLikelyFalsePositive(String url) {
    final String lower = url.toLowerCase();
    const List<String> blocklist = <String>[
      'doubleclick.net',
      'googlesyndication.com',
      'google-analytics.com',
      '/pixel',
      'tracking',
      'beacon',
      '.gif',
      '1x1',
    ];
    for (final String token in blocklist) {
      if (lower.contains(token)) return true;
    }
    return false;
  }

  /// Returns true when [url] looks like a real downloadable video:
  /// [isVideoUrl] passes and [isLikelyFalsePositive] rejects it.
  static bool looksDownloadable(String url) {
    return isVideoUrl(url) && !isLikelyFalsePositive(url);
  }
}
