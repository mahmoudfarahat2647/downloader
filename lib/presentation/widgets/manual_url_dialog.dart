import 'package:flutter/material.dart';

/// Dialog for manually pasting a direct video URL.
///
/// Validates locally (no domain imports) by checking that the URL path
/// ends with `.mp4` or `.webm`, ignoring query parameters.
class ManualUrlDialog {
  const ManualUrlDialog._();

  /// Shows the dialog and returns the validated URL, or null on cancel.
  ///
  /// An optional [validator] can be provided to test URL validity before
  /// closing the dialog. If null, any non-empty input is accepted.
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
                    hintText: '.mp4 / .webm link',
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
    final bool valid = url.isNotEmpty && (validator == null || validator(url));
    if (!valid) {
      setState(() {
        setError(errorMessage ?? 'Enter a direct .mp4 or .webm link');
      });
      return;
    }
    Navigator.of(dialogContext).pop(url);
  }
}
