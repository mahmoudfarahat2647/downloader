/// Contract for receiving URLs shared into the app from external sources.
///
/// When a user presses "Share" on a video in YouTube, a social-media app, or
/// a browser, Android delivers the URL via an [ACTION_SEND] intent. This
/// gateway converts that OS mechanism into a simple [Stream] that the
/// presentation layer can subscribe to.
abstract class IReceiveShareGateway {
  /// Emits URLs that were shared into the app from other apps.
  ///
  /// Both cold-start shares (app was not running) and hot-start shares (app
  /// was already in the foreground or background) must be covered.
  Stream<String> get incomingUrls;

  /// Releases resources (closes the stream controller, cancels subscriptions).
  void dispose();
}
