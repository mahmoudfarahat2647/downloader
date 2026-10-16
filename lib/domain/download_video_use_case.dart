import 'download_request.dart';
import 'i_file_downloader.dart';
import 'i_hls_downloader.dart';
import 'i_storage_gateway.dart';
import 'video_url_matcher.dart';

/// Use case orchestrating download-then-save.
///
/// Routes each [DownloadRequest] to the right fetcher, then moves the
/// resulting temp file to its final location via [storage]. Callers observe
/// progress and receive either the final saved path or an error message.
///
/// Routing rules (see [execute]):
///   * Unresolved (`needsResolve` or [VideoKind.blob]) fails fast — there is
///     no byte-range to fetch yet.
///   * HLS ([VideoKind.hls], a `.m3u8` URL, or an
///     `application/x-mpegURL` content type) delegates to the injected
///     [IHlsDownloader], which concatenates segments without transcoding.
///   * Everything else uses the direct progressive [downloader].
///
/// Container note: the HLS path writes MPEG-TS playlists (no `EXT-X-MAP`
/// init segment) as `.ts` and fMP4 playlists (init segment present) as
/// `.mp4`. No transcode is performed — the extension reflects the source
/// container, so `.ts` output will not play in players without TS support.
class DownloadVideoUseCase {
  /// Low-level downloader producing temp files for direct progressive URLs.
  final IFileDownloader downloader;

  /// Gateway persisting temp files into downloads.
  final IStorageGateway storage;

  /// HLS fetcher for playlist URLs. Null means HLS is unavailable.
  ///
  /// Nullable (instead of a default instance) so the existing
  /// `DownloadVideoUseCase(downloader, storage)` call site keeps working and
  /// tests can inject a fake. The composition root provides the real
  /// implementation; the domain never constructs infrastructure itself.
  final IHlsDownloader? hlsDownloader;

  /// Builds live session headers (cookies/referer) for a playlist URL.
  ///
  /// Nullable so tests can omit it; the composition root provides the
  /// WebView-backed implementation.
  final Future<Map<String, String>> Function(String url)? headerBuilder;

  /// Tracks the active HLS download so [cancel] can abort it.
  IHlsDownloader? _activeHls;

  /// Creates a use case with the given [downloader] and [storage].
  ///
  /// Pass [hlsDownloader] to enable HLS downloads (tests may pass a fake);
  /// omit it and HLS requests fail fast with 'Stream download unavailable'.
  /// Pass [headerBuilder] to merge live session headers into HLS requests.
  DownloadVideoUseCase(
    this.downloader,
    this.storage, {
    this.hlsDownloader,
    this.headerBuilder,
  });

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
    if (request.needsResolve || request.kind == VideoKind.blob) {
      onError('Stream is still resolving...');
      return;
    }
    if (_isHls(request)) {
      await _downloadHls(
        request,
        onProgress: onProgress,
        onComplete: onComplete,
        onError: onError,
      );
      return;
    }
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

  /// Fetches an HLS playlist via [hlsDownloader], then saves as usual.
  ///
  /// Merges [DownloadRequest.headers] with the live session headers from
  /// [headerBuilder] (when provided) so protected playlists keep working.
  /// The service's temp file (`.ts` for MPEG-TS, `.mp4` for fMP4) is
  /// persisted via [storage] exactly like the direct path.
  Future<void> _downloadHls(
    DownloadRequest request, {
    required void Function(double) onProgress,
    required void Function(String savedPath) onComplete,
    required void Function(String error) onError,
  }) async {
    final IHlsDownloader? hls = hlsDownloader;
    if (hls == null) {
      onError('Stream download unavailable');
      return;
    }
    _activeHls = hls;
    try {
      final Map<String, String> sessionHeaders =
          await headerBuilder?.call(request.url) ?? <String, String>{};
      final Map<String, String> headers = <String, String>{
        ...?request.headers,
        ...sessionHeaders,
      };
      await hls.download(
        playlistUrl: request.url,
        headers: headers,
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
    } finally {
      if (identical(_activeHls, hls)) {
        _activeHls = null;
      }
    }
  }

  /// Returns true for HLS requests: [VideoKind.hls], a `.m3u8` URL path
  /// (query/fragment ignored, case-insensitive), or an
  /// `application/x-mpegURL` content type (parameters after `;` ignored,
  /// case-insensitive).
  bool _isHls(DownloadRequest request) {
    if (request.kind == VideoKind.hls) {
      return true;
    }
    if (VideoUrlMatcher.isHlsUrl(request.url)) {
      return true;
    }
    final String? contentType = request.contentType;
    if (contentType != null &&
        contentType.split(';').first.trim().toLowerCase() ==
            'application/x-mpegurl') {
      return true;
    }
    return false;
  }

  /// Cancels the in-flight download, whether direct or HLS.
  void cancel() {
    downloader.cancel();
    hlsDownloader?.cancel();
    _activeHls?.cancel();
  }
}
