import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bosstro/core/lifecycle/app_lifecycle_service.dart';
import 'package:bosstro/features/nodes/providers/node_providers.dart';
import 'package:bosstro/features/notifications/providers/push_providers.dart';
import 'package:bosstro/features/solver_key/providers/solver_key_providers.dart';

/// Decides when the push watch is looked at again, and shows nothing: at
/// startup, when the app returns to the foreground, and when the active node
/// or the solver key changes. The work is [PushController]'s.
///
/// A key change is seen here once it has settled (the provider changes after
/// the key was replaced or dropped), which is why the core does not do it
/// from inside its own unload.
class PushLifecycle extends ConsumerStatefulWidget {
  const PushLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PushLifecycle> createState() => _PushLifecycleState();
}

class _PushLifecycleState extends ConsumerState<PushLifecycle> {
  late final AppLifecycleService _lifecycle = AppLifecycleService(
    onResume: () => _controller.reconcile(),
  );

  PushController get _controller => ref.read(pushControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _lifecycle.attach();
    // After the first frame: the controller sets state, which a provider
    // may not do while the tree is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.start();
    });
  }

  @override
  void dispose() {
    _lifecycle.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeNodeProvider, (previous, next) {
      if (previous != next) _controller.reconcile();
    });
    ref.listen(solverKeyProvider, (previous, next) {
      if (previous?.publicKeyHex != next?.publicKeyHex) _controller.reconcile();
    });
    return widget.child;
  }
}
