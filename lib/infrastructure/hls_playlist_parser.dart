/// Pure-Dart HLS (M3U8) playlist parser.
///
/// No Flutter imports — safe to unit test on any platform.
///
/// Rejection rule (enforced by the caller, typically `HlsDownloadService`):
/// encrypted (`EXT-X-KEY` present) OR live (media playlist without
/// `EXT-X-ENDLIST`) streams must fail fast with a user-facing message.
/// Only unencrypted VOD (`EXT-X-ENDLIST` present) may be downloaded.
library;

/// A single rendition listed by a master playlist (`EXT-X-STREAM-INF`).
class HlsVariant {
  /// Creates a variant entry with its absolute URL and bandwidth.
  const HlsVariant({
    required this.url,
    required this.bandwidth,
    this.resolution,
    this.codecs,
  });

  /// Absolute URL of the variant media playlist.
  final String url;

  /// Peak bandwidth declared via `BANDWIDTH=` (0 when absent/unparseable).
  final int bandwidth;

  /// Declared `RESOLUTION=` value, if any (e.g. `1280x720`).
  final String? resolution;

  /// Declared `CODECS=` value, if any.
  final String? codecs;
}

/// Parsed representation of an HLS playlist (master or media).
class HlsPlaylist {
  /// Creates a parsed playlist value.
  const HlsPlaylist({
    required this.isMaster,
    required this.isLive,
    required this.isEncrypted,
    required this.variants,
    required this.segments,
    required this.initSegment,
    required this.targetDuration,
  });

  /// True when at least one `EXT-X-STREAM-INF` entry was found.
  final bool isMaster;

  /// True for media playlists without `EXT-X-ENDLIST`.
  ///
  /// Master playlists are never considered live even though they also
  /// lack `EXT-X-ENDLIST`; liveness only applies to media playlists.
  final bool isLive;

  /// True when any `EXT-X-KEY` tag was found (encrypted/protected stream).
  final bool isEncrypted;

  /// Renditions declared by a master playlist (empty for media playlists).
  final List<HlsVariant> variants;

  /// Absolute segment URLs of a media playlist (empty for master).
  final List<String> segments;

  /// Absolute `EXT-X-MAP` init-segment URL, if present (fMP4 playlists).
  final String? initSegment;

  /// Declared `EXT-X-TARGETDURATION` in seconds (0 when absent).
  final double targetDuration;

  /// Absolute URL of the highest-`BANDWIDTH` variant, or null when none.
  String? get bestVariantUrl {
    if (variants.isEmpty) {
      return null;
    }
    HlsVariant best = variants.first;
    for (final HlsVariant variant in variants.skip(1)) {
      if (variant.bandwidth > best.bandwidth) {
        best = variant;
      }
    }
    return best.url;
  }

  /// Parses M3U8 [content], resolving relative URLs against [baseUrl].
  static HlsPlaylist parse(String content, String baseUrl) {
    return parseHlsPlaylist(content, baseUrl);
  }
}

/// Parses M3U8 [content], resolving relative URLs against [baseUrl].
HlsPlaylist parseHlsPlaylist(String content, String baseUrl) {
  final Uri base = Uri.parse(baseUrl);

  /// Resolves [ref] (quoted or bare) against the playlist URL.
  String resolve(String ref) {
    final String trimmed = _unquote(ref.trim());
    return base.resolve(trimmed).toString();
  }

  final List<HlsVariant> variants = <HlsVariant>[];
  final List<String> segments = <String>[];
  String? initSegment;
  bool isEncrypted = false;
  bool hasEndlist = false;
  double targetDuration = 0;
  bool expectVariantUri = false;
  int pendingBandwidth = 0;
  String? pendingResolution;
  String? pendingCodecs;
  bool expectSegmentUri = false;

  final List<String> lines = content.split(RegExp(r'\r?\n'));
  for (final String rawLine in lines) {
    final String line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line == '#EXT-X-ENDLIST') {
      hasEndlist = true;
      continue;
    }
    if (line.startsWith('#EXT-X-KEY')) {
      isEncrypted = true;
      continue;
    }
    if (line.startsWith('#EXT-X-MAP:')) {
      final String? uri = _attributeValue(line, 'URI');
      if (uri != null && uri.isNotEmpty) {
        initSegment = resolve(uri);
      }
      continue;
    }
    if (line.startsWith('#EXT-X-TARGETDURATION:')) {
      final String value =
          line.substring('#EXT-X-TARGETDURATION:'.length).trim();
      targetDuration = double.tryParse(value) ?? 0;
      continue;
    }
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      final String attrs = line.substring('#EXT-X-STREAM-INF:'.length);
      pendingBandwidth = int.tryParse(_attributeValue(attrs, 'BANDWIDTH') ?? '') ?? 0;
      pendingResolution = _attributeValue(attrs, 'RESOLUTION');
      pendingCodecs = _attributeValue(attrs, 'CODECS');
      expectVariantUri = true;
      continue;
    }
    if (line.startsWith('#EXTINF')) {
      expectSegmentUri = true;
      continue;
    }
    if (line.startsWith('#')) {
      continue;
    }
    if (expectVariantUri) {
      variants.add(
        HlsVariant(
          url: resolve(line),
          bandwidth: pendingBandwidth,
          resolution: pendingResolution,
          codecs: pendingCodecs,
        ),
      );
      expectVariantUri = false;
      pendingBandwidth = 0;
      pendingResolution = null;
      pendingCodecs = null;
      continue;
    }
    if (expectSegmentUri) {
      segments.add(resolve(line));
      expectSegmentUri = false;
      continue;
    }
  }

  final bool isMaster = variants.isNotEmpty;
  // Master playlists also lack EXT-X-ENDLIST; liveness only applies
  // to media playlists.
  final bool isLive = !isMaster && !hasEndlist;

  return HlsPlaylist(
    isMaster: isMaster,
    isLive: isLive,
    isEncrypted: isEncrypted,
    variants: List<HlsVariant>.unmodifiable(variants),
    segments: List<String>.unmodifiable(segments),
    initSegment: initSegment,
    targetDuration: targetDuration,
  );
}

/// Reads a (possibly quoted) attribute value from a tag attribute list.
String? _attributeValue(String attributeList, String name) {
  // Matches NAME="quoted" or NAME=bare (up to next comma).
  final RegExp pattern = RegExp('$name=("([^"]*)"|([^,]*))');
  final RegExpMatch? match = pattern.firstMatch(attributeList);
  if (match == null) {
    return null;
  }
  final String? quoted = match.group(2);
  if (quoted != null) {
    return quoted;
  }
  return match.group(3)?.trim();
}

/// Strips one pair of surrounding double quotes, if present.
String _unquote(String value) {
  if (value.length >= 2 &&
      value.startsWith('"') &&
      value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}
