import 'package:flutter_test/flutter_test.dart';

import 'package:downloader/infrastructure/hls_playlist_parser.dart';

/// Master playlist fixture with two variants (1080p has higher bandwidth).
const String masterFixture = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
low/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720
high/index.m3u8
''';

/// fMP4 media fixture: EXT-X-MAP init segment + relative segment URLs.
const String fmp4Fixture = '''
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-TARGETDURATION:6
#EXT-X-MAP:URI="init.mp4"
#EXTINF:6.0,
seg-0.m4s
#EXTINF:6.0,
seg-1.m4s
#EXT-X-ENDLIST
''';

/// MPEG-TS media fixture with absolute + relative segment URLs.
const String tsFixture = '''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:10.0,
https://cdn.example.com/videos/seg-0.ts
#EXTINF:10.0,
seg-1.ts
#EXT-X-ENDLIST
''';

/// Encrypted media fixture (EXT-X-KEY present).
const String encryptedFixture = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXT-X-KEY:METHOD=AES-128,URI="https://keys.example.com/k.key"
#EXTINF:6.0,
seg-0.ts
#EXTINF:6.0,
seg-1.ts
#EXT-X-ENDLIST
''';

/// Live media fixture: no EXT-X-ENDLIST.
const String liveFixture = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:100
#EXTINF:6.0,
seg-100.ts
#EXTINF:6.0,
seg-101.ts
''';

void main() {
  group('parseHlsPlaylist master', () {
    test('detects master and resolves relative variant URLs', () {
      final HlsPlaylist playlist = parseHlsPlaylist(
        masterFixture,
        'https://cdn.example.com/videos/master.m3u8',
      );

      expect(playlist.isMaster, isTrue);
      expect(playlist.isLive, isFalse);
      expect(playlist.isEncrypted, isFalse);
      expect(playlist.variants, hasLength(2));
      expect(
        playlist.variants.map((HlsVariant v) => v.url),
        containsAll(<String>[
          'https://cdn.example.com/videos/low/index.m3u8',
          'https://cdn.example.com/videos/high/index.m3u8',
        ]),
      );
      expect(playlist.segments, isEmpty);
    });

    test('bestVariantUrl picks the highest bandwidth', () {
      final HlsPlaylist playlist = parseHlsPlaylist(
        masterFixture,
        'https://cdn.example.com/videos/master.m3u8',
      );

      expect(
        playlist.bestVariantUrl,
        'https://cdn.example.com/videos/high/index.m3u8',
      );
    });
  });

  group('parseHlsPlaylist fMP4 media', () {
    test('captures init segment and resolves segments', () {
      final HlsPlaylist playlist = parseHlsPlaylist(
        fmp4Fixture,
        'https://cdn.example.com/videos/fmp4/index.m3u8',
      );

      expect(playlist.isMaster, isFalse);
      expect(playlist.isLive, isFalse);
      expect(playlist.isEncrypted, isFalse);
      expect(
        playlist.initSegment,
        'https://cdn.example.com/videos/fmp4/init.mp4',
      );
      expect(playlist.segments, <String>[
        'https://cdn.example.com/videos/fmp4/seg-0.m4s',
        'https://cdn.example.com/videos/fmp4/seg-1.m4s',
      ]);
      expect(playlist.targetDuration, 6);
    });
  });

  group('parseHlsPlaylist TS media', () {
    test('keeps absolute URLs and resolves relative ones', () {
      final HlsPlaylist playlist = parseHlsPlaylist(
        tsFixture,
        'https://cdn.example.com/videos/ts/index.m3u8',
      );

      expect(playlist.isMaster, isFalse);
      expect(playlist.isLive, isFalse);
      expect(playlist.initSegment, isNull);
      expect(playlist.segments, <String>[
        'https://cdn.example.com/videos/seg-0.ts',
        'https://cdn.example.com/videos/ts/seg-1.ts',
      ]);
    });
  });

  group('parseHlsPlaylist rejection signals', () {
    test('flags encrypted playlists', () {
      final HlsPlaylist playlist = parseHlsPlaylist(
        encryptedFixture,
        'https://cdn.example.com/videos/enc/index.m3u8',
      );

      expect(playlist.isEncrypted, isTrue);
      expect(playlist.isMaster, isFalse);
      expect(playlist.segments, hasLength(2));
    });

    test('flags live playlists missing EXT-X-ENDLIST', () {
      final HlsPlaylist playlist = parseHlsPlaylist(
        liveFixture,
        'https://cdn.example.com/videos/live/index.m3u8',
      );

      expect(playlist.isLive, isTrue);
      expect(playlist.isMaster, isFalse);
      expect(playlist.segments, <String>[
        'https://cdn.example.com/videos/live/seg-100.ts',
        'https://cdn.example.com/videos/live/seg-101.ts',
      ]);
    });
  });
}
