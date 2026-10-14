import 'package:flutter/material.dart';

/// Floating action button that scales in/out when [visible] changes.
///
/// Shows a [Badge] with [count] when more than one video is available,
/// and forwards [onPressed] to the inner [FloatingActionButton].
class AnimatedDownloadFab extends StatefulWidget {
  /// Creates an animated download FAB.
  const AnimatedDownloadFab({
    super.key,
    required this.visible,
    required this.count,
    required this.onPressed,
  });

  /// Whether the FAB should be visible (scaled in).
  final bool visible;

  /// Number of downloadable videos; shown as a badge when greater than 1.
  final int count;

  /// Called when the FAB is pressed.
  final VoidCallback onPressed;

  @override
  State<AnimatedDownloadFab> createState() => _AnimatedDownloadFabState();
}

class _AnimatedDownloadFabState extends State<AnimatedDownloadFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: widget.visible ? 1.0 : 0.0,
    );
    _scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
  }

  @override
  void didUpdateWidget(AnimatedDownloadFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Badge(
        label: Text('${widget.count}'),
        isLabelVisible: widget.count > 1,
        child: FloatingActionButton(
          onPressed: widget.onPressed,
          child: const Icon(Icons.download),
        ),
      ),
    );
  }
}
