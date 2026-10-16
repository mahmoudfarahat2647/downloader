import 'package:downloader/domain/download_request.dart';
import 'package:flutter/material.dart';

/// A rich list tile for the video download picker bottom-sheet.
///
/// Displays:
///  - A human-readable **title** (falls back to [DownloadRequest.suggestedFileName]).
///  - The raw URL as a truncated subtitle.
///  - A row of chips showing file size, quality label, and format badge.
///  - A **Download** button.
class VideoPickerTile extends StatelessWidget {
  const VideoPickerTile({
    super.key,
    required this.request,
    required this.onDownload,
    this.enabled = true,
    this.subtitleOverride,
  });

  final DownloadRequest request;
  final VoidCallback onDownload;

  /// Whether the tile offers a download action.
  ///
  /// Defaults to true to keep existing call sites compiling. When false,
  /// the tile is greyed out, the tap target is disabled, and the trailing
  /// action shows a waiting indicator instead of the download button.
  final bool enabled;

  /// Optional subtitle override (e.g. `'Resolving stream…'`).
  ///
  /// Defaults to null, which falls back to displaying [DownloadRequest.url].
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme texts = Theme.of(context).textTheme;

    final String displayTitle =
        (request.title != null && request.title!.isNotEmpty)
            ? request.title!
            : request.suggestedFileName;

    final String? sizeLabel = _formatSize(request.contentLength);
    final String? qualityLabel = request.qualityLabel;
    final String? formatLabel = _formatBadge(request.suggestedFileName);

    final String subtitle = subtitleOverride ?? request.url;

    final Widget card = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        elevation: 0,
        color: colors.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Video icon
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 10),
                child: Icon(Icons.ondemand_video_rounded,
                    size: 28, color: colors.primary),
              ),
              // Title + URL + chips
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: texts.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: texts.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    if (sizeLabel != null ||
                        qualityLabel != null ||
                        formatLabel != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: <Widget>[
                          if (sizeLabel != null)
                            _Chip(
                              label: sizeLabel,
                              icon: Icons.storage_rounded,
                              color: colors.tertiaryContainer,
                              textColor: colors.onTertiaryContainer,
                            ),
                          if (qualityLabel != null)
                            _Chip(
                              label: qualityLabel,
                              icon: Icons.hd_rounded,
                              color: colors.secondaryContainer,
                              textColor: colors.onSecondaryContainer,
                            ),
                          if (formatLabel != null)
                            _Chip(
                              label: formatLabel,
                              icon: Icons.videocam_rounded,
                              color: colors.primaryContainer,
                              textColor: colors.onPrimaryContainer,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Download button (or waiting indicator when disabled).
              if (enabled)
                TextButton(
                  onPressed: onDownload,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.download_rounded, size: 20),
                      SizedBox(height: 2),
                      Text('Save', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                )
              else
                const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.hourglass_top_rounded, size: 20),
                      SizedBox(height: 2),
                      Text('Wait', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!enabled) {
      return Opacity(opacity: 0.6, child: card);
    }
    return card;
  }

  // ---------------------------------------------------------------------------
  // Formatting helpers (pure – no framework dependency)
  // ---------------------------------------------------------------------------

  static String? _formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return null;
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  static String? _formatBadge(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return null;
    return fileName.substring(dot + 1).toUpperCase();
  }
}

/// A compact icon + label chip used inside [VideoPickerTile].
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.color,
    required this.textColor,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 11, color: textColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: textColor),
          ),
        ],
      ),
    );
  }
}
