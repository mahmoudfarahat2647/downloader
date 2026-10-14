/// Value object describing a single detected downloadable video.
///
/// The [url] is the original unmodified URL as observed (e.g. from a
/// WebView request). [suggestedFileName] is a filesystem-friendly hint
/// derived at detection time. [detectedAt] records when the URL was
/// spotted. Optional [headers] may carry request headers needed to
/// download the file (e.g. cookies, referer).
class DownloadRequest {
  /// Original unmodified URL of the video resource.
  final String url;

  /// Filesystem-friendly file name suggestion (includes extension).
  final String suggestedFileName;

  /// Timestamp recording when the URL was detected.
  final DateTime detectedAt;

  /// Optional HTTP headers required to fetch [url].
  final Map<String, String>? headers;

  /// Creates a new [DownloadRequest].
  const DownloadRequest({
    required this.url,
    required this.suggestedFileName,
    required this.detectedAt,
    this.headers,
  });

  /// Creates a copy with the given fields replaced.
  DownloadRequest copyWith({
    String? url,
    String? suggestedFileName,
    DateTime? detectedAt,
    Map<String, String>? headers,
  }) {
    return DownloadRequest(
      url: url ?? this.url,
      suggestedFileName: suggestedFileName ?? this.suggestedFileName,
      detectedAt: detectedAt ?? this.detectedAt,
      headers: headers ?? this.headers,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DownloadRequest &&
        other.url == url &&
        other.suggestedFileName == suggestedFileName &&
        other.detectedAt == detectedAt &&
        _mapsEqual(other.headers, headers);
  }

  @override
  int get hashCode => Object.hash(url, suggestedFileName, detectedAt, _mapHash(headers));

  @override
  String toString() =>
      'DownloadRequest(url: $url, suggestedFileName: $suggestedFileName, '
      'detectedAt: $detectedAt, headers: $headers)';
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
