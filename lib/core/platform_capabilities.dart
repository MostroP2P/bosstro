import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// What the device can do for the key screens and for notifications. Android
/// is the target the app is built for (A2); Linux and web run it for
/// development and as a convenience, without the Android-only protections.
///
/// Each check takes `isWeb` and `platform` rather than reading them, because
/// `kIsWeb` is a compile-time constant: a test could otherwise never reach
/// the web branch. Callers use the getters below.
abstract final class PlatformCapabilities {
  /// Scanning a QR code with the camera. `mobile_scanner` has no Linux
  /// implementation, and on web the key is pasted, as in MostroP2P/app
  /// (`qrInputFor`).
  static bool scanQrOn(bool isWeb, TargetPlatform platform) =>
      !isWeb && platform == TargetPlatform.android;

  /// Copying a secret key. Only Android copies it protected: marked
  /// sensitive and cleared after a minute (`MainActivity.kt`). Elsewhere the
  /// clipboard would keep the key, and desktop clipboard managers record
  /// their history, so the key is written down instead.
  static bool copySecretOn(bool isWeb, TargetPlatform platform) =>
      !isWeb && platform == TargetPlatform.android;

  /// Push notifications of a new dispute. Only Android has what they need:
  /// Firebase Cloud Messaging set up for this app, the notification channel
  /// (`MainActivity.kt`) and the texts Android shows (`strings.xml`). Where
  /// this is false nothing loads Firebase, and nothing offers notifications.
  ///
  /// True says the build can, not that the device can: Firebase needs Google
  /// Play Services, which this does not look for. A phone without them never
  /// gets a token, and whoever offers notifications has to handle that.
  static bool canPushOn(bool isWeb, TargetPlatform platform) =>
      !isWeb && platform == TargetPlatform.android;

  static bool get scanQr => scanQrOn(kIsWeb, defaultTargetPlatform);

  static bool get copySecret => copySecretOn(kIsWeb, defaultTargetPlatform);

  static bool get canPush => canPushOn(kIsWeb, defaultTargetPlatform);
}
