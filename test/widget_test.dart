import 'package:downloader/domain/detect_video_use_case.dart';
import 'package:downloader/domain/download_request.dart';
import 'package:downloader/domain/video_url_matcher.dart';
import 'package:downloader/infrastructure/webview_video_sniffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoUrlMatcher.isVideoUrl', () {
    test('accepts direct .mp4 link', () {
      expect(VideoUrlMatcher.isVideoUrl('https://example.com/v/video.mp4'),
          isTrue);
    });

    test('accepts direct .webm link', () {
      expect(VideoUrlMatcher.isVideoUrl('https://example.com/v/clip.webm'),
          isTrue);
    });

    test('matches extension before query string (signed/redirected URL)', () {
      expect(
          VideoUrlMatcher.isVideoUrl(
              'https://cdn.example.com/v.mp4?token=AbC123&exp=999'),
          isTrue);
    });

    test('is case-insensitive on path only', () {
      expect(VideoUrlMatcher.isVideoUrl('https://example.com/V/Clip.MP4'),
          isTrue);
    });

    test('rejects blob: URLs (expected miss)', () {
      expect(VideoUrlMatcher.isVideoUrl('blob:https://example.com/abc'),
          isFalse);
    });

    test('rejects data: and non-http schemes', () {
      expect(VideoUrlMatcher.isVideoUrl('data:video/mp4;base64,AAAA'),
          isFalse);
      expect(VideoUrlMatcher.isVideoUrl('file:///sdcard/v.mp4'), isFalse);
    });

    test('rejects non-video pages', () {
      expect(VideoUrlMatcher.isVideoUrl('https://example.com/watch?v=1'),
          isFalse);
      expect(
          VideoUrlMatcher.isVideoUrl('https://example.com/thumb.jpg'),
          isFalse);
    });
  });

  group('VideoUrlMatcher.isVideoContentType', () {
    test('accepts video/mp4 and video/webm with params', () {
      expect(VideoUrlMatcher.isVideoContentType('video/mp4'), isTrue);
      expect(
          VideoUrlMatcher.isVideoContentType('video/webm; charset=binary'),
          isTrue);
    });

    test('rejects non-video and null types', () {
      expect(VideoUrlMatcher.isVideoContentType('text/html'), isFalse);
      expect(VideoUrlMatcher.isVideoContentType(null), isFalse);
    });
  });

  group('VideoUrlMatcher false positives', () {
    test('rejects ad/tracker domains', () {
      expect(
          VideoUrlMatcher.looksDownloadable(
              'https://doubleclick.net/v.mp4?sz=1x1'),
          isFalse);
      expect(
          VideoUrlMatcher.looksDownloadable(
              'https://example.com/pixel.mp4'),
          isFalse);
    });
  });

  group('VideoUrlMatcher.normalizeForDedup', () {
    test('lowercases scheme+host but preserves path/query case', () {
      expect(
          VideoUrlMatcher.normalizeForDedup(
              'HTTPS://Example.COM/V/Clip.mp4?Token=AbC'),
          'https://example.com/V/Clip.mp4?Token=AbC');
    });
  });

  group('VideoUrlMatcher.suggestFileName', () {
    test('extracts last segment and keeps extension', () {
      expect(
          VideoUrlMatcher.suggestFileName(
              'https://cdn.example.com/a/clip_720.mp4?x=1'),
          'clip_720.mp4');
    });

    test('falls back to generated name when no segment', () {
      expect(
          VideoUrlMatcher.suggestFileName('https://example.com/'),
          startsWith('video_'));
    });
  });

  group('DownloadRequest', () {
    test('preserves original URL exactly (signatures intact)', () {
      const url = 'https://cdn.example.com/v.mp4?Token=AbC&Exp=1';
      final req = DownloadRequest(
        url: url,
        suggestedFileName: 'v.mp4',
        detectedAt: DateTime(2026, 1, 1),
      );
      expect(req.url, same(url));
      expect(req.url, url);
    });
  });

  group('WebViewVideoSniffer and DetectVideoUseCase', () {
    test('deduplicates URLs in sniffer and filters via use case', () async {
      final WebViewVideoSniffer sniffer = WebViewVideoSniffer();
      final DetectVideoUseCase useCase = DetectVideoUseCase(sniffer);

      final List<DownloadRequest> detected = <DownloadRequest>[];
      final subscription = useCase.videos.listen(detected.add);

      // Emits video
      expect(sniffer.handleUrl('https://example.com/video.mp4'), isTrue);
      // Rejects duplicate
      expect(sniffer.handleUrl('https://example.com/video.mp4'), isFalse);
      // Rejects blob
      expect(sniffer.handleUrl('blob:https://example.com/uuid'), isFalse);
      // Sniffer accepts non-video url candidate, but useCase filters it out
      expect(sniffer.handleUrl('https://example.com/ad/tracking.js'), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(detected.length, 1);
      expect(detected.first.url, 'https://example.com/video.mp4');

      await subscription.cancel();
      sniffer.dispose();
    });
  });
}
