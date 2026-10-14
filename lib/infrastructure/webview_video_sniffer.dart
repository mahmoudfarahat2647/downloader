import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:downloader/domain/download_request.dart';
import 'package:downloader/domain/i_video_detector.dart';
import 'package:downloader/domain/video_url_matcher.dart';

/// Best-effort video URL detector fed by WebView interception hooks and JS.
///
/// The presentation layer forwards candidate URLs from
/// `shouldInterceptRequest`, `onLoadResource`, the fetch/XHR hook
/// ([fetchHookJs]) and the DOM scan ([videoScanJs]) into [handleUrl].
/// Deduplication is handled here so hooks can fire freely.
class WebViewVideoSniffer implements IVideoDetector {
  final StreamController<DownloadRequest> _controller =
      StreamController<DownloadRequest>.broadcast();
  final Set<String> _seen = {};

  @override
  Stream<DownloadRequest> get detectedVideos => _controller.stream;

  /// Evaluates [url] and emits a [DownloadRequest] when it looks like a
  /// downloadable video. Returns true when a request was emitted.
  @override
  bool handleUrl(
    String url, {
    Map<String, String>? headers,
    String? contentType,
    String source = 'intercept',
  }) {
    final String trimmed = url.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final String lower = trimmed.toLowerCase();
    if (lower.startsWith('blob:') || lower.startsWith('data:')) {
      return false;
    }

    final String key = VideoUrlMatcher.normalizeForDedup(trimmed);
    if (_seen.contains(key)) {
      return false;
    }
    _seen.add(key);

    if (_controller.isClosed) {
      return false;
    }
    _controller.add(DownloadRequest(
      url: trimmed,
      suggestedFileName: VideoUrlMatcher.suggestFileName(trimmed),
      detectedAt: DateTime.now(),
      headers: headers,
    ));
    return true;
  }

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

  /// Manual URL entry fallback. Never throws; unrecognized URLs are ignored.
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

  /// Wraps `fetch` and `XMLHttpRequest.open` to report requested URLs back
  /// through the `videoHit` JS handler.
  static const String fetchHookJs = r'''
(function(){try{
function hit(u){try{if(typeof u==='string'&&u){window.flutter_inappwebview.callHandler('videoHit',u);}}catch(e){}}
if(window.fetch){var of=window.fetch;window.fetch=function(){try{var a=arguments[0];hit(typeof a==='string'?a:(a&&a.url)||'');}catch(e){}return of.apply(this,arguments);};}
var oo=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){try{hit(u);}catch(e){}return oo.apply(this,arguments);};
}catch(e){}})();
''';

  /// Collects `<video>`/`<source>` URLs plus anchor hrefs that look like
  /// direct video files. Returns a JSON array string.
  static const String videoScanJs = r'''
(function(){try{
var out=[];
function push(u){if(typeof u==='string'&&u&&out.indexOf(u)<0){out.push(u);}}
var vs=document.querySelectorAll('video');for(var i=0;i<vs.length;i++){push(vs[i].currentSrc);push(vs[i].src);}
var ss=document.querySelectorAll('source');for(var j=0;j<ss.length;j++){push(ss[j].src);}
var as=document.querySelectorAll('a[href]');for(var k=0;k<as.length;k++){var h=as[k].href||'';if(/\.(mp4|webm)(\?|#|$)/i.test(h)){push(h);}}
return JSON.stringify(out);
}catch(e){return '[]';}})();
''';
}
