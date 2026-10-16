import 'download_request.dart';
import 'i_video_detector.dart';
import 'video_url_matcher.dart';

/// Use case exposing only genuine downloadable videos.
///
/// Forwards [IVideoDetector.detectedVideos], filtering each event through
/// [VideoUrlMatcher.looksDownloadable] so UI layers never see ads,
/// trackers, or non-video resources.
class DetectVideoUseCase {
  /// Underlying detector producing raw candidate URLs.
  final IVideoDetector detector;

  /// Creates a use case wrapping [detector].
  const DetectVideoUseCase(this.detector);

  /// Stream of validated [DownloadRequest]s safe to offer for download.
  ///
  /// Filters each event through [VideoUrlMatcher.looksDownloadable] using
  /// the request's observed [DownloadRequest.contentType] (so extensionless
  /// delivery URLs with a video content-type still pass), and hides
  /// unresolvable placeholders ([DownloadRequest.needsResolve] or
  /// [VideoKind.blob]) until the real URL is resolved.
  Stream<DownloadRequest> get videos =>
      detector.detectedVideos.where((DownloadRequest r) =>
          VideoUrlMatcher.looksDownloadable(r.url, r.contentType) &&
          !r.needsResolve &&
          r.kind != VideoKind.blob);
}
