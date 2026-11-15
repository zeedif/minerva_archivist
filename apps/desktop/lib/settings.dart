import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show ChangeNotifier, Locale;
import 'package:fluent_ui/fluent_ui.dart' show ThemeMode;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Desktop preferences, kept in the user's application data folder so that no
/// working directory or cache folder can hide them.
final class AppSettings {
  AppSettings(this.file);

  /// `settings.json` under the platform's application support folder.
  static Future<AppSettings> standard() async => AppSettings(
    File(
      p.join((await getApplicationSupportDirectory()).path, 'settings.json'),
    ),
  );

  final File file;
  Future<void> _writes = Future.value();

  /// The last cache folder that loaded, or null on first launch.
  Future<String?> cacheDir() async => switch (await _read()) {
    {'cacheDir': final String dir} when dir.isNotEmpty => dir,
    _ => null,
  };

  Future<void> setCacheDir(String dir) => setValue('cacheDir', dir);

  /// The stored value of [key], or null.
  Future<Object?> value(String key) async => (await _read())[key];

  /// Writes are queued and atomic, so the newest call always wins.
  Future<void> setValue(String key, Object? value) =>
      _writes = _writes.then((_) async {
        final values = await _read();
        if (jsonEncode(values[key]) == jsonEncode(value)) return;
        values[key] = value;
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(
          const JsonEncoder.withIndent('  ').convert(values),
          flush: true,
        );
        await temporary.rename(file.path);
      });

  Future<Map<String, Object?>> _read() async {
    try {
      if (jsonDecode(await file.readAsString())
          case final Map<String, Object?> values) {
        return values;
      }
    } on FileSystemException {
      // Missing or unreadable: start over.
    } on FormatException {
      // Corrupt: start over.
    }
    return {};
  }
}

/// The nearest `.minerva-cache` at or above [start], else one inside [start].
String findCacheDir(String start) {
  final origin = p.absolute(start);
  for (var dir = origin; ; dir = p.dirname(dir)) {
    final candidate = p.join(dir, '.minerva-cache');
    if (Directory(candidate).existsSync()) return candidate;
    if (p.dirname(dir) == dir) return p.join(origin, '.minerva-cache');
  }
}

/// The language and theme the user forced, or null and [ThemeMode.system]
/// to follow Windows.
final class AppPreferences extends ChangeNotifier {
  AppPreferences({this.settings});

  final AppSettings? settings;
  Locale? locale;
  ThemeMode theme = ThemeMode.system;

  Future<void> restore() async {
    if (await settings?.value('language') case final String code) {
      locale = Locale(code);
    }
    theme =
        ThemeMode.values.asNameMap()[await settings?.value('theme')] ?? theme;
  }

  void setLocale(Locale? value) {
    locale = value;
    notifyListeners();
    settings?.setValue('language', value?.languageCode);
  }

  void setTheme(ThemeMode value) {
    theme = value;
    notifyListeners();
    settings?.setValue('theme', value.name);
  }
}
