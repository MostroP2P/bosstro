import 'package:bosstro/src/rust/api/push.dart' as push_api;

export 'package:bosstro/src/rust/api/push.dart' show PushWatchStatus;

/// The Rust side of push notifications (`rust/src/api/push.rs`): the switch,
/// the token and the watch on the push server. Behind an interface so tests
/// run without the bridge.
abstract class PushCore {
  /// Whether the solver turned notifications on.
  Future<bool> enabled();

  /// Turn them on or off and bring the push server in step.
  Future<push_api.PushWatchStatus> setEnabled(bool enabled);

  /// Keep the device's token, or forget it with null, and bring the push
  /// server in step. Throws `InvalidToken` for what cannot be a token.
  Future<push_api.PushWatchStatus> setToken(String? token);

  /// Make the push server agree with what should be watched now.
  Future<push_api.PushWatchStatus> reconcile();
}

class RustPushCore implements PushCore {
  const RustPushCore();

  @override
  Future<bool> enabled() => push_api.pushEnabled();

  @override
  Future<push_api.PushWatchStatus> setEnabled(bool enabled) =>
      push_api.setPushEnabled(enabled: enabled);

  @override
  Future<push_api.PushWatchStatus> setToken(String? token) =>
      push_api.setPushToken(token: token);

  @override
  Future<push_api.PushWatchStatus> reconcile() => push_api.reconcilePush();
}
