import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'package:downloader/domain/i_hls_downloader.dart';

import 'hls_playlist_parser.dart';

/// Downloads unencrypted HLS VOD streams without transcoding.
///
/// Flow: GET playlist (+headers) → reject encrypted/live → resolve master
/// variant (highest `BANDWIDTH`, re-GET) → download init segment first when
/// present → download media segments (max 3 concurrent, 2 retries each) →
/// concatenate into a single file.
///
/// Container rule: fMP4 (playlist carries `EXT-X-MAP` init segment) is
/// written as `.mp4` (init bytes + segments concatenated); MPEG-TS
/// (no init segment) is written as `.ts`. No transcode is performed.
class HlsDownloadService implements IHlsDownloader {
  /// Creates a service, optionally sharing a [dio] instance (for tests).
  HlsDownloadService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  CancelToken? _cancelToken;

  /// Maximum concurrent segment downloads.
  static const int _maxConcurrency = 3;

  /// Per-segment retry attempts (in addition to the first try).
  static const int _maxRetries = 2;

  /// Downloads the HLS stream at [playlistUrl] to a temp file.
  ///
  /// [headers] are forwarded on every request (cookies/auth). Progress is
  /// reported as segments completed / total segments (0..1). [onComplete]
  /// receives the saved temp-file path. Expected failures (protected/live
  /// streams, HTTP errors, cancellation) are reported via [onError], never
  /// thrown. Pass [cancelToken] to allow the caller to cancel externally.
  @override
  Future<void> download({
    required String playlistUrl,
    required Map<String, String> headers,
    required void Function(double) onProgress,
    required void Function(String savedPath) onComplete,
    required void Function(String) onError,
    covariant CancelToken? cancelToken,
  }) async {
    final CancelToken effectiveToken = cancelToken ?? CancelToken();
    _cancelToken = effectiveToken;

    final Directory tempDir = await getTemporaryDirectory();
    final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String workDirPath = '${tempDir.path}/hls_$stamp';
    String? outputPath;

    try {
      HlsPlaylist playlist =
          await _fetchPlaylist(playlistUrl, headers, effectiveToken);

      final String? rejected = _rejectionReason(playlist);
      if (rejected != null) {
        onError(rejected);
        return;
      }

      if (playlist.isMaster) {
        final String? variantUrl = playlist.bestVariantUrl;
        if (variantUrl == null) {
          onError('No playable quality found in this stream');
          return;
        }
        playlist = await _fetchPlaylist(variantUrl, headers, effectiveToken);
        final String? variantRejected = _rejectionReason(playlist);
        if (variantRejected != null) {
          onError(variantRejected);
          return;
        }
      }

      if (playlist.segments.isEmpty) {
        onError('No playable segments found in this stream');
        return;
      }

      final bool isFmp4 = playlist.initSegment != null;
      final String extension = isFmp4 ? 'mp4' : 'ts';
      outputPath = '${tempDir.path}/vd_hls_$stamp.$extension';

      final Directory workDir = Directory(workDirPath);
      await workDir.create(recursive: true);

      int done = 0;
      final int total =
          playlist.segments.length + (playlist.initSegment != null ? 1 : 0);
      void reportProgress() {
        onProgress(total > 0 ? done / total : 0.0);
      }

      reportProgress();

      final List<String> partPaths = List<String>.filled(
        playlist.segments.length,
        '',
      );

      if (playlist.initSegment != null) {
        final String initPath = '${workDir.path}/init.part';
        await _downloadBytes(
          playlist.initSegment!,
          initPath,
          headers,
          effectiveToken,
        );
        done++;
        reportProgress();
        await _appendToOutput(initPath, outputPath, create: true);
        await _deleteQuietly(initPath);
      } else {
        await File(outputPath).create(recursive: true);
      }

      await _downloadSegments(
        playlist.segments,
        workDir.path,
        partPaths,
        headers,
        effectiveToken,
      );
      done = total - playlist.segments.length;
      for (int i = 0; i < partPaths.length; i++) {
        if (effectiveToken.isCancelled) {
          throw _cancelledException();
        }
        await _appendToOutput(partPaths[i], outputPath, create: false);
        await _deleteQuietly(partPaths[i]);
        done++;
        reportProgress();
      }

      onProgress(1.0);
      onComplete(outputPath);
    } on DioException catch (e) {
      await _deleteQuietly(outputPath);
      onError(_dioErrorMessage(e));
    } catch (e) {
      await _deleteQuietly(outputPath);
      if (e is _Cancelled) {
        onError('Download cancelled');
      } else {
        onError('Download failed — $e');
      }
    } finally {
      await _deleteQuietly(workDirPath);
    }
  }

  /// Cancels the in-flight download, if any.
  @override
  void cancel() {
    _cancelToken?.cancel();
  }

  /// Returns the fail-fast message for protected/live playlists, else null.
  String? _rejectionReason(HlsPlaylist playlist) {
    if (playlist.isEncrypted) {
      return 'Protected stream — encrypted streams cannot be downloaded';
    }
    if (playlist.isLive) {
      return 'Live stream — only completed videos can be downloaded';
    }
    return null;
  }

  Future<HlsPlaylist> _fetchPlaylist(
    String url,
    Map<String, String> headers,
    CancelToken token,
  ) async {
    final Response<String> response = await _dio.get<String>(
      url,
      cancelToken: token,
      options: Options(
        headers: headers,
        followRedirects: true,
        responseType: ResponseType.plain,
      ),
    );
    final String? body = response.data;
    if (body == null || body.isEmpty) {
      throw DioException(
        requestOptions: response.requestOptions,
        message: 'Empty playlist response',
      );
    }
    return parseHlsPlaylist(body, url);
  }

  Future<void> _downloadSegments(
    List<String> urls,
    String workDirPath,
    List<String> partPaths,
    Map<String, String> headers,
    CancelToken token,
  ) async {
    for (int start = 0; start < urls.length; start += _maxConcurrency) {
      if (token.isCancelled) {
        throw _cancelledException();
      }
      final int end = (start + _maxConcurrency).clamp(0, urls.length);
      final List<Future<void>> batch = <Future<void>>[];
      for (int i = start; i < end; i++) {
        final String partPath = '$workDirPath/seg_$i.part';
        partPaths[i] = partPath;
        batch.add(_downloadBytes(urls[i], partPath, headers, token));
      }
      await Future.wait(batch);
    }
  }

  Future<void> _downloadBytes(
    String url,
    String savePath,
    Map<String, String> headers,
    CancelToken token,
  ) async {
    DioException? lastError;
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      if (token.isCancelled) {
        throw _cancelledException();
      }
      try {
        final Response<List<int>> response = await _dio.get<List<int>>(
          url,
          cancelToken: token,
          options: Options(
            headers: headers,
            followRedirects: true,
            responseType: ResponseType.bytes,
          ),
        );
        final List<int>? data = response.data;
        if (data == null || data.isEmpty) {
          throw DioException(
            requestOptions: response.requestOptions,
            message: 'Empty segment response',
          );
        }
        await File(savePath).writeAsBytes(data, flush: true);
        return;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          rethrow;
        }
        lastError = e;
      }
    }
    throw lastError ??
        DioException(
          requestOptions: RequestOptions(path: url),
          message: 'Segment download failed',
        );
  }

  Future<void> _appendToOutput(
    String partPath,
    String outputPath, {
    required bool create,
  }) async {
    final Uint8List bytes = await File(partPath).readAsBytes();
    final File output = File(outputPath);
    if (create) {
      await output.writeAsBytes(bytes, flush: true);
    } else {
      final RandomAccessFile handle =
          await output.open(mode: FileMode.append);
      try {
        await handle.writeFrom(bytes);
        await handle.flush();
      } finally {
        await handle.close();
      }
    }
  }

  String _dioErrorMessage(DioException e) {
    if (e.type == DioExceptionType.cancel) {
      return 'Download cancelled';
    }
    final int? statusCode = e.response?.statusCode;
    final String detail = e.message ?? e.toString();
    return statusCode == null
        ? 'Download failed — $detail'
        : 'Download failed (HTTP $statusCode) — $detail';
  }

  Never _cancelledException() => throw const _Cancelled();

  static Future<void> _deleteQuietly(String? path) async {
    if (path == null || path.isEmpty) {
      return;
    }
    try {
      final File file = File(path);
      if (await file.exists()) {
        await file.delete();
      } else {
        final Directory dir = Directory(path);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    } catch (_) {
      // Best-effort temp cleanup; failures are safe to ignore.
    }
  }
}

/// Internal marker for cooperative cancellation between batches.
class _Cancelled {
  /// Creates the cancellation marker.
  const _Cancelled();
}
