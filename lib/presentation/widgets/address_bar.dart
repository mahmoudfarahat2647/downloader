import 'package:flutter/material.dart';

/// Compact single-line browser address bar.
///
/// Shows back / forward / reload controls, a URL text field, and a
/// "Go" action that submits the current [controller] text.
class AddressBar extends StatelessWidget {
  /// Creates a compact browser address bar.
  const AddressBar({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onSubmitted,
    required this.canGoBack,
    required this.canGoForward,
  });

  /// Text controller for the URL field.
  final TextEditingController controller;

  /// Called when the back button is pressed.
  final VoidCallback onBack;

  /// Called when the forward button is pressed.
  final VoidCallback onForward;

  /// Called when the reload button is pressed.
  final VoidCallback onReload;

  /// Called with the URL text on submit or "Go" press.
  final ValueChanged<String> onSubmitted;

  /// Whether backward navigation is available.
  final bool canGoBack;

  /// Whether forward navigation is available.
  final bool canGoForward;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: canGoBack ? onBack : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward),
              tooltip: 'Forward',
              onPressed: canGoForward ? onForward : null,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload',
              onPressed: onReload,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Enter URL…',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                maxLines: 1,
                onSubmitted: onSubmitted,
              ),
            ),
            TextButton(
              onPressed: () => onSubmitted(controller.text),
              child: const Text('Go'),
            ),
          ],
        ),
      ),
    );
  }
}
