import 'download_request.dart';

/// Contract for any component that detects video URLs.
///
/// Implementations may observe WebView traffic, parse pages, or accept
/// manual input. Consumers subscribe to [detectedVideos].
abstract class IVideoDetector {
  /// Broadcast stream of detected download requests.
  Stream<DownloadRequest> get detectedVideos;

  /// Submits a candidate URL for detection.
  ///
  /// Returns true when accepted and emitted.
  ///
  /// Optional metadata ([title], [contentLength], [qualityLabel]) may be
  /// supplied when the call site already has richer information (e.g. from
  /// a DOM scan). When the URL is already known, the implementation should
  /// *merge* the new metadata rather than silently dropping the call.
  ///
  /// [isGenericTitle] marks whether [title] is a generic fallback
  /// (`document.title`) as opposed to a specific source (`<video title>`,
  /// anchor text). Generic titles never overwrite specific ones, but
  /// specific titles may upgrade a previously stored generic title.
  bool handleUrl(
    String url, {
    Map<String, String>? headers,
    String? contentType,
    String source = 'intercept',
    String? title,
    int? contentLength,
    String? qualityLabel,
    bool isGenericTitle = false,
  });

  /// Submits a user-entered URL for validation/detection.
  void addManualUrl(String url);

  /// JavaScript to inject on page load for intercepting fetch/XHR, if any.
  String? get networkHookScript;

  /// JavaScript to evaluate during periodic DOM scans, if any.
  String? get pageScanScript;

  /// Releases any held resources (e.g. closes stream controllers).
  void dispose();
}
