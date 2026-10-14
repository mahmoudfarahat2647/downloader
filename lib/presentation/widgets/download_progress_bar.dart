import 'package:flutter/material.dart';

/// Thin bottom progress bar for an in-progress download.
///
/// Returns a [SizedBox.shrink] when [visible] is false.
class DownloadProgressBar extends StatelessWidget {
  /// Creates a download progress bar.
  const DownloadProgressBar({
    super.key,
    required this.visible,
    required this.progress,
    required this.fileName,
    required this.onCancel,
  });

  /// Whether the bar should be shown.
  final bool visible;

  /// Download progress in the range 0..1.
  final double progress;

  /// Name of the file being downloaded.
  final String fileName;

  /// Called when the cancel button is pressed.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${(progress * 100).toStringAsFixed(0)}%'),
              IconButton(
                icon: const Icon(Icons.cancel),
                tooltip: 'Cancel download',
                onPressed: onCancel,
              ),
            ],
          ),
          LinearProgressIndicator(value: progress),
        ],
      ),
    );
  }
}
