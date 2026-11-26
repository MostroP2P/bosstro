import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bosstro/l10n/app_localizations.dart';

/// The new-dispute push is shown by Android itself, from the string resources
/// the push server names (`title_loc_key`, `body_loc_key`): no Dart runs. So
/// its text lives in `android/app/src/main/res/values*/strings.xml`, the one
/// place user-facing copy is kept outside the ARB files. The ARB entries stay
/// the source, and this keeps the two equal in every language the app ships.
const _resources = {
  'push_dispute_new_title': 'pushDisputeNewTitle',
  'push_dispute_new_body': 'pushDisputeNewBody',
  'push_disputes_channel_name': 'pushDisputesChannelName',
};

const _res = 'android/app/src/main/res';

/// The strings of one `strings.xml`, by name, as Android reads them.
Map<String, String> _androidStrings(File file) {
  final entry = RegExp(r'<string name="([^"]+)">(.*?)</string>', dotAll: true);
  return {
    for (final m in entry.allMatches(file.readAsStringSync()))
      m.group(1)!: _unescape(m.group(2)!),
  };
}

/// Android's escapes, then XML's.
String _unescape(String value) => value
    .replaceAll(r"\'", "'")
    .replaceAll(r'\"', '"')
    .replaceAll(r'\\', r'\')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

Map<String, dynamic> _arb(String language) =>
    jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
        as Map<String, dynamic>;

/// English is Android's default (`values/`), as it is the ARB template.
File _stringsFile(String language) =>
    File('$_res/values${language == 'en' ? '' : '-$language'}/strings.xml');

void main() {
  final languages = [
    for (final locale in AppLocalizations.supportedLocales) locale.languageCode,
  ];

  test('every language of the app has the push strings Android shows', () {
    for (final language in languages) {
      final file = _stringsFile(language);
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing');

      final android = _androidStrings(file);
      final arb = _arb(language);
      expect(
        android.keys.toSet(),
        _resources.keys.toSet(),
        reason: '${file.path} must hold the push strings and nothing else',
      );
      for (final MapEntry(key: resource, value: arbKey) in _resources.entries) {
        expect(
          android[resource],
          arb[arbKey],
          reason: '$resource in ${file.path} differs from $arbKey',
        );
        expect(android[resource], isNotEmpty, reason: '$resource ($language)');
      }
    }
  });

  test('no language has push strings the app does not ship', () {
    final shipped = {
      for (final language in languages) _stringsFile(language).path,
    };
    final found = {
      for (final dir in Directory(_res).listSync().whereType<Directory>())
        if (File('${dir.path}/strings.xml').existsSync())
          '${dir.path}/strings.xml',
    };
    expect(found, shipped);
  });

  // Nothing in the app refers to the title and the body: the push server
  // names them. A release build removes such resources unless told to keep
  // them, and the notification then shows empty.
  test('a release build is told to keep every push string', () {
    final keep = File('$_res/raw/keep.xml').readAsStringSync();
    for (final resource in _resources.keys) {
      expect(keep, contains('@string/$resource'), reason: resource);
    }
  });

  test('an apostrophe is escaped, or Android drops it', () {
    for (final language in languages) {
      final raw = _stringsFile(language).readAsStringSync();
      final values = RegExp(
        r'<string name="[^"]+">(.*?)</string>',
        dotAll: true,
      ).allMatches(raw).map((m) => m.group(1)!);
      for (final value in values) {
        expect(
          RegExp(r"(?<!\\)'").hasMatch(value),
          isFalse,
          reason: "an unescaped ' in $language: $value",
        );
      }
    }
  });
}
