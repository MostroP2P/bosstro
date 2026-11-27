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
}

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
    await (_app ??= Firebase.initializeApp());
    return FirebaseMessaging.instance;
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await (await _messaging()).requestPermission();
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
  Stream<String> tokenRefreshes() async* {
    // ignore: deprecated_member_use, see the class.
    yield* (await _messaging()).onTokenRefresh;
  }
}
