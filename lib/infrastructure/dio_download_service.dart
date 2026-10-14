import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:downloader/domain/download_request.dart';
import 'package:downloader/domain/i_file_downloader.dart';
import 'webview_cookie_bridge.dart';

/// Downloads video files to a temporary path via Dio.
///
/// Session cookies are forwarded from the WebView so protected URLs keep
/// working. The [onComplete] callback receives a TEMP path; persisting it
/// into Downloads is the job of the storage gateway.
class DioDownloadService implements IFileDownloader {
  DioDownloadService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  CancelToken? _cancelToken;

  /// Files smaller than this are assumed to be error pages, not videos.
  static const int _minFileSizeBytes = 100 * 1024;

  @override
  Future<void> download(
    DownloadRequest request, {
    required void Function(double) onProgress,
    required void Function(String tempPath) onComplete,
    required void Function(String) onError,
  }) async {
    if (kIsWeb) {
      onError('File downloads are intended for Android (preview mode in Edge)');
      return;
    }
    _cancelToken = CancelToken();
    final CancelToken token = _cancelToken!;

    final Map<String, String> headers = <String, String>{
      ...?request.headers,
      ...await WebViewCookieBridge.buildHeaders(request.url),
    };

    final Directory tempDir = await getTemporaryDirectory();
    final String tempPath =
        '${tempDir.path}/vd_${DateTime.now().millisecondsSinceEpoch}.tmp';

    try {
      await _dio.download(
        request.url,
        tempPath,
        cancelToken: token,
        options: Options(
          headers: headers,
          followRedirects: true,
          // Note: no responseType — Dio's download() forces a stream
          // internally and pipes it to the file.
        ),
        onReceiveProgress: (int received, int total) {
          onProgress(total > 0 ? received / total : 0.0);
        },
      );

      final File file = File(tempPath);
      if (!await file.exists()) {
        onError('Download failed — file not created');
        return;
      }
      if (await file.length() < _minFileSizeBytes) {
        await _deleteQuietly(tempPath);
        onError('File too small (< 100KB) — likely an error or tracking page');
        return;
      }
      onComplete(tempPath);
    } on DioException catch (e) {
      await _deleteQuietly(tempPath);
      if (e.type == DioExceptionType.cancel) {
        onError('Download cancelled');
      } else {
        final int? statusCode = e.response?.statusCode;
        final String detail = e.message ?? e.toString();
        onError(statusCode == null
            ? 'Download failed — $detail'
            : 'Download failed (HTTP $statusCode) — $detail');
      }
    } catch (e) {
      await _deleteQuietly(tempPath);
      onError('Download failed — $e');
    }
  }

  @override
  void cancel() {
    _cancelToken?.cancel();
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final File file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort temp cleanup; failures are safe to ignore.
    }
  }
}
