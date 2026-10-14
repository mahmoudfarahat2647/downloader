import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:downloader/domain/download_request.dart';
import 'package:downloader/domain/i_video_detector.dart';
import 'package:downloader/domain/video_url_matcher.dart';

/// Best-effort video URL detector fed by WebView interception hooks and JS.
///
/// The presentation layer forwards candidate URLs from
/// `shouldInterceptRequest`, `onLoadResource`, the fetch/XHR hook
/// ([fetchHookJs]) and the DOM scan ([videoScanJs]) into [handleUrl].
///
/// ### Deduplication + metadata enrichment
/// Instead of a plain [Set] that silently discards re-submissions, we keep a
/// [Map] keyed by the normalised URL. When [handleUrl] is called for an
/// already-known URL *with* richer metadata (title / contentLength /
/// qualityLabel), the entry is **merged** and an updated [DownloadRequest] is
/// re-emitted so the UI can refresh.
class WebViewVideoSniffer implements IVideoDetector {
  WebViewVideoSniffer({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  final StreamController<DownloadRequest> _controller =
      StreamController<DownloadRequest>.broadcast();

  /// Keyed by normalised URL → current best-known [DownloadRequest].
  final Map<String, DownloadRequest> _knownRequests = {};

  @override
  Stream<DownloadRequest> get detectedVideos => _controller.stream;

  // ---------------------------------------------------------------------------
  // handleUrl — core entry point
  // ---------------------------------------------------------------------------

  /// Evaluates [url] and emits (or enriches) a [DownloadRequest].
  ///
  /// Returns `true` when a request was emitted or updated.
  @override
  bool handleUrl(
    String url, {
    Map<String, String>? headers,
    String? contentType,
    String source = 'intercept',
    String? title,
    int? contentLength,
    String? qualityLabel,
  }) {
    final String trimmed = url.trim();
    if (trimmed.isEmpty) return false;

    final String lower = trimmed.toLowerCase();
    if (lower.startsWith('blob:') || lower.startsWith('data:')) return false;

    final String key = VideoUrlMatcher.normalizeForDedup(trimmed);

    if (_controller.isClosed) return false;

    final DownloadRequest? existing = _knownRequests[key];

    if (existing == null) {
      // ── New URL ────────────────────────────────────────────────────────────
      final DownloadRequest req = DownloadRequest(
        url: trimmed,
        suggestedFileName: VideoUrlMatcher.suggestFileName(trimmed),
        detectedAt: DateTime.now(),
        headers: headers,
        title: _nonEmpty(title),
        contentLength: contentLength,
        qualityLabel: _nonEmpty(qualityLabel),
      );
      _knownRequests[key] = req;
      _controller.add(req);

      // Fire a background HEAD request to fill in contentLength if missing.
      if (req.contentLength == null) {
        _fetchMetadataInBackground(key, trimmed, headers);
      }
      return true;
    }

    // ── Known URL — attempt metadata enrichment ────────────────────────────
    final bool hasNewTitle =
        _nonEmpty(title) != null && existing.title == null;
    final bool hasNewLength =
        contentLength != null && existing.contentLength == null;
    final bool hasNewQuality =
        _nonEmpty(qualityLabel) != null && existing.qualityLabel == null;

    if (!hasNewTitle && !hasNewLength && !hasNewQuality) {
      return false; // Nothing new to add.
    }

    final DownloadRequest enriched = existing.copyWith(
      title: hasNewTitle ? _nonEmpty(title) : null,
      contentLength: hasNewLength ? contentLength : null,
      qualityLabel: hasNewQuality ? _nonEmpty(qualityLabel) : null,
    );
    _knownRequests[key] = enriched;
    _controller.add(enriched);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Background HEAD fetch
  // ---------------------------------------------------------------------------

  /// Fires a lightweight HEAD request to obtain `content-length` from the
  /// server. On success, calls [handleUrl] with just the [contentLength] to
  /// trigger a merge. Failures are silently swallowed — this is best-effort.
  void _fetchMetadataInBackground(
    String key,
    String url,
    Map<String, String>? headers,
  ) {
    unawaited(_headRequest(key, url, headers));
  }

  Future<void> _headRequest(
    String key,
    String url,
    Map<String, String>? headers,
  ) async {
    try {
      final Response<dynamic> response = await _dio.head<dynamic>(
        url,
        options: Options(
          headers: headers,
          followRedirects: true,
          sendTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      final String? rawLength =
          response.headers.value(Headers.contentLengthHeader);
      final int? length = rawLength != null ? int.tryParse(rawLength) : null;
      if (length != null && length > 0 && !_controller.isClosed) {
        // Re-enter handleUrl to trigger the merge path.
        handleUrl(url, contentLength: length, source: 'head');
      }
    } catch (_) {
      // Best-effort — network errors are acceptable.
    }
  }

  // ---------------------------------------------------------------------------
  // Convenience helpers
  // ---------------------------------------------------------------------------

  /// Convenience overload for call sites that already hold a [WebUri].
  bool handleWebUri(
    WebUri uri, {
    Map<String, String>? headers,
    String? contentType,
    String source = 'intercept',
  }) =>
      handleUrl(
        uri.toString(),
        headers: headers,
        contentType: contentType,
        source: source,
      );

  /// Manual URL entry fallback. Never throws; unrecognised URLs are ignored.
  @override
  void addManualUrl(String url) {
    handleUrl(url, source: 'manual');
  }

  @override
  String? get networkHookScript => fetchHookJs;

  @override
  String? get pageScanScript => videoScanJs;

  @override
  void dispose() {
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Static helpers
  // ---------------------------------------------------------------------------

  static String? _nonEmpty(String? s) {
    if (s == null) return null;
    final String t = s.trim();
    return t.isEmpty ? null : t;
  }

  /// Maps a pixel height to a standard quality label.
  static String? qualityLabelFromHeight(int height) {
    if (height <= 0) return null;
    if (height >= 1080) return '1080p';
    if (height >= 720) return '720p';
    if (height >= 480) return '480p';
    if (height >= 360) return '360p';
    if (height >= 240) return '240p';
    return '${height}p';
  }

  /// Extracts a quality label from URL patterns like "720p", "1080", etc.
  static String? qualityLabelFromUrl(String url) {
    final RegExpMatch? m =
        RegExp(r'(2160|1440|1080|720|480|360|240)p?', caseSensitive: false)
            .firstMatch(url);
    if (m == null) return null;
    final String digits = m.group(1)!;
    return '${digits}p';
  }

  // ---------------------------------------------------------------------------
  // JavaScript snippets
  // ---------------------------------------------------------------------------

  /// Wraps `fetch` and `XMLHttpRequest.open` to report requested URLs back
  /// through the `videoHit` JS handler.
  static const String fetchHookJs = r'''
(function(){try{
function hit(u){try{if(typeof u==='string'&&u){window.flutter_inappwebview.callHandler('videoHit',u);}}catch(e){}}
if(window.fetch){var of=window.fetch;window.fetch=function(){try{var a=arguments[0];hit(typeof a==='string'?a:(a&&a.url)||'');}catch(e){}return of.apply(this,arguments);};}
var oo=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){try{hit(u);}catch(e){}return oo.apply(this,arguments);};
}catch(e){}})();
''';

  /// Enhanced DOM scan that returns an array of rich objects:
  /// `{ url, title, ql }` where `ql` is the quality label resolved in
  /// priority order: `<source label/res>` attribute → URL pattern → videoHeight.
  ///
  /// Returns a JSON array string.
  static const String videoScanJs = r'''
(function(){try{
var out=[];
var seen={};
function push(obj){
  if(!obj||typeof obj.url!=='string'||!obj.url||seen[obj.url])return;
  seen[obj.url]=true;
  out.push(obj);
}
function qlFromUrl(u){
  var m=u.match(/(2160|1440|1080|720|480|360|240)p?/i);
  return m?m[1]+'p':'';
}
function qlFromSource(el){
  var lb=el.getAttribute('label')||el.getAttribute('res')||el.getAttribute('data-res')||'';
  if(lb)return lb.match(/\d+/)?lb.match(/\d+/)[0]+'p':lb;
  return '';
}
// --- <video> elements ---
var vs=document.querySelectorAll('video');
for(var i=0;i<vs.length;i++){
  var v=vs[i];
  var urls=[v.currentSrc,v.src].filter(function(u){return typeof u==='string'&&u;});
  var ptitle=v.getAttribute('title')||document.title||'';
  // Try quality from child <source> matching currentSrc first
  var ql='';
  var childSrcs=v.querySelectorAll('source');
  for(var s=0;s<childSrcs.length;s++){
    if(childSrcs[s].src&&childSrcs[s].src===v.currentSrc){
      ql=qlFromSource(childSrcs[s]);break;
    }
  }
  for(var u=0;u<urls.length;u++){
    var finalQl=ql||qlFromUrl(urls[u]);
    // videoHeight fallback (often 0 before play, but worth trying)
    if(!finalQl&&v.videoHeight>0)finalQl=v.videoHeight+'p';
    push({url:urls[u],title:ptitle,ql:finalQl});
  }
}
// --- standalone <source> tags ---
var ss=document.querySelectorAll('source[src]');
for(var j=0;j<ss.length;j++){
  var src=ss[j].src||'';
  if(!src)continue;
  var q=qlFromSource(ss[j])||qlFromUrl(src);
  push({url:src,title:document.title||'',ql:q});
}
// --- direct video anchors ---
var as=document.querySelectorAll('a[href]');
for(var k=0;k<as.length;k++){
  var h=as[k].href||'';
  if(/\.(mp4|webm)(\?|#|$)/i.test(h)){
    push({url:h,title:as[k].textContent.trim()||document.title||'',ql:qlFromUrl(h)});
  }
}
return JSON.stringify(out);
}catch(e){return '[]';}})();
''';
}
