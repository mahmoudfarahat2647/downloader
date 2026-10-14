import 'package:flutter/material.dart';

import 'package:downloader/domain/detect_video_use_case.dart';
import 'package:downloader/domain/download_video_use_case.dart';
import 'package:downloader/infrastructure/dio_download_service.dart';
import 'package:downloader/infrastructure/media_store_gateway.dart';
import 'package:downloader/infrastructure/webview_video_sniffer.dart';
import 'package:downloader/presentation/browser_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Composition root: wire concrete infrastructure to domain use cases
  final WebViewVideoSniffer sniffer = WebViewVideoSniffer();
  final DetectVideoUseCase detectUseCase = DetectVideoUseCase(sniffer);
  final DownloadVideoUseCase downloadUseCase = DownloadVideoUseCase(
    DioDownloadService(),
    MediaStoreGateway(),
  );

  runApp(VideoDownloaderApp(
    detector: sniffer,
    detectUseCase: detectUseCase,
    downloadUseCase: downloadUseCase,
  ));
}

class VideoDownloaderApp extends StatelessWidget {
  const VideoDownloaderApp({
    super.key,
    required this.detector,
    required this.detectUseCase,
    required this.downloadUseCase,
  });

  final WebViewVideoSniffer detector;
  final DetectVideoUseCase detectUseCase;
  final DownloadVideoUseCase downloadUseCase;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Downloader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: BrowserPage(
        detector: detector,
        detectUseCase: detectUseCase,
        downloadUseCase: downloadUseCase,
      ),
    );
  }
}
