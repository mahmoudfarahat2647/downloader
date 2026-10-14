import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:downloader/domain/i_storage_gateway.dart';

/// Persists temp downloads into the Android Downloads collection.
///
/// Android 10+ (API 29+) goes through MediaStore via a platform channel;
/// older devices fall back to a direct copy into the public Download folder.
class MediaStoreGateway implements IStorageGateway {
  static const MethodChannel _channel =
      MethodChannel('com.example.downloader/mediastore');

  static const String _legacyDownloadDir = '/storage/emulated/0/Download';

  @override
  Future<String> saveToDownloads(String tempFilePath, String fileName) async {
    if (kIsWeb || !Platform.isAndroid) {
      throw UnsupportedError('MediaStore is only supported on Android');
    }
    final String safeName = _sanitizeFileName(fileName);
    final int sdk = await _getSdkVersion();
    if (sdk >= 29) {
      try {
        return await _saveViaMediaStore(tempFilePath, safeName);
      } on PlatformException catch (e) {
        if (e.code != 'UNSUPPORTED_SDK') {
          rethrow;
        }
        // Channel host is too old — drop down to the legacy path.
      }
    }
    return _saveLegacy(tempFilePath, safeName);
  }

  static Future<int> _getSdkVersion() async {
    if (kIsWeb) return 0;
    try {
      final int? version = await _channel.invokeMethod<int>('getSdkVersion');
      return version ?? 29;
    } catch (_) {
      return 29;
    }
  }

  Future<String> _saveViaMediaStore(String tempPath, String fileName) async {
    final String? uri =
        await _channel.invokeMethod<String>('saveToDownloads', <String, Object>{
      'tempPath': tempPath,
      'fileName': fileName,
      'mimeType': _mimeTypeFor(fileName),
    });
    if (uri == null || uri.isEmpty) {
      throw PlatformException(
        code: 'SAVE_FAILED',
        message: 'MediaStore returned no URI',
      );
    }
    return uri;
  }

  Future<String> _saveLegacy(String tempPath, String fileName) async {
    final PermissionStatus status = await Permission.storage.request();
    if (!status.isGranted) {
      throw StateError('Storage permission denied');
    }
    final Directory dir = Directory(_legacyDownloadDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    String target = '${dir.path}/$fileName';
    int copyIndex = 1;
    while (await File(target).exists()) {
      target = '${dir.path}/${_withCopySuffix(fileName, copyIndex)}';
      copyIndex++;
    }
    return (await File(tempPath).copy(target)).path;
  }

  static String _mimeTypeFor(String fileName) {
    final String lower = fileName.toLowerCase();
    if (lower.endsWith('.mp4')) {
      return 'video/mp4';
    }
    if (lower.endsWith('.webm')) {
      return 'video/webm';
    }
    return 'application/octet-stream';
  }

  static String _sanitizeFileName(String fileName) {
    final String trimmed = fileName.trim();
    final String base = trimmed.isEmpty ? 'video.mp4' : trimmed;
    return base.replaceAll(RegExp('[\\/:*?"<>|]'), '_');
  }

  static String _withCopySuffix(String fileName, int n) {
    final int dot = fileName.lastIndexOf('.');
    if (dot <= 0) {
      return '$fileName ($n)';
    }
    return '${fileName.substring(0, dot)} ($n)${fileName.substring(dot)}';
  }
}
