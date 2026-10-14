import 'package:flutter/material.dart';

import 'package:downloader/domain/detect_video_use_case.dart';
import 'package:downloader/domain/download_video_use_case.dart';
import 'package:downloader/domain/i_receive_share_gateway.dart';
import 'package:downloader/infrastructure/dio_download_service.dart';
import 'package:downloader/infrastructure/media_store_gateway.dart';
import 'package:downloader/infrastructure/receive_share_gateway.dart';
import 'package:downloader/infrastructure/webview_video_sniffer.dart';
import 'package:downloader/presentation/browser_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Composition root: wire concrete infrastructure to domain use cases.
  final WebViewVideoSniffer sniffer = WebViewVideoSniffer();
  final DetectVideoUseCase detectUseCase = DetectVideoUseCase(sniffer);
  final DownloadVideoUseCase downloadUseCase = DownloadVideoUseCase(
    DioDownloadService(),
    MediaStoreGateway(),
  );
  final ReceiveShareGateway receiveShareGateway = ReceiveShareGateway();

  runApp(VideoDownloaderApp(
    detector: sniffer,
    detectUseCase: detectUseCase,
    downloadUseCase: downloadUseCase,
    receiveShareGateway: receiveShareGateway,
  ));
}

class VideoDownloaderApp extends StatefulWidget {
  const VideoDownloaderApp({
    super.key,
    required this.detector,
    required this.detectUseCase,
    required this.downloadUseCase,
    required this.receiveShareGateway,
  });

  final WebViewVideoSniffer detector;
  final DetectVideoUseCase detectUseCase;
  final DownloadVideoUseCase downloadUseCase;
  final IReceiveShareGateway receiveShareGateway;

  @override
  State<VideoDownloaderApp> createState() => _VideoDownloaderAppState();
}

class _VideoDownloaderAppState extends State<VideoDownloaderApp> {
  @override
  void dispose() {
    widget.receiveShareGateway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Downloader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: BrowserPage(
        detector: widget.detector,
        detectUseCase: widget.detectUseCase,
        downloadUseCase: widget.downloadUseCase,
        receiveShareGateway: widget.receiveShareGateway,
      ),
    );
  }
}
