import 'dart:async';

import 'package:bosstro/features/settings/services/settings_core.dart';

/// [SettingsCore] in Dart: the language kept in a field.
class FakeSettingsCore implements SettingsCore {
  FakeSettingsCore({this.saved, Map<String, String>? serbero})
    : serbero = serbero ?? {};

  /// The language the core holds; null: the system's.
  String? saved;

  /// The Serbero npub trusted per node.
  final Map<String, String> serbero;

  /// Thrown by the next [setSerberoPubkey], once.
  Object? serberoError;

  /// Holds the next [setSerberoPubkey] until the test completes it.
  Completer<void>? holdSerberoWrite;

  /// Every language written, in order.
  final List<String?> writes = [];

  @override
  Future<String?> language() async => saved;

  @override
  Future<void> setLanguage(String? code) async {
    writes.add(code);
    saved = code;
  }

  @override
  Future<String?> serberoNpub(String node) async => serbero[node];

  @override
  Future<String?> setSerberoPubkey(String node, String? pubkey) async {
    final held = holdSerberoWrite;
    if (held != null) {
      holdSerberoWrite = null;
      await held.future;
    }
    final error = serberoError;
    if (error != null) {
      serberoError = null;
      throw error;
    }
    if (pubkey == null || pubkey.trim().isEmpty) {
      serbero.remove(node);
      return null;
    }
    return serbero[node] = pubkey.trim();
  }
}
