import 'dart:async';
import 'dart:convert';

import 'package:downloader/domain/detect_video_use_case.dart';
import 'package:downloader/domain/download_request.dart';
import 'package:downloader/domain/download_video_use_case.dart';
import 'package:downloader/domain/i_video_detector.dart';
import 'package:downloader/domain/video_url_matcher.dart';
import 'package:downloader/presentation/widgets/address_bar.dart';
import 'package:downloader/presentation/widgets/animated_download_fab.dart';
import 'package:downloader/presentation/widgets/download_progress_bar.dart';
import 'package:downloader/presentation/widgets/manual_url_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Single-screen in-app browser with best-effort video detection + download.
///
/// Follows Clean Architecture: depends only on domain abstractions
/// ([IVideoDetector], [DetectVideoUseCase], [DownloadVideoUseCase]) injected
/// via the constructor.
class BrowserPage extends StatefulWidget {
  const BrowserPage({
    super.key,
    required this.detector,
    required this.detectUseCase,
    required this.downloadUseCase,
  });

  /// Abstraction for detecting video candidates from web events.
  final IVideoDetector detector;

  /// Domain use case filtering genuine downloadable videos.
  final DetectVideoUseCase detectUseCase;

  /// Domain use case executing downloads and saving to storage.
  final DownloadVideoUseCase downloadUseCase;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  InAppWebViewController? _webCtrl;
  final TextEditingController _urlCtrl =
      TextEditingController(text: 'https://www.google.com');
  final List<DownloadRequest> _candidates = <DownloadRequest>[];
  StreamSubscription<DownloadRequest>? _sub;
  double _pageProgress = 0;
  double _dlProgress = 0;
  bool _downloading = false;
  String _dlName = '';
  int _dlGen = 0;
  Timer? _scanTimer;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.detectUseCase.videos.listen(_onVideoDetected);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    _urlCtrl.dispose();
    super.dispose();
  }

  void _onVideoDetected(DownloadRequest req) {
    if (!mounted) return;
    setState(() {
      // Deduplication is handled upstream by IVideoDetector
      _candidates.add(req);
    });
  }

  String _normalizeInput(String raw) {
    final String input = raw.trim();
    if (input.isEmpty) return input;
    final String lower = input.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return input;
    }
    return 'https://$input';
  }

  void _loadUrl(String value) {
    final String normalized = _normalizeInput(value);
    if (normalized.isEmpty) return;
    try {
      unawaited(
        _webCtrl?.loadUrl(urlRequest: URLRequest(url: WebUri(normalized))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid URL')),
      );
    }
  }

  Future<void> _refreshNavState(InAppWebViewController controller) async {
    try {
      final bool back = await controller.canGoBack();
      final bool forward = await controller.canGoForward();
      if (!mounted) return;
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    } catch (_) {}
  }

  void _restartScanTimer() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_runDomScan());
    });
  }

  Future<void> _runDomScan() async {
    final InAppWebViewController? ctrl = _webCtrl;
    final String? script = widget.detector.pageScanScript;
    if (ctrl == null || script == null) return;
    try {
      final dynamic result = await ctrl.evaluateJavascript(source: script);
      final List<dynamic>? urls = _parseUrlList(result);
      if (urls == null) return;
      for (final dynamic item in urls) {
        final String u = item.toString();
        if (u.isEmpty || u == 'null') continue;
        widget.detector.handleUrl(u, source: 'dom-scan');
      }
    } catch (_) {}
  }

  List<dynamic>? _parseUrlList(dynamic result) {
    try {
      if (result == null) return null;
      if (result is List) return result;
      if (result is String && result.isNotEmpty) {
        final dynamic decoded = jsonDecode(result);
        if (decoded is List) return decoded;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onManualPaste() async {
    final String? pasted = await ManualUrlDialog.show(
      context,
      validator: (url) => VideoUrlMatcher.isVideoUrl(url),
      errorMessage: 'Enter a direct .mp4 or .webm link',
    );
    if (pasted == null) return;
    final String url = pasted.trim();
    if (url.isEmpty) return;
    widget.detector.addManualUrl(url);
  }

  void _showCandidates() {
    if (_candidates.isEmpty) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        builder: (BuildContext sheetContext) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Videos found (${_candidates.length})',
                          style: Theme.of(sheetContext).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _candidates.length,
                    itemBuilder: (context, index) {
                      final DownloadRequest req = _candidates[index];
                      final String ext =
                          _extensionOf(req.suggestedFileName);
                      return ListTile(
                        title: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                req.suggestedFileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (ext.isNotEmpty) ...<Widget>[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  ext.toUpperCase(),
                                  style:
                                      Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          req.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: TextButton(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            unawaited(_startDownload(req));
                          },
                          child: const Text('Download'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _extensionOf(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  Future<void> _startDownload(DownloadRequest req) async {
    setState(() {
      _downloading = true;
      _dlProgress = 0;
      _dlName = req.suggestedFileName;
    });
    final int gen = ++_dlGen;
    try {
      await widget.downloadUseCase.execute(
        req,
        onProgress: (p) {
          if (gen == _dlGen && mounted) {
            setState(() => _dlProgress = p);
          }
        },
        onComplete: (saved) {
          if (gen != _dlGen || !mounted) return;
          setState(() {
            _downloading = false;
            _candidates.removeWhere((c) => c.url == req.url);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved: $saved')),
          );
        },
        onError: (e) {
          if (gen != _dlGen || !mounted) return;
          setState(() => _downloading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Download failed: $e'),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () => unawaited(_startDownload(req)),
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (gen != _dlGen || !mounted) return;
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  void _cancelDownload() {
    widget.downloadUseCase.cancel();
    if (!mounted) return;
    setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            AddressBar(
              controller: _urlCtrl,
              onBack: () => unawaited(_webCtrl?.goBack()),
              onForward: () => unawaited(_webCtrl?.goForward()),
              onReload: () => unawaited(_webCtrl?.reload()),
              onSubmitted: _loadUrl,
              canGoBack: _canGoBack,
              canGoForward: _canGoForward,
            ),
            if (_pageProgress < 1)
              LinearProgressIndicator(value: _pageProgress),
            Expanded(
              child: InAppWebView(
                initialUrlRequest:
                    URLRequest(url: WebUri('https://www.google.com')),
                initialSettings: InAppWebViewSettings(
                  useShouldInterceptRequest: true,
                  useOnLoadResource: true,
                  useShouldInterceptAjaxRequest: true,
                  useShouldInterceptFetchRequest: true,
                  allowsInlineMediaPlayback: true,
                  mediaPlaybackRequiresUserGesture: false,
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                ),
                onWebViewCreated: (controller) {
                  _webCtrl = controller;
                  try {
                    controller.addJavaScriptHandler(
                      handlerName: 'videoHit',
                      callback: (args) {
                        try {
                          if (args.isNotEmpty) {
                            final String url = args[0].toString();
                            if (url.isNotEmpty && url != 'null') {
                              widget.detector.handleUrl(url, source: 'js');
                            }
                          }
                        } catch (_) {}
                        return null;
                      },
                    );
                  } catch (_) {}
                },
                onUpdateVisitedHistory: (controller, url, isReload) {
                  if (url != null) {
                    _urlCtrl.text = url.toString();
                  }
                  unawaited(_refreshNavState(controller));
                },
                shouldOverrideUrlLoading:
                    (controller, navigationAction) async {
                  return NavigationActionPolicy.ALLOW;
                },
                shouldInterceptRequest: (controller, request) async {
                  try {
                    final String url = request.url.toString();
                    if (url.isNotEmpty && url != 'null') {
                      widget.detector.handleUrl(
                        url,
                        source: 'intercept',
                      );
                    }
                  } catch (_) {}
                  return null;
                },
                onLoadResource: (controller, resource) {
                  try {
                    final String? url = resource.url?.toString();
                    if (url == null || url.isEmpty || url == 'null') return;
                    widget.detector.handleUrl(url, source: 'resource');
                  } catch (_) {}
                },
                onProgressChanged: (controller, progress) {
                  if (!mounted) return;
                  setState(() => _pageProgress = progress / 100);
                },
                onLoadStop: (controller, url) async {
                  try {
                    final String? currentUrl =
                        (await controller.getUrl())?.toString();
                    // Only inject fetch hook and restart periodic scan for main page load
                    if (url != null && currentUrl == url.toString()) {
                      final String? hookScript =
                          widget.detector.networkHookScript;
                      if (hookScript != null) {
                        await controller.evaluateJavascript(source: hookScript);
                      }
                      _restartScanTimer();
                    }
                  } catch (_) {}
                },
              ),
            ),
            DownloadProgressBar(
              visible: _downloading,
              progress: _dlProgress,
              fileName: _dlName,
              onCancel: _cancelDownload,
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FloatingActionButton.small(
            heroTag: 'manualUrl',
            onPressed: () => unawaited(_onManualPaste()),
            tooltip: 'Paste video URL',
            child: const Icon(Icons.attach_file),
          ),
          const SizedBox(height: 12),
          AnimatedDownloadFab(
            visible: _candidates.isNotEmpty && !_downloading,
            count: _candidates.length,
            onPressed: _showCandidates,
          ),
        ],
      ),
    );
  }
}
