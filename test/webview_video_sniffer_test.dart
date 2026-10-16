import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:downloader/infrastructure/webview_video_sniffer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dio adapter that records every request and answers with a tiny success,
/// so tests can observe exactly which URLs trigger a background HEAD probe.
class _RecordingAdapter implements HttpClientAdapter {
  final List<String> requests = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri.toString());
    return ResponseBody.fromString(
      '',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['video/mp4'],
      },
    );
  }
}

void main() {
  group('WebViewVideoSniffer metadata probe gating', () {
    test('does not probe ordinary page assets', () async {
      final _RecordingAdapter adapter = _RecordingAdapter();
      final Dio dio = Dio()..httpClientAdapter = adapter;
      final WebViewVideoSniffer sniffer = WebViewVideoSniffer(dio: dio);

      sniffer.handleUrl('https://site.example.com/app.css');
      sniffer.handleUrl('https://site.example.com/bundle.js');
      sniffer.handleUrl('https://site.example.com/thumb.jpg');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(adapter.requests, isEmpty);
      sniffer.dispose();
    });

    test('probes extensionless delivery URLs and media URLs', () async {
      final _RecordingAdapter adapter = _RecordingAdapter();
      final Dio dio = Dio()..httpClientAdapter = adapter;
      final WebViewVideoSniffer sniffer = WebViewVideoSniffer(dio: dio);

      sniffer.handleUrl('https://video.fbcn1.fbcdn.net/v/12345?token=abc');
      sniffer.handleUrl('https://cdn.example.com/movie.mp4');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        adapter.requests,
        containsAll(<String>[
          'https://video.fbcn1.fbcdn.net/v/12345?token=abc',
          'https://cdn.example.com/movie.mp4',
        ]),
      );
      sniffer.dispose();
    });

    test('blob: placeholders are never probed over HTTP', () async {
      final _RecordingAdapter adapter = _RecordingAdapter();
      final Dio dio = Dio()..httpClientAdapter = adapter;
      final WebViewVideoSniffer sniffer = WebViewVideoSniffer(dio: dio);

      sniffer.handleUrl('blob:https://example.com/uuid');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(adapter.requests, isEmpty);
      sniffer.dispose();
    });
  });
}
