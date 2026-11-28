import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// The device side of push notifications: what only the OS and Google's
/// messaging service can do. Behind an interface so tests run without them.
///
/// Nothing here may be called before the solver turned notifications on:
/// every method starts Firebase in Dart, and asking for a token is what
/// first tells Google about this install.
abstract class PushMessaging {
  /// Ask the OS for permission to show notifications (Android 13+; granted
  /// without asking below it). Whether it is granted.
  Future<bool> requestPermission();

  /// Whether the OS lets the app show notifications now, without asking.
  /// The solver can take the permission away later, in the system's
  /// settings.
  Future<bool> permissionGranted();

  /// The device's token, asking Google for one if there is none yet. Throws,
  /// or never answers, on a device without Google Play Services or without a
  /// connection.
  Future<String?> getToken();

  /// Delete the device's token: Google stops delivering to it.
  Future<void> deleteToken();

  /// Whether Firebase keeps the token fresh by itself from now on. Off in
  /// the manifest; the choice made here outlives a restart.
  Future<void> setAutoInit(bool enabled);

  /// Every token that replaces the device's.
  Stream<String> tokenRefreshes();

  /// One event each time the solver taps a new-dispute notification while
  /// the app is in the background. A tap that starts the app is not one:
  /// the app starts on the pending disputes anyway.
  Stream<void> newDisputeTaps();
}

/// `data.type` of the push server's new-dispute push.
const newDisputePushType = 'dispute_new';

/// firebase_messaging 17 deprecates `getToken`, `deleteToken` and
/// `onTokenRefresh` for `register` / `onRegistered`, which hand out a
/// Firebase Installation ID instead of a registration token. The push server
/// sends to registration tokens, and checks a new one with FCM before it
/// stores it, so the token calls are the ones used here. The plugin is
/// pinned (`pubspec.yaml`); a version without them needs the server to take
/// installation ids first.
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging();

  Future<FirebaseApp>? _app;

  /// Firebase's Dart side, started at the first use. The options come from
  /// `android/app/google-services.json`.
  Future<FirebaseMessaging> _messaging() async {
    final app = _app ??= Firebase.initializeApp();
    try {
      await app;
    } catch (_) {
      // Not kept: a start that failed once would fail every call until the
      // app is restarted. The next call starts it again.
      if (identical(_app, app)) _app = null;
      rethrow;
    }
    return FirebaseMessaging.instance;
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await (await _messaging()).requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  @override
  Future<bool> permissionGranted() async {
    final settings = await (await _messaging()).getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  @override
  // ignore: deprecated_member_use, see the class.
  Future<String?> getToken() async => (await _messaging()).getToken();

  @override
  // ignore: deprecated_member_use, see the class.
  Future<void> deleteToken() async => (await _messaging()).deleteToken();

  @override
  Future<void> setAutoInit(bool enabled) async =>
      (await _messaging()).setAutoInitEnabled(enabled);

  @override
  Stream<void> newDisputeTaps() async* {
    await _messaging();
    yield* FirebaseMessaging.onMessageOpenedApp
        .where((message) => message.data['type'] == newDisputePushType)
        .map<void>((_) {});
  }

  @override
  Stream<String> tokenRefreshes() async* {
    // ignore: deprecated_member_use, see the class.
    yield* (await _messaging()).onTokenRefresh;
  }
}
