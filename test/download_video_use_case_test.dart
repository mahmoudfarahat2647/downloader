import 'package:downloader/domain/download_request.dart';
import 'package:downloader/domain/download_video_use_case.dart';
import 'package:downloader/domain/i_file_downloader.dart';
import 'package:downloader/domain/i_hls_downloader.dart';
import 'package:downloader/domain/i_storage_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

/// HLS downloader double that completes immediately with a fixed temp path.
class _FakeHlsDownloader implements IHlsDownloader {
  _FakeHlsDownloader({required this.tempPath, this.error});

  final String tempPath;
  final String? error;
  bool cancelled = false;

  @override
  Future<void> download({
    required String playlistUrl,
    required Map<String, String> headers,
    required void Function(double) onProgress,
    required void Function(String savedPath) onComplete,
    required void Function(String error) onError,
    Object? cancelToken,
  }) async {
    if (error != null) {
      onError(error!);
      return;
    }
    onProgress(1.0);
    onComplete(tempPath);
  }

  @override
  void cancel() => cancelled = true;
}

/// Direct downloader double that completes with a fixed temp path.
class _FakeDownloader implements IFileDownloader {
  _FakeDownloader({required this.tempPath});

  final String tempPath;

  @override
  Future<void> download(
    DownloadRequest request, {
    required void Function(double) onProgress,
    required void Function(String tempPath) onComplete,
    required void Function(String error) onError,
  }) async {
    onProgress(1.0);
    onComplete(tempPath);
  }

  @override
  void cancel() {}
}

/// Storage double recording what the use case tried to persist.
class _RecordingStorage implements IStorageGateway {
  String? savedTempPath;
  String? savedFileName;
  String? failMessage;

  @override
  Future<String> saveToDownloads(String tempFilePath, String fileName) async {
    if (failMessage != null) throw StateError(failMessage!);
    savedTempPath = tempFilePath;
    savedFileName = fileName;
    return '/Download/$fileName';
  }
}

DownloadRequest _hlsRequest({String suggestedFileName = 'stream.mp4'}) =>
    DownloadRequest(
      url: 'https://cdn.example.com/stream.m3u8',
      suggestedFileName: suggestedFileName,
      detectedAt: DateTime(2026, 1, 1),
      kind: VideoKind.hls,
    );

/// Runs [useCase.execute] and drains the notifier microtasks so the save step
/// (which the use case performs inside a callback) has settled.
Future<void> _run(
  DownloadVideoUseCase useCase,
  DownloadRequest request, {
  void Function(String)? onComplete,
  void Function(String)? onError,
}) async {
  await useCase.execute(
    request,
    onProgress: (_) {},
    onComplete: onComplete ?? (_) {},
    onError: onError ?? (_) {},
  );
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('DownloadVideoUseCase HLS routing', () {
    test('aligns the saved name with the MPEG-TS container', () async {
      final _RecordingStorage storage = _RecordingStorage();
      final DownloadVideoUseCase useCase = DownloadVideoUseCase(
        _FakeDownloader(tempPath: '/tmp/unused.tmp'),
        storage,
        hlsDownloader: _FakeHlsDownloader(tempPath: '/tmp/vd_hls_1.ts'),
      );

      String? saved;
      String? failed;
      await _run(
        useCase,
        _hlsRequest(),
        onComplete: (String p) => saved = p,
        onError: (String e) => failed = e,
      );

      expect(failed, isNull);
      expect(storage.savedTempPath, '/tmp/vd_hls_1.ts');
      expect(storage.savedFileName, 'stream.ts');
      expect(saved, '/Download/stream.ts');
    });

    test('keeps .mp4 for an fMP4 container', () async {
      final _RecordingStorage storage = _RecordingStorage();
      final DownloadVideoUseCase useCase = DownloadVideoUseCase(
        _FakeDownloader(tempPath: '/tmp/unused.tmp'),
        storage,
        hlsDownloader: _FakeHlsDownloader(tempPath: '/tmp/vd_hls_2.mp4'),
      );

      await _run(useCase, _hlsRequest());

      expect(storage.savedFileName, 'stream.mp4');
    });

    test('strips a leftover manifest extension in the suggestion', () async {
      final _RecordingStorage storage = _RecordingStorage();
      final DownloadVideoUseCase useCase = DownloadVideoUseCase(
        _FakeDownloader(tempPath: '/tmp/unused.tmp'),
        storage,
        hlsDownloader: _FakeHlsDownloader(tempPath: '/tmp/vd_hls_3.ts'),
      );

      await _run(useCase, _hlsRequest(suggestedFileName: 'stream.m3u8.mp4'));

      expect(storage.savedFileName, 'stream.ts');
    });

    test('fails fast when no HLS downloader is injected', () async {
      final DownloadVideoUseCase useCase = DownloadVideoUseCase(
        _FakeDownloader(tempPath: '/tmp/unused.tmp'),
        _RecordingStorage(),
      );

      String? failed;
      await _run(useCase, _hlsRequest(), onError: (String e) => failed = e);

      expect(failed, 'Stream download unavailable');
    });

    test('surfaces HLS downloader errors', () async {
      final _RecordingStorage storage = _RecordingStorage();
      final DownloadVideoUseCase useCase = DownloadVideoUseCase(
        _FakeDownloader(tempPath: '/tmp/unused.tmp'),
        storage,
        hlsDownloader: _FakeHlsDownloader(
          tempPath: '/tmp/vd_hls_4.ts',
          error: 'Live stream — only completed videos can be downloaded',
        ),
      );

      String? failed;
      await _run(useCase, _hlsRequest(), onError: (String e) => failed = e);

      expect(failed, 'Live stream — only completed videos can be downloaded');
      expect(storage.savedFileName, isNull);
    });
  });

  group('DownloadVideoUseCase direct routing', () {
    test('saves the direct request under its suggested name', () async {
      final _RecordingStorage storage = _RecordingStorage();
      final DownloadVideoUseCase useCase = DownloadVideoUseCase(
        _FakeDownloader(tempPath: '/tmp/vd_1.tmp'),
        storage,
      );

      final DownloadRequest request = DownloadRequest(
        url: 'https://cdn.example.com/clip.mov',
        suggestedFileName: 'clip.mov',
        detectedAt: DateTime(2026, 1, 1),
        kind: VideoKind.direct,
      );

      String? saved;
      await _run(useCase, request, onComplete: (String p) => saved = p);

      expect(storage.savedFileName, 'clip.mov');
      expect(saved, '/Download/clip.mov');
    });

    test('unresolved placeholders fail fast without downloading', () async {
      final _RecordingStorage storage = _RecordingStorage();
      final DownloadVideoUseCase useCase = DownloadVideoUseCase(
        _FakeDownloader(tempPath: '/tmp/vd_2.tmp'),
        storage,
      );

      final DownloadRequest request = DownloadRequest(
        url: 'blob:https://example.com/uuid',
        suggestedFileName: 'video.mp4',
        detectedAt: DateTime(2026, 1, 1),
        kind: VideoKind.blob,
        needsResolve: true,
      );

      String? failed;
      await _run(useCase, request, onError: (String e) => failed = e);

      expect(failed, 'Stream is still resolving...');
      expect(storage.savedFileName, isNull);
    });

    test('reports a save failure without claiming completion', () async {
      final _RecordingStorage storage = _RecordingStorage()
        ..failMessage = 'disk full';
      final DownloadVideoUseCase useCase = DownloadVideoUseCase(
        _FakeDownloader(tempPath: '/tmp/vd_3.tmp'),
        storage,
      );

      final DownloadRequest request = DownloadRequest(
        url: 'https://cdn.example.com/clip.mp4',
        suggestedFileName: 'clip.mp4',
        detectedAt: DateTime(2026, 1, 1),
        kind: VideoKind.direct,
      );

      String? failed;
      String? saved;
      await _run(
        useCase,
        request,
        onComplete: (String p) => saved = p,
        onError: (String e) => failed = e,
      );

      expect(saved, isNull);
      expect(failed, startsWith('Save failed:'));
    });
  });
}
