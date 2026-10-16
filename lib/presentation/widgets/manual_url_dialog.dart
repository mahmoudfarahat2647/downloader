import 'package:flutter/material.dart';

/// Dialog for manually pasting any video / page link.
///
/// Validates locally (no domain imports) by checking that the URL is a
/// non-empty http(s) URL. Callers may pass a stricter [validator].
class ManualUrlDialog {
  const ManualUrlDialog._();

  /// Returns true for non-empty http(s) URLs.
  static bool isHttpUrl(String url) {
    final String trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    final String scheme = uri.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') && uri.host.isNotEmpty;
  }

  /// Shows the dialog and returns the validated URL, or null on cancel.
  ///
  /// An optional [validator] can be provided to test URL validity before
  /// closing the dialog. If null, any non-empty http(s) URL is accepted.
  static Future<String?> show(
    BuildContext context, {
    bool Function(String url)? validator,
    String? errorMessage,
  }) async {
    final TextEditingController controller = TextEditingController();
    try {
      return await showDialog<String?>(
        context: context,
        builder: (BuildContext dialogContext) {
          String? errorText;
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return AlertDialog(
                title: const Text('Paste video URL'),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: 'Paste any video / page link',
                    errorText: errorText,
                  ),
                  onSubmitted: (_) => _submit(
                    dialogContext,
                    controller,
                    setState,
                    (String? error) => errorText = error,
                    validator: validator,
                    errorMessage: errorMessage,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(null),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => _submit(
                      dialogContext,
                      controller,
                      setState,
                      (String? error) => errorText = error,
                      validator: validator,
                      errorMessage: errorMessage,
                    ),
                    child: const Text('Add'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  static void _submit(
    BuildContext dialogContext,
    TextEditingController controller,
    StateSetter setState,
    void Function(String? error) setError, {
    bool Function(String url)? validator,
    String? errorMessage,
  }) {
    final String url = controller.text.trim();
    final bool valid =
        url.isNotEmpty && (validator == null ? isHttpUrl(url) : validator(url));
    if (!valid) {
      setState(() {
        setError(errorMessage ?? 'Enter a valid http(s) link');
      });
      return;
    }
    Navigator.of(dialogContext).pop(url);
  }
}
