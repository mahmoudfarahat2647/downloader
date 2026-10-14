import 'dart:async';
import 'dart:convert';

import 'package:downloader/domain/detect_video_use_case.dart';
import 'package:downloader/domain/download_request.dart';
import 'package:downloader/domain/download_video_use_case.dart';
import 'package:downloader/domain/i_receive_share_gateway.dart';
import 'package:downloader/domain/i_video_detector.dart';
import 'package:downloader/domain/video_url_matcher.dart';
import 'package:downloader/presentation/widgets/address_bar.dart';
import 'package:downloader/presentation/widgets/animated_download_fab.dart';
import 'package:downloader/presentation/widgets/download_progress_bar.dart';
import 'package:downloader/presentation/widgets/manual_url_dialog.dart';
import 'package:downloader/presentation/widgets/video_picker_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Single-screen in-app browser with best-effort video detection + download.
///
/// Follows Clean Architecture: depends only on domain abstractions
/// ([IVideoDetector], [DetectVideoUseCase], [DownloadVideoUseCase],
/// [IReceiveShareGateway]) injected via the constructor.
class BrowserPage extends StatefulWidget {
  const BrowserPage({
    super.key,
    required this.detector,
    required this.detectUseCase,
    required this.downloadUseCase,
    required this.receiveShareGateway,
  });

  /// Abstraction for detecting video candidates from web events.
  final IVideoDetector detector;

  /// Domain use case filtering genuine downloadable videos.
  final DetectVideoUseCase detectUseCase;

  /// Domain use case executing downloads and saving to storage.
  final DownloadVideoUseCase downloadUseCase;

  /// Gateway that surfaces URLs shared into the app from external apps.
  final IReceiveShareGateway receiveShareGateway;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  InAppWebViewController? _webCtrl;
  final TextEditingController _urlCtrl =
      TextEditingController(text: 'https://www.google.com');

  /// Detected video candidates keyed by URL for O(1) update on enrichment.
  final Map<String, DownloadRequest> _candidateMap = {};

  /// Ordered list for stable rendering in the bottom-sheet.
  final List<String> _candidateOrder = [];

  StreamSubscription<DownloadRequest>? _detectSub;
  StreamSubscription<String>? _shareSub;
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

    // Subscribe to detected videos (initial emission + enrichment re-emissions).
    _detectSub = widget.detectUseCase.videos.listen(_onVideoDetected);

    // Subscribe to URLs shared from external apps (YouTube, browsers, etc.).
    _shareSub =
        widget.receiveShareGateway.incomingUrls.listen(_onSharedUrlReceived);
  }

  @override
  void dispose() {
    _detectSub?.cancel();
    _detectSub = null;
    _shareSub?.cancel();
    _shareSub = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    _urlCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Event handlers
  // ---------------------------------------------------------------------------

  void _onVideoDetected(DownloadRequest req) {
    if (!mounted) return;
    setState(() {
      final bool isNew = !_candidateMap.containsKey(req.url);
      _candidateMap[req.url] = req;
      if (isNew) {
        _candidateOrder.add(req.url);
      }
      // If not new, the map value is updated in-place so the bottom-sheet
      // picks up the enriched data on next open/rebuild.
    });
  }

  void _onSharedUrlReceived(String url) {
    if (!mounted) return;
    _urlCtrl.text = url;
    _loadUrl(url);
  }

  // ---------------------------------------------------------------------------
  // Navigation helpers
  // ---------------------------------------------------------------------------

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
        _webCtrl?.loadUrl(urlRequest: URLRequest(url: WebUri(normalized)))
            ?? Future<void>.value(),
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

  // ---------------------------------------------------------------------------
  // DOM scan — parses rich objects from videoScanJs
  // ---------------------------------------------------------------------------

  Future<void> _runDomScan() async {
    final InAppWebViewController? ctrl = _webCtrl;
    final String? script = widget.detector.pageScanScript;
    if (ctrl == null || script == null) return;
    try {
      final dynamic result = await ctrl.evaluateJavascript(source: script);
      final List<dynamic>? items = _parseJsonList(result);
      if (items == null) return;

      for (final dynamic item in items) {
        // The new JS returns objects; the old plain-string format is still
        // supported as a safe fallback.
        if (item is Map<dynamic, dynamic> || item is Map<String, dynamic>) {
          final Map<dynamic, dynamic> obj = item as Map<dynamic, dynamic>;
          final String url = (obj['url'] ?? '').toString();
          if (url.isEmpty || url == 'null') continue;
          final String rawTitle = (obj['title'] ?? '').toString().trim();
          final String rawQl = (obj['ql'] ?? '').toString().trim();
          widget.detector.handleUrl(
            url,
            source: 'dom-scan',
            title: rawTitle.isEmpty ? null : rawTitle,
            qualityLabel: rawQl.isEmpty ? null : rawQl,
          );
        } else {
          // Legacy fallback: plain URL string.
          final String u = item.toString();
          if (u.isEmpty || u == 'null') continue;
          widget.detector.handleUrl(u, source: 'dom-scan');
        }
      }
    } catch (_) {}
  }

  List<dynamic>? _parseJsonList(dynamic result) {
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

  // ---------------------------------------------------------------------------
  // Manual paste
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Video picker bottom-sheet
  // ---------------------------------------------------------------------------

  void _showCandidates() {
    if (_candidateMap.isEmpty) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (BuildContext sheetContext) {
          return SafeArea(
            child: DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder:
                  (BuildContext ctx, ScrollController scrollCtrl) {
                // Take a snapshot of candidates at sheet-open time.
                final List<DownloadRequest> candidates = _candidateOrder
                    .map((url) => _candidateMap[url])
                    .whereType<DownloadRequest>()
                    .toList();

                return Column(
                  children: <Widget>[
                    // Handle bar
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(sheetContext)
                              .colorScheme
                              .outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Header row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Videos found (${candidates.length})',
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .titleSmall,
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
                    // Candidate list
                    Expanded(
                      child: ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: candidates.length,
                        itemBuilder: (BuildContext _, int index) {
                          final DownloadRequest req = candidates[index];
                          return VideoPickerTile(
                            request: req,
                            onDownload: () {
                              Navigator.of(sheetContext).pop();
                              unawaited(_startDownload(req));
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------------

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
            _candidateMap.remove(req.url);
            _candidateOrder.remove(req.url);
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            AddressBar(
              controller: _urlCtrl,
              onBack: () => unawaited(_webCtrl?.goBack() ?? Future<void>.value()),
              onForward: () => unawaited(_webCtrl?.goForward() ?? Future<void>.value()),
              onReload: () => unawaited(_webCtrl?.reload() ?? Future<void>.value()),
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
                    if (url != null && currentUrl == url.toString()) {
                      final String? hookScript =
                          widget.detector.networkHookScript;
                      if (hookScript != null) {
                        await controller.evaluateJavascript(
                            source: hookScript);
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
            visible: _candidateMap.isNotEmpty && !_downloading,
            count: _candidateMap.length,
            onPressed: _showCandidates,
          ),
        ],
      ),
    );
  }
}
