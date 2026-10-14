/// Value object describing a single detected downloadable video.
///
/// The [url] is the original unmodified URL as observed (e.g. from a
/// WebView request). [suggestedFileName] is a filesystem-friendly hint
/// derived at detection time. [detectedAt] records when the URL was
/// spotted. Optional [headers] may carry request headers needed to
/// download the file (e.g. cookies, referer).
///
/// Optional metadata fields ([title], [contentLength], [qualityLabel]) are
/// enriched progressively — they may be null on first detection and filled in
/// after a background HEAD request or a DOM scan completes.
class DownloadRequest {
  /// Original unmodified URL of the video resource.
  final String url;

  /// Filesystem-friendly file name suggestion (includes extension).
  final String suggestedFileName;

  /// Timestamp recording when the URL was detected.
  final DateTime detectedAt;

  /// Optional HTTP headers required to fetch [url].
  final Map<String, String>? headers;

  /// Human-readable title extracted from the page or video element.
  ///
  /// Sourced from the `<video title>` attribute or the page `<title>`.
  /// Null when not available.
  final String? title;

  /// File size in bytes, read from the server's `content-length` header.
  ///
  /// Populated asynchronously via a background HEAD request.
  /// Null when unknown.
  final int? contentLength;

  /// Quality label such as "1080p", "720p", "480p", or "360p".
  ///
  /// Derived in priority order:
  ///   1. `<source label>` / `<source res>` DOM attributes.
  ///   2. Pattern matching on the URL string.
  ///   3. `<video>.videoHeight` at runtime (fallback – often 0).
  /// Null when none of the above yields a result.
  final String? qualityLabel;

  /// Creates a new [DownloadRequest].
  const DownloadRequest({
    required this.url,
    required this.suggestedFileName,
    required this.detectedAt,
    this.headers,
    this.title,
    this.contentLength,
    this.qualityLabel,
  });

  /// Creates a copy with the given fields replaced.
  DownloadRequest copyWith({
    String? url,
    String? suggestedFileName,
    DateTime? detectedAt,
    Map<String, String>? headers,
    String? title,
    int? contentLength,
    String? qualityLabel,
  }) {
    return DownloadRequest(
      url: url ?? this.url,
      suggestedFileName: suggestedFileName ?? this.suggestedFileName,
      detectedAt: detectedAt ?? this.detectedAt,
      headers: headers ?? this.headers,
      title: title ?? this.title,
      contentLength: contentLength ?? this.contentLength,
      qualityLabel: qualityLabel ?? this.qualityLabel,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DownloadRequest &&
        other.url == url &&
        other.suggestedFileName == suggestedFileName &&
        other.detectedAt == detectedAt &&
        other.title == title &&
        other.contentLength == contentLength &&
        other.qualityLabel == qualityLabel &&
        _mapsEqual(other.headers, headers);
  }

  @override
  int get hashCode => Object.hash(
        url,
        suggestedFileName,
        detectedAt,
        title,
        contentLength,
        qualityLabel,
        _mapHash(headers),
      );

  @override
  String toString() =>
      'DownloadRequest(url: $url, suggestedFileName: $suggestedFileName, '
      'detectedAt: $detectedAt, title: $title, '
      'contentLength: $contentLength, qualityLabel: $qualityLabel, '
      'headers: $headers)';
}

/// Compares two nullable string maps for equality.
bool _mapsEqual(Map<String, String>? a, Map<String, String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (final MapEntry<String, String> entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Computes a stable hash for a nullable string map.
int _mapHash(Map<String, String>? map) {
  if (map == null) return 0;
  final List<int> entryHashes = map.entries
      .map((MapEntry<String, String> e) => Object.hash(e.key, e.value))
      .toList()
    ..sort();
  return Object.hashAll(entryHashes);
}
