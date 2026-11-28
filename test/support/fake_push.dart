import 'dart:async';

import 'package:bosstro/features/notifications/services/push_core.dart';
import 'package:bosstro/features/notifications/services/push_messaging.dart';

/// Everything asked of the device and of the core, in order, in one list:
/// the order between the two is what the tests check.
class PushCalls {
  final log = <String>[];
}

class FakePushMessaging implements PushMessaging {
  FakePushMessaging(this.calls);

  final PushCalls calls;
  bool permission = true;
  String? token = 'token-1';
  Object? tokenError;
  bool tokenNeverAnswers = false;
  final refreshes = StreamController<String>.broadcast();

  /// A tap on a new-dispute notification. Following them is not in the
  /// log: [tapsFollowed] says it.
  final taps = StreamController<void>.broadcast();
  bool tapsFollowed = false;

  @override
  Stream<void> newDisputeTaps() {
    tapsFollowed = true;
    return taps.stream;
  }

  @override
  Future<bool> requestPermission() async {
    calls.log.add('requestPermission');
    return permission;
  }

  /// Not in the log, as following the taps: it asks nothing of Google.
  @override
  Future<bool> permissionGranted() async => permission;

  /// When set, the token request answers when the test says, not at once.
  Completer<String?>? tokenLater;

  @override
  Future<String?> getToken() {
    calls.log.add('getToken');
    if (tokenLater case final later?) return later.future;
    if (tokenNeverAnswers) return Completer<String?>().future;
    if (tokenError != null) return Future.error(tokenError!);
    return Future.value(token);
  }

  @override
  Future<void> deleteToken() async => calls.log.add('deleteToken');

  @override
  Future<void> setAutoInit(bool enabled) async =>
      calls.log.add('setAutoInit($enabled)');

  @override
  Stream<String> tokenRefreshes() {
    calls.log.add('tokenRefreshes');
    return refreshes.stream;
  }
}

class FakePushCore implements PushCore {
  FakePushCore(this.calls, {this.isEnabled = false});

  final PushCalls calls;
  bool isEnabled;

  /// Whether the offer was already made.
  bool offered = false;
  PushWatchStatus registered = PushWatchStatus.registered;

  PushWatchStatus get _status => isEnabled ? registered : PushWatchStatus.off;

  @override
  Future<bool> enabled() async {
    calls.log.add('core.enabled');
    return isEnabled;
  }

  @override
  Future<PushWatchStatus> setEnabled(bool enabled) async {
    calls.log.add('core.setEnabled($enabled)');
    isEnabled = enabled;
    return _status;
  }

  /// When set, keeping a token fails with it. Forgetting one still works.
  Object? setTokenError;

  @override
  Future<PushWatchStatus> setToken(String? token) async {
    calls.log.add('core.setToken($token)');
    if (token != null && setTokenError != null) throw setTokenError!;
    return _status;
  }

  @override
  Future<bool> takeOffer() async {
    calls.log.add('core.takeOffer');
    if (offered) return false;
    offered = true;
    return !isEnabled;
  }

  @override
  Future<PushWatchStatus> reconcile() async {
    calls.log.add('core.reconcile');
    return _status;
  }
}
