import 'package:bosstro/src/rust/api/serbero.dart' as serbero_api;
import 'package:bosstro/src/rust/api/settings.dart' as settings_api;

/// The app's settings the Rust core keeps (`rust/src/api/settings.rs`,
/// `rust/src/api/serbero.rs`). An interface so widget tests, which run
/// without the native library, drive a fake.
abstract interface class SettingsCore {
  /// The language chosen for the app, or null to follow the system's.
  Future<String?> language();

  /// Keep [code] as the app's language, or follow the system's with null.
  Future<void> setLanguage(String? code);

  /// The Serbero pubkey trusted on [node], as an npub, or null when none is
  /// set (D13).
  Future<String?> serberoNpub(String node);

  /// Trust [pubkey] (npub or hex) as Serbero on [node], or none with null.
  /// Completes with the trusted npub. Throws a core marker
  /// (`InvalidPubkey`, `PrivateKeyNotAllowed`, `SerberoIsNode`, …).
  Future<String?> setSerberoPubkey(String node, String? pubkey);
}

class RustSettingsCore implements SettingsCore {
  const RustSettingsCore();

  @override
  Future<String?> language() => settings_api.getLanguage();

  @override
  Future<void> setLanguage(String? code) =>
      settings_api.setLanguage(code: code);

  @override
  Future<String?> serberoNpub(String node) =>
      serbero_api.getSerberoNpub(node: node);

  @override
  Future<String?> setSerberoPubkey(String node, String? pubkey) =>
      serbero_api.setSerberoPubkey(node: node, pubkey: pubkey);
}
