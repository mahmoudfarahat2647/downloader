import 'package:downloader/domain/video_url_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoUrlMatcher.isHlsUrl', () {
    test('accepts .m3u8 path', () {
      expect(
        VideoUrlMatcher.isHlsUrl('https://example.com/stream/master.m3u8'),
        isTrue,
      );
    });

    test('accepts .m3u8 with query string', () {
      expect(
        VideoUrlMatcher.isHlsUrl(
          'https://example.com/stream/master.m3u8?token=abc',
        ),
        isTrue,
      );
    });

    test('is case-insensitive on path', () {
      expect(
        VideoUrlMatcher.isHlsUrl('https://example.com/stream/MASTER.M3U8'),
        isTrue,
      );
    });

    test('rejects mp4', () {
      expect(
        VideoUrlMatcher.isHlsUrl('https://example.com/video.mp4'),
        isFalse,
      );
    });

    test('rejects blob scheme', () {
      expect(VideoUrlMatcher.isHlsUrl('blob:https://example.com/x'), isFalse);
    });

    test('rejects empty string', () {
      expect(VideoUrlMatcher.isHlsUrl('  '), isFalse);
    });
  });

  group('VideoUrlMatcher.isDashUrl', () {
    test('accepts .mpd path', () {
      expect(
        VideoUrlMatcher.isDashUrl('https://example.com/stream/manifest.mpd'),
        isTrue,
      );
    });

    test('accepts .mpd with query string', () {
      expect(
        VideoUrlMatcher.isDashUrl(
          'https://example.com/stream/manifest.mpd?token=abc',
        ),
        isTrue,
      );
    });

    test('rejects mp4', () {
      expect(
        VideoUrlMatcher.isDashUrl('https://example.com/video.mp4'),
        isFalse,
      );
    });

    test('rejects blob scheme', () {
      expect(VideoUrlMatcher.isDashUrl('blob:https://example.com/x'), isFalse);
    });

    test('rejects empty string', () {
      expect(VideoUrlMatcher.isDashUrl(''), isFalse);
    });
  });

  group('VideoUrlMatcher.isSupportedMediaUrl', () {
    test('accepts mov', () {
      expect(
        VideoUrlMatcher.isSupportedMediaUrl('https://example.com/clip.mov'),
        isTrue,
      );
    });

    test('accepts m4v', () {
      expect(
        VideoUrlMatcher.isSupportedMediaUrl('https://example.com/clip.m4v'),
        isTrue,
      );
    });

    test('accepts mp4 and webm', () {
      expect(
        VideoUrlMatcher.isSupportedMediaUrl('https://example.com/a.mp4'),
        isTrue,
      );
      expect(
        VideoUrlMatcher.isSupportedMediaUrl('https://example.com/a.webm'),
        isTrue,
      );
    });

    test('accepts hls and dash', () {
      expect(
        VideoUrlMatcher.isSupportedMediaUrl(
          'https://example.com/stream/master.m3u8',
        ),
        isTrue,
      );
      expect(
        VideoUrlMatcher.isSupportedMediaUrl(
          'https://example.com/stream/manifest.mpd',
        ),
        isTrue,
      );
    });

    test('rejects plain page URL without content type', () {
      expect(
        VideoUrlMatcher.isSupportedMediaUrl('https://example.com/watch/123'),
        isFalse,
      );
    });

    test('extensionless fbcdn URL with video/mp4 content-type is supported', () {
      const String url = 'https://video.fbcn1.fbcdn.net/v/12345?token=abc';
      expect(VideoUrlMatcher.isVideoUrl(url), isFalse);
      expect(VideoUrlMatcher.isVideoContentType('video/mp4'), isTrue);
      expect(VideoUrlMatcher.isSupportedMediaUrl(url, 'video/mp4'), isTrue);
    });

    test('extensionless URL with hls content-type is supported', () {
      const String url = 'https://example.com/delivery/abc123';
      expect(
        VideoUrlMatcher.isSupportedMediaUrl(url, 'application/x-mpegURL'),
        isTrue,
      );
      expect(
        VideoUrlMatcher.isSupportedMediaUrl(url, 'application/dash+xml'),
        isTrue,
      );
    });

    test('extensionless URL with text/html content-type is not supported', () {
      const String url = 'https://example.com/watch/123';
      expect(VideoUrlMatcher.isSupportedMediaUrl(url, 'text/html'), isFalse);
    });
  });

  group('VideoUrlMatcher.isVideoContentType', () {
    test('accepts application/x-mpegURL', () {
      expect(
        VideoUrlMatcher.isVideoContentType('application/x-mpegURL'),
        isTrue,
      );
    });

    test('accepts application/dash+xml', () {
      expect(
        VideoUrlMatcher.isVideoContentType('application/dash+xml'),
        isTrue,
      );
    });

    test('still accepts video/mp4 and video/webm', () {
      expect(VideoUrlMatcher.isVideoContentType('video/mp4'), isTrue);
      expect(VideoUrlMatcher.isVideoContentType('video/webm'), isTrue);
    });

    test('rejects text/html', () {
      expect(VideoUrlMatcher.isVideoContentType('text/html'), isFalse);
    });

    test('strips parameters and ignores case', () {
      expect(
        VideoUrlMatcher.isVideoContentType(
          'Application/X-MpegURL; charset=utf-8',
        ),
        isTrue,
      );
    });
  });

  group('VideoUrlMatcher.isPageUrl', () {
    test('facebook share link is a page URL but not a video URL', () {
      const String url = 'https://www.facebook.com/share/xyz';
      expect(VideoUrlMatcher.isPageUrl(url), isTrue);
      expect(VideoUrlMatcher.isVideoUrl(url), isFalse);
    });

    test('accepts http and https', () {
      expect(VideoUrlMatcher.isPageUrl('http://example.com/a'), isTrue);
      expect(VideoUrlMatcher.isPageUrl('https://example.com/a'), isTrue);
    });

    test('rejects non-http schemes and empty', () {
      expect(VideoUrlMatcher.isPageUrl('blob:https://example.com/x'), isFalse);
      expect(VideoUrlMatcher.isPageUrl('data:text/plain,hi'), isFalse);
      expect(VideoUrlMatcher.isPageUrl(''), isFalse);
    });
  });

  group('VideoUrlMatcher.looksDownloadable', () {
    test('ads still rejected', () {
      expect(
        VideoUrlMatcher.looksDownloadable(
          'https://doubleclick.net/video.mp4',
        ),
        isFalse,
      );
      expect(
        VideoUrlMatcher.looksDownloadable(
          'https://example.com/track/pixel/video.m3u8?tracking=1',
        ),
        isFalse,
      );
    });

    test('supported media accepted', () {
      expect(
        VideoUrlMatcher.looksDownloadable('https://example.com/a.mp4'),
        isTrue,
      );
      expect(
        VideoUrlMatcher.looksDownloadable(
          'https://example.com/stream/master.m3u8',
        ),
        isTrue,
      );
      expect(
        VideoUrlMatcher.looksDownloadable('https://example.com/clip.mov'),
        isTrue,
      );
    });

    test('page URL not downloadable', () {
      expect(
        VideoUrlMatcher.looksDownloadable(
          'https://www.facebook.com/share/xyz',
        ),
        isFalse,
      );
    });
  });
}
