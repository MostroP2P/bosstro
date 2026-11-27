import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bosstro/core/platform_capabilities.dart';
import 'package:bosstro/features/notifications/services/push_core.dart';
import 'package:bosstro/features/notifications/services/push_messaging.dart';

/// Whether this build can receive pushes at all (Android only). Where it is
/// false nothing here touches Firebase or the push server.
final canPushProvider = Provider<bool>((ref) => PlatformCapabilities.canPush);

final pushCoreProvider = Provider<PushCore>((ref) => const RustPushCore());

final pushMessagingProvider = Provider<PushMessaging>(
  (ref) => FirebasePushMessaging(),
);

/// Counts the taps on a new-dispute notification made while the app was in
/// the background. The app listens and opens the pending disputes
/// (`lib/core/app.dart`); the number itself means nothing.
final newDisputeTapsProvider = StateProvider<int>((ref) => 0);

/// The notifications of new disputes, as Settings shows them.
@immutable
class PushState {
  const PushState({this.enabled = false, this.status});

  /// The solver turned them on.
  final bool enabled;

  /// Where the watch on the push server stands; null until first read, and
  /// when it could not be read.
  final PushWatchStatus? status;

  @override
  bool operator ==(Object other) =>
      other is PushState && other.enabled == enabled && other.status == status;

  @override
  int get hashCode => Object.hash(enabled, status);

  @override
  String toString() => 'PushState(enabled: $enabled, status: $status)';
}

/// How turning notifications on went.
enum PushEnableResult {
  /// On: the token is with the core, which asked the push server.
  enabled,

  /// The solver, or the OS, refused the permission to show notifications.
  /// Nothing was asked from Google.
  permissionDenied,

  /// No token: the device has no Google Play Services, or no connection.
  /// Notifications stay off.
  unavailable,
}

final pushControllerProvider = NotifierProvider<PushController, PushState>(
  PushController.new,
);

/// Turns the notifications of new disputes on and off, and keeps the core
/// told of the device's token.
///
/// **Nothing reaches Google until the solver accepts**: while notifications
/// are off no method here calls [PushMessaging], so Firebase is not started
/// in Dart and no token is asked for. Turning them off deletes the token.
///
/// The token is never logged.
class PushController extends Notifier<PushState> {
  /// How long Google has to answer with a token. A device without Google
  /// Play Services may never answer.
  static const tokenTimeout = Duration(seconds: 20);

  PushCore get _core => ref.read(pushCoreProvider);
  PushMessaging get _messaging => ref.read(pushMessagingProvider);
  bool get _canPush => ref.read(canPushProvider);

  StreamSubscription<String>? _refreshes;
  StreamSubscription<void>? _taps;

  /// One operation at a time: a toggle tapped twice, or a resume in the
  /// middle of one, must not interleave their steps.
  Future<void> _last = Future.value();

  @override
  PushState build() {
    ref.onDispose(() {
      _refreshes?.cancel();
      _taps?.cancel();
    });
    return const PushState();
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _last.then((_) => operation());
    _last = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// At startup: read the switch, and when it is on, hand the core the
  /// device's token and follow its changes. When it is off the core is only
  /// asked to reconcile (an unwatch may still be owed).
  Future<void> start() => _serial(() async {
    if (!_canPush) return;
    try {
      final enabled = await _core.enabled();
      if (!enabled) {
        state = PushState(status: await _core.reconcile());
        return;
      }
      _followRefreshes();
      final token = await _token();
      state = PushState(
        enabled: true,
        // No token this time (no connection): the core works with the one
        // it kept.
        status:
            token != null
                ? await _core.setToken(token)
                : await _core.reconcile(),
      );
    } catch (e) {
      debugPrint('[push] not started: ${e.runtimeType}');
    }
  });

  /// Whether to offer notifications now: where they can be received, at
  /// most once per install, and never while they are on.
  Future<bool> takeOffer() => _serial(() async {
    if (!_canPush) return false;
    try {
      return await _core.takeOffer();
    } catch (e) {
      debugPrint('[push] offer not read: ${e.runtimeType}');
      return false;
    }
  });

  /// The solver accepts: ask for the permission, then for a token, and hand
  /// it to the core. In that order: a refused permission asks Google for
  /// nothing.
  Future<PushEnableResult> enable() => _serial(() async {
    if (!_canPush) return PushEnableResult.unavailable;
    try {
      if (!await _messaging.requestPermission()) {
        return PushEnableResult.permissionDenied;
      }
      // With the manifest's default Firebase would not keep the token
      // fresh by itself.
      await _messaging.setAutoInit(true);
    } catch (e) {
      debugPrint('[push] not enabled: ${e.runtimeType}');
      return PushEnableResult.unavailable;
    }
    final token = await _token();
    if (token == null) {
      await _quietly(() => _messaging.setAutoInit(false));
      return PushEnableResult.unavailable;
    }
    try {
      await _core.setToken(token);
      state = PushState(enabled: true, status: await _core.setEnabled(true));
    } catch (e) {
      debugPrint('[push] not enabled: ${e.runtimeType}');
      await _quietly(() => _messaging.setAutoInit(false));
      return PushEnableResult.unavailable;
    }
    _followRefreshes();
    return PushEnableResult.enabled;
  });

  /// The solver turns them off: the push server is told first, while the
  /// token still names this device, and then the token is deleted.
  Future<void> disable() => _serial(() async {
    if (!_canPush) return;
    PushWatchStatus? status;
    try {
      status = await _core.setEnabled(false);
    } catch (e) {
      debugPrint('[push] not disabled in the core: ${e.runtimeType}');
      return;
    }
    // Not awaited: nothing here depends on the cancellation having ended.
    unawaited(_refreshes?.cancel());
    _refreshes = null;
    unawaited(_taps?.cancel());
    _taps = null;
    await _quietly(_messaging.deleteToken);
    await _quietly(() => _messaging.setAutoInit(false));
    try {
      status = await _core.setToken(null);
    } catch (e) {
      debugPrint('[push] token not forgotten: ${e.runtimeType}');
    }
    state = PushState(status: status);
  });

  /// The node, the key or the time changed: have the core bring the push
  /// server in step.
  Future<void> reconcile() => _serial(() async {
    if (!_canPush) return;
    try {
      state = PushState(
        enabled: state.enabled,
        status: await _core.reconcile(),
      );
    } catch (e) {
      debugPrint('[push] not reconciled: ${e.runtimeType}');
    }
  });

  /// Follow what the device says while notifications are on: a token that
  /// replaces the device's, and a tap on a notification.
  void _followRefreshes() {
    _taps ??= _messaging.newDisputeTaps().listen(
      (_) => ref.read(newDisputeTapsProvider.notifier).state++,
      onError: (Object e) {
        debugPrint('[push] taps not followed: ${e.runtimeType}');
      },
    );
    _refreshes ??= _messaging.tokenRefreshes().listen(
      (token) => _serial(() async {
        if (!state.enabled) return;
        try {
          state = PushState(enabled: true, status: await _core.setToken(token));
        } catch (e) {
          debugPrint('[push] new token not kept: ${e.runtimeType}');
        }
      }),
      onError: (Object e) {
        debugPrint('[push] token changes not followed: ${e.runtimeType}');
      },
    );
  }

  /// The device's token, or null when Google gave none in time.
  Future<String?> _token() async {
    try {
      final token = await _messaging.getToken().timeout(tokenTimeout);
      return (token == null || token.isEmpty) ? null : token;
    } catch (e) {
      debugPrint('[push] no token: ${e.runtimeType}');
      return null;
    }
  }

  Future<void> _quietly(Future<void> Function() step) async {
    try {
      await step();
    } catch (e) {
      debugPrint('[push] cleanup step failed: ${e.runtimeType}');
    }
  }
}
