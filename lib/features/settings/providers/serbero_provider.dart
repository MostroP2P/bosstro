import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bosstro/features/nodes/providers/node_providers.dart';
import 'package:bosstro/features/settings/providers/language_provider.dart';

/// The Serbero npub trusted on the active node (D13), or null when none is
/// set or no node is active. Invalidate it after a change.
final serberoNpubProvider = FutureProvider.autoDispose<String?>((ref) async {
  final node = ref.watch(activeNodeProvider);
  if (node == null) return null;
  return ref.watch(settingsCoreProvider).serberoNpub(node);
});
