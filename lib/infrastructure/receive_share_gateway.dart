import 'dart:async';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:downloader/domain/i_receive_share_gateway.dart';

/// Adapts `receive_sharing_intent` to the [IReceiveShareGateway] contract.
///
/// Handles both:
///  - **Cold start**: app was launched via an ACTION_SEND intent (e.g. user
///    pressed Share in YouTube while the app was not running).
///  - **Hot resume**: app was already running when the intent arrived.
///
/// Filters out non-URL payloads; only `http://` and `https://` strings are
/// forwarded on [incomingUrls].
class ReceiveShareGateway implements IReceiveShareGateway {
  ReceiveShareGateway() {
    // Hot-resume: intent arrives while app is already in foreground/background.
    _liveSub = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_handleFiles, onError: (_) {});

    // Cold-start: intent that launched the app.
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then(_handleFiles, onError: (_) {});
  }

  final StreamController<String> _ctrl =
      StreamController<String>.broadcast();

  StreamSubscription<List<SharedMediaFile>>? _liveSub;

  @override
  Stream<String> get incomingUrls => _ctrl.stream;

  void _handleFiles(List<SharedMediaFile> files) {
    for (final SharedMediaFile file in files) {
      final String candidate = file.path.trim();
      if (candidate.startsWith('http://') ||
          candidate.startsWith('https://')) {
        if (!_ctrl.isClosed) {
          _ctrl.add(candidate);
        }
      }
    }
    // Acknowledge consumption so the plugin does not re-deliver on next resume.
    ReceiveSharingIntent.instance.reset();
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _liveSub = null;
    if (!_ctrl.isClosed) {
      _ctrl.close();
    }
  }
}
