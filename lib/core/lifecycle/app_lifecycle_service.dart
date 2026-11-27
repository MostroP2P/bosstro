import 'dart:async';

import 'package:flutter/widgets.dart';

/// Turns the OS lifecycle into two calls, and nothing else. From
/// MostroP2P/app.
///
/// The process is frozen whole while the app is in the background: the relay
/// sockets die, and a dispute opened or a message sent meanwhile is only on
/// the relays. Coming back is one operation, `resync()` in Rust
/// (`rust/src/api/relays.rs`), and this observer only decides *when* it runs.
/// The work itself is [onResume], a plain async function tests call directly.
///
/// Two rules keep it from firing for nothing:
///
/// - **A latch.** Only a real `paused` (or `hidden`, which is what web and
///   desktop deliver) arms the next `resumed`. The `inactive → resumed` flap
///   of a permission dialog, a share sheet or an app-switcher peek never
///   suspended anything and is ignored.
/// - **A debounce.** A resume that flaps within [debounce] runs once, at the
///   end; the Rust side shares one pass between concurrent calls too, but
///   there is no reason to ask twice.
///
/// Every platform gets the same path: a desktop window that is never hidden
/// never arms the latch.
class AppLifecycleService with WidgetsBindingObserver {
  AppLifecycleService({
    required this.onResume,
    this.onPause,
    this.debounce = const Duration(milliseconds: 300),
  });

  /// Runs after a suspension ends. Exceptions are caught and logged: a
  /// failed resync must never take the UI down.
  final Future<void> Function() onResume;

  /// Runs when a suspension starts. Optional: on this architecture the work
  /// belongs on the resume side.
  final void Function()? onPause;

  final Duration debounce;

  bool _suspended = false;
  Timer? _pending;

  /// Whether a suspension is in progress, i.e. the next `resumed` will fire
  /// [onResume]. Exposed for tests.
  @visibleForTesting
  bool get suspended => _suspended;

  void attach() => WidgetsBinding.instance.addObserver(this);

  void detach() {
    WidgetsBinding.instance.removeObserver(this);
    _pending?.cancel();
    _pending = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (!_suspended) {
          _suspended = true;
          _pending?.cancel();
          _pending = null;
          onPause?.call();
        }
      case AppLifecycleState.resumed:
        if (!_suspended) return;
        _suspended = false;
        _pending?.cancel();
        _pending = Timer(debounce, _fireResume);
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _fireResume() {
    _pending = null;
    unawaited(
      onResume().catchError((Object e, StackTrace st) {
        debugPrint('[lifecycle] resume handler failed: $e\n$st');
      }),
    );
  }
}
