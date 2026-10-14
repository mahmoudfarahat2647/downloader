import 'download_request.dart';

/// Contract for downloading a file to a temporary location.
///
/// Implementations fetch [DownloadRequest.url] (with [DownloadRequest.headers]
/// when present) and report progress. Completion reports a TEMP file path;
/// callers are responsible for moving it to its final destination (see
/// `IStorageGateway.saveToDownloads`). [cancel] aborts an in-flight download.
abstract class IFileDownloader {
  /// Downloads [request], reporting progress/completion via callbacks.
  ///
  /// [onProgress] receives values in the range 0.0–1.0. [onComplete] receives
  /// the TEMP file path (not the final destination). [onError] receives a
  /// human-readable error message.
  Future<void> download(
    DownloadRequest request, {
    required void Function(double progress) onProgress,
    required void Function(String tempPath) onComplete,
    required void Function(String error) onError,
  });

  /// Cancels the currently running download, if any.
  void cancel();
}
