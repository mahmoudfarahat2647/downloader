/// Pure-Dart contract for HLS playlist downloaders.
///
/// Implemented by infrastructure (e.g. the HLS segment fetcher) and consumed
/// by [DownloadVideoUseCase], so the domain never depends on concrete
/// infrastructure classes.
abstract class IHlsDownloader {
  /// Downloads the HLS stream at [playlistUrl] to a temp file.
  ///
  /// [headers] are forwarded on every request (cookies/auth). [onProgress]
  /// receives 0.0–1.0 updates. [onComplete] receives the saved temp-file
  /// path. Failures are reported via [onError], never thrown. [cancelToken]
  /// is an opaque cancellation handle owned by the implementation (typed as
  /// [Object] here so the domain stays free of HTTP-client imports; the
  /// implementation casts it internally).
  Future<void> download({
    required String playlistUrl,
    required Map<String, String> headers,
    required void Function(double) onProgress,
    required void Function(String savedPath) onComplete,
    required void Function(String error) onError,
    Object? cancelToken,
  });

  /// Cancels the in-flight download, if any.
  void cancel();
}
