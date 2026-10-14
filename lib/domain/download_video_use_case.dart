import 'download_request.dart';
import 'i_file_downloader.dart';
import 'i_storage_gateway.dart';

/// Use case orchestrating download-then-save.
///
/// Delegates fetching to [downloader] (which yields a temp file), then
/// moves it to its final location via [storage]. Callers observe progress
/// and receive either the final saved path or an error message.
class DownloadVideoUseCase {
  /// Low-level downloader producing temp files.
  final IFileDownloader downloader;

  /// Gateway persisting temp files into downloads.
  final IStorageGateway storage;

  /// Creates a use case with the given [downloader] and [storage].
  const DownloadVideoUseCase(this.downloader, this.storage);

  /// Executes the download-then-save flow for [request].
  ///
  /// [onProgress] receives 0.0–1.0 updates. [onComplete] receives the final
  /// saved path. [onError] receives a human-readable error message whether
  /// the download or the save step fails.
  Future<void> execute(
    DownloadRequest request, {
    required void Function(double) onProgress,
    required void Function(String savedPath) onComplete,
    required void Function(String error) onError,
  }) async {
    try {
      await downloader.download(
        request,
        onProgress: onProgress,
        onComplete: (String tempPath) async {
          try {
            final String saved =
                await storage.saveToDownloads(tempPath, request.suggestedFileName);
            onComplete(saved);
          } catch (e) {
            onError('Save failed: $e');
          }
        },
        onError: onError,
      );
    } catch (e) {
      onError(e.toString());
    }
  }

  /// Cancels the in-flight download, if any.
  void cancel() => downloader.cancel();
}
