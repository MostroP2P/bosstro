import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bosstro/l10n/app_localizations.dart';

/// With the app in the background or not running, the new-dispute push is
/// shown by Android itself, from the string resources the push server names
/// (`title_loc_key`, `body_loc_key`): no Dart runs. So its text lives in
/// `android/app/src/main/res/values*/strings.xml`, the one place user-facing
/// copy is kept outside the ARB files. The ARB entries stay the source, and
/// this keeps the two equal in every language the app ships.
const _resources = {
  'push_dispute_new_title': 'pushDisputeNewTitle',
  'push_dispute_new_body': 'pushDisputeNewBody',
  'push_disputes_channel_name': 'pushDisputesChannelName',
};

const _res = 'android/app/src/main/res';

/// The only shape of entry this reads: one `name`, plain text.
final _entry = RegExp(r'<string name="([^"]+)">([^<]*)</string>');

/// The escapes this knows how Android reads: its own, then XML's.
final _escape = RegExp(r'''\\['"\\]|&(?:lt|gt|amp);''');

/// What Android would not show as written: an escape this does not know, a
/// bare quote (dropped), a reference (`@`, `?`), or whitespace it collapses
/// or trims.
final _notPlain = RegExp(r'''[\\'"&>\n\r\t]|  |^[ @?]| $''');

/// The strings of a `strings.xml`, by name, as Android reads them.
///
/// It does not model all of Android's rules. It reads the plain entries the
/// push strings are, and throws on anything else rather than skip it or read
/// it differently from Android: an entry with another attribute or with
/// markup, an escape it does not know, a name given twice.
Map<String, String> _androidStrings(String xml) {
  final entries = _entry.allMatches(xml).toList();
  final opened = RegExp(r'<string\b').allMatches(xml).length;
  if (opened != entries.length) {
    throw FormatException(
      '${opened - entries.length} <string> entries are not of the form '
      '<string name="…">plain text</string>',
    );
  }
  final strings = <String, String>{};
  for (final m in entries) {
    final name = m.group(1)!;
    final raw = m.group(2)!;
    if (strings.containsKey(name)) {
      throw FormatException('$name is given twice');
    }
    // A letter stands for each known escape, so the rest is judged alone.
    if (_notPlain.hasMatch(raw.replaceAll(_escape, 'x'))) {
      throw FormatException('$name is not read by Android as written: $raw');
    }
    strings[name] = raw.replaceAllMapped(
      _escape,
      (e) => switch (e.group(0)!) {
        '&lt;' => '<',
        '&gt;' => '>',
        '&amp;' => '&',
        final escaped => escaped.substring(1),
      },
    );
  }
  return strings;
}

Map<String, dynamic> _arb(String language) =>
    jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
        as Map<String, dynamic>;

/// English is Android's default (`values/`), as it is the ARB template.
String _valuesDir(String language) =>
    'values${language == 'en' ? '' : '-$language'}';

File _stringsFile(String language) =>
    File('$_res/${_valuesDir(language)}/strings.xml');

void main() {
  final languages = [
    for (final locale in AppLocalizations.supportedLocales) locale.languageCode,
  ];

  test('every language of the app has the push strings Android shows', () {
    for (final language in languages) {
      final file = _stringsFile(language);
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing');

      final android = _androidStrings(file.readAsStringSync());
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
    // Directory names, not paths: a path's separator differs by platform.
    final shipped = {for (final language in languages) _valuesDir(language)};
    final found = {
      for (final dir in Directory(_res).listSync().whereType<Directory>())
        if (File.fromUri(dir.uri.resolve('strings.xml')).existsSync())
          dir.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
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

  test('the reader knows the escapes the push strings may use', () {
    expect(
      _androidStrings(
        r'''<string name="a">d\'un \"x\" \\ &lt;&amp;&gt;</string>''',
      ),
      {'a': r'''d'un "x" \ <&>'''},
    );
  });

  // A comparison that passed over such an entry, or read it differently from
  // Android, would call two different texts equal.
  test('the reader refuses what it does not read as Android does', () {
    const refused = {
      'another attribute': '<string name="a" translatable="false">x</string>',
      'single-quoted name': "<string name='a'>x</string>",
      'markup': '<string name="a">a <b>x</b></string>',
      'CDATA': '<string name="a"><![CDATA[x]]></string>',
      'a name given twice':
          '<string name="a">x</string><string name="a">y</string>',
      'a bare apostrophe, which Android drops':
          '<string name="a">d\'un</string>',
      'a bare quote, which Android drops': '<string name="a">"x"</string>',
      'an unknown escape': r'<string name="a">a\nb</string>',
      'an unknown entity': '<string name="a">a&apos;b</string>',
      'a line break, which Android collapses': '<string name="a">a\nb</string>',
      'two spaces, which Android collapses': '<string name="a">a  b</string>',
      'a trailing space, which Android trims': '<string name="a">a </string>',
      'a reference': '<string name="a">@string/b</string>',
    };
    for (final MapEntry(key: what, value: xml) in refused.entries) {
      expect(() => _androidStrings(xml), throwsFormatException, reason: what);
    }
  });
}
