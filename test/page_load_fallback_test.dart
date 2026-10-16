import 'package:downloader/presentation/browser_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('facebookMobileFallback', () {
    test('rewrites www.facebook.com reel to m.facebook.com', () {
      expect(
        facebookMobileFallback(
          'https://www.facebook.com/reel/1803681354276534',
        ),
        'https://m.facebook.com/reel/1803681354276534',
      );
    });

    test('preserves path and query when rewriting', () {
      expect(
        facebookMobileFallback('https://www.facebook.com/share/abc/?x=1'),
        'https://m.facebook.com/share/abc/?x=1',
      );
    });

    test('returns null for non-Facebook URLs', () {
      expect(facebookMobileFallback('https://example.com/video.mp4'), isNull);
      expect(facebookMobileFallback('https://m.facebook.com/reel/1'), isNull);
    });

    test('returns null for empty or unparsable input', () {
      expect(facebookMobileFallback(''), isNull);
      expect(facebookMobileFallback('not a url'), isNull);
    });
  });

  group('kChromeMobileUserAgent', () {
    test('does not contain the WebView wv token', () {
      expect(kChromeMobileUserAgent.contains('wv'), isFalse);
      expect(kChromeMobileUserAgent.contains('Chrome/'), isTrue);
      expect(kChromeMobileUserAgent.contains('Mobile'), isTrue);
    });
  });
}
