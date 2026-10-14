/// Contract for persisting a downloaded temp file.
///
/// Implementations move/copy [tempFilePath] into a user-visible downloads
/// location under [fileName] and return the final saved path.
abstract class IStorageGateway {
  /// Saves the temp file at [tempFilePath] as [fileName] in downloads.
  ///
  /// Returns the final saved file path.
  Future<String> saveToDownloads(String tempFilePath, String fileName);
}
