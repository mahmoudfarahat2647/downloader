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

  /// Returns true for `video/mp4`, `video/webm`, `application/x-mpegURL`
  /// and `application/dash+xml` content types.
  ///
  /// Strips parameters after `;`, trims whitespace and lowercases before
  /// comparing. Null input returns false. `text/html` and any other type
  /// return false.
  static bool isVideoContentType(String? contentType) {
    if (contentType == null) return false;
    final String mime = contentType.split(';').first.trim().toLowerCase();
    return mime == 'video/mp4' ||
        mime == 'video/webm' ||
        mime == 'application/x-mpegurl' ||
        mime == 'application/dash+xml';
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
    // Preserve the real media container when the URL already carries one.
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v')) {
      return sanitized;
    }
    // A manifest is not the media itself: `stream.m3u8` → `stream.mp4`. The
    // HLS downloader later rewrites the extension to the real container
    // (`.ts` for MPEG-TS, `.mp4` for fMP4) via [alignFileNameWithContainer].
    for (final String manifest in <String>['.m3u8', '.mpd']) {
      if (lower.endsWith(manifest)) {
        final String base =
            sanitized.substring(0, sanitized.length - manifest.length);
        return base.isEmpty ? sanitized : '$base.mp4';
      }
    }
    return '$sanitized.mp4';
  }

  /// Rewrites [suggestedFileName]'s extension to match the container actually
  /// written to [tempPath].
  ///
  /// Used by the download flow: an HLS request may suggest `stream.mp4` while
  /// the fetched file is MPEG-TS (`…/vd_hls_123.ts`), so the persisted name
  /// must follow the temp file (`stream.ts`) instead of mislabelling the bytes.
  /// A manifest extension left in the name is stripped first
  /// (`stream.m3u8.mp4` → `stream.ts`). Returns [suggestedFileName] unchanged
  /// when [tempPath] has no extension.
  static String alignFileNameWithContainer(
    String suggestedFileName,
    String tempPath,
  ) {
    final String containerExt = _extensionOf(tempPath);
    if (containerExt.isEmpty) return suggestedFileName;
    final String trimmed = suggestedFileName.trim();
    String base = trimmed.isEmpty ? 'video' : _stripExtension(trimmed);
    final String lowerBase = base.toLowerCase();
    if (lowerBase.endsWith('.m3u8')) {
      base = base.substring(0, base.length - '.m3u8'.length);
    } else if (lowerBase.endsWith('.mpd')) {
      base = base.substring(0, base.length - '.mpd'.length);
    }
    if (base.isEmpty) base = 'video';
    return '$base.$containerExt';
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
  /// [isSupportedMediaUrl] passes and [isLikelyFalsePositive] rejects it.
  ///
  /// When [contentType] is supplied, an extensionless URL (e.g. an fbcdn
  /// delivery link) still counts as supported if [isVideoContentType]
  /// accepts the content type.
  static bool looksDownloadable(String url, [String? contentType]) {
    return isSupportedMediaUrl(url, contentType) &&
        !isLikelyFalsePositive(url);
  }

  /// Returns true when it is worth issuing a background metadata probe
  /// (HTTP HEAD) for [url].
  ///
  /// True for anything [looksDownloadable] accepts, and — crucially — for
  /// extensionless `http`/`https` delivery URLs (`https://fbcdn.../v/12345`,
  /// `googlevideo` style endpoints) whose real content type is only
  /// discoverable from a HEAD response. False for ordinary page assets
  /// (`app.css`, `bundle.js`, `thumb.jpg`) and ad/tracker URLs, so a page load
  /// does not fan out into hundreds of HEAD requests.
  static bool shouldProbeMetadata(String url, [String? contentType]) {
    if (looksDownloadable(url, contentType)) return true;
    try {
      final String trimmed = url.trim();
      if (trimmed.isEmpty) return false;
      final Uri uri = Uri.parse(trimmed);
      final String scheme = uri.scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return false;
      if (isLikelyFalsePositive(url)) return false;
      // Only extensionless paths are worth probing: a known extension that is
      // not media (css/js/jpg/…) is definitively not a downloadable video.
      return _extensionOf(uri.path).isEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Returns true only for `.m3u8` (HLS) URLs.
  ///
  /// Rules mirror [isVideoUrl]: trims input; rejects empty strings; parses
  /// with [Uri.parse]; rejects `blob:`, `data:`, `javascript:`, `about:`
  /// and `file` schemes; inspects [Uri.path] only (before query/fragment),
  /// lowercasing only the path for the extension check. Returns false on
  /// parse errors.
  static bool isHlsUrl(String url) {
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
      return path.endsWith('.m3u8');
    } catch (_) {
      return false;
    }
  }

  /// Returns true only for `.mpd` (DASH) URLs.
  ///
  /// Rules mirror [isVideoUrl]: trims input; rejects empty strings; parses
  /// with [Uri.parse]; rejects `blob:`, `data:`, `javascript:`, `about:`
  /// and `file` schemes; inspects [Uri.path] only (before query/fragment),
  /// lowercasing only the path for the extension check. Returns false on
  /// parse errors.
  static bool isDashUrl(String url) {
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
      return path.endsWith('.mpd');
    } catch (_) {
      return false;
    }
  }

  /// Returns true for any supported media URL.
  ///
  /// Accepts `.mp4`, `.webm`, `.mov`, `.m4v`, `.m3u8` and `.mpd` by path
  /// (same scheme/path rules as [isVideoUrl]), or — for extensionless
  /// delivery URLs — when the optional [contentType] is accepted by
  /// [isVideoContentType] (`video/mp4`, `video/webm`,
  /// `application/x-mpegURL`, `application/dash+xml`).
  static bool isSupportedMediaUrl(String url, [String? contentType]) {
    if (isVideoUrl(url) || isHlsUrl(url) || isDashUrl(url)) return true;
    try {
      final String trimmed = url.trim();
      if (trimmed.isEmpty) {
        return contentType != null && isVideoContentType(contentType);
      }
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
      if (path.endsWith('.mp4') ||
          path.endsWith('.webm') ||
          path.endsWith('.mov') ||
          path.endsWith('.m4v') ||
          path.endsWith('.m3u8') ||
          path.endsWith('.mpd')) {
        return true;
      }
    } catch (_) {
      return false;
    }
    if (contentType == null) return false;
    return isVideoContentType(contentType);
  }

  /// Returns true for any `http`/`https` URL.
  ///
  /// Trims input; requires a parseable [Uri] with scheme `http` or `https`
  /// (case-insensitive) and a non-empty host. Used to decide whether a
  /// pasted/shared link is a browsable page (including share links such as
  /// `https://www.facebook.com/share/xyz`), as opposed to a direct media
  /// file URL. Returns false on parse errors.
  static bool isPageUrl(String url) {
    try {
      final String trimmed = url.trim();
      if (trimmed.isEmpty) return false;
      final Uri uri = Uri.parse(trimmed);
      final String scheme = uri.scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return false;
      return uri.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Returns the lowercase extension (without the dot) of the last path
  /// segment in [pathOrUrl], or an empty string when there is none.
  ///
  /// `https://x/v/12345` → `''`; `https://x/clip.MP4` → `mp4`;
  /// `/tmp/vd_hls_1.ts` → `ts`.
  static String _extensionOf(String pathOrUrl) {
    final int slash = pathOrUrl.lastIndexOf(RegExp(r'[/\\]'));
    final String last =
        slash >= 0 ? pathOrUrl.substring(slash + 1) : pathOrUrl;
    final int dot = last.lastIndexOf('.');
    if (dot <= 0 || dot == last.length - 1) return '';
    return last.substring(dot + 1).toLowerCase();
  }

  /// Strips the trailing extension from [name] (`clip.mov` → `clip`).
  static String _stripExtension(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot <= 0) return name;
    return name.substring(0, dot);
  }
}
