import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:minerva_core/minerva_core.dart';
import 'package:minerva_desktop/main.dart';
import 'package:minerva_desktop/output.dart';
import 'package:minerva_desktop/run_controller.dart';
import 'package:minerva_desktop/settings.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('minerva_desktop_');
  });
  tearDown(() => temporary.delete(recursive: true));

  Directory cacheWith(String name, String profiles) {
    final dir = Directory(p.join(temporary.path, name))..createSync();
    File(p.join(dir.path, 'profiles.jsonc')).writeAsStringSync(profiles);
    return dir;
  }

  Future<void> pumpApp(WidgetTester tester, RunController controller) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MinervaApp(controller: controller));
    await tester.pump();
  }

  testWidgets('first launch saves a profile without a file', (tester) async {
    final controller = RunController(p.join(temporary.path, 'cache'));
    addTearDown(controller.dispose);
    await tester.runAsync(controller.load);
    expect(controller.cacheError, isNull);
    expect(controller.profilesFile.existsSync(), isFalse);
    await pumpApp(tester, controller);
    expect(find.text('Load'), findsOneWidget);
    controller
      ..rename('Handheld')
      ..edit('dat', ['Nintendo - Game Boy'])
      ..edit('root', temporary.path);
    await tester.runAsync(controller.saveProfile);
    expect(controller.nameExists, isTrue);
    expect(
      controller.profilesFile.readAsStringSync(),
      contains('"Handheld": {"dat": "Nintendo - Game Boy", "root": '),
    );
    await tester.pump();
    expect(find.text('Handheld'), findsWidgets);
  });

  test('a malformed file is reported and never overwritten', () async {
    final dir = cacheWith('broken', '{broken');
    final controller = RunController(dir.path);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.cacheError, isNotNull);
    controller.rename('New');
    await controller.saveProfile();
    expect(
      File(p.join(dir.path, 'profiles.jsonc')).readAsStringSync(),
      '{broken',
    );
  });

  test('loading the folder already loaded reads nothing', () async {
    final dir = cacheWith('cache', '{"profiles": {"A": {"dat": "X"}}}');
    final controller = RunController(dir.path);
    addTearDown(controller.dispose);
    await controller.load();
    final first = controller.profiles;
    await controller.load(directory: '${dir.path}${p.separator}');
    await controller.load(directory: p.join(dir.path, '..', 'cache'));
    expect(identical(controller.profiles, first), isTrue);
  });

  test('a later cache load wins over an earlier one', () async {
    final first = cacheWith('first', '{"profiles": {"First": {}}}');
    final second = cacheWith('second', '{"profiles": {"Second": {}}}');
    final controller = RunController(first.path);
    addTearDown(controller.dispose);
    await Future.wait([
      controller.load(),
      controller.load(directory: second.path),
    ]);
    expect(controller.cacheDir, second.path);
    expect(controller.profiles!.names, ['Second']);
  });

  test(
    'the cache folder that loaded is remembered for the next launch',
    () async {
      final dir = cacheWith('cache', '{"profiles": {}}');
      final settings = AppSettings(
        File(p.join(temporary.path, 'settings.json')),
      );
      expect(await settings.cacheDir(), isNull);
      final controller = RunController(dir.path, settings: settings);
      addTearDown(controller.dispose);
      await controller.load();
      expect(await settings.cacheDir(), dir.path);
      await controller.load(directory: p.join(temporary.path, 'missing'));
      expect(await AppSettings(settings.file).cacheDir(), dir.path);
    },
  );

  test('findCacheDir walks up to the repository cache', () {
    final cache = Directory(p.join(temporary.path, '.minerva-cache'))
      ..createSync();
    final nested = Directory(p.join(temporary.path, 'apps', 'desktop'))
      ..createSync(recursive: true);
    expect(findCacheDir(nested.path), cache.path);
  });

  testWidgets('switching cache refreshes the profile list and keeps edits', (
    tester,
  ) async {
    final first = cacheWith('first', '{"profiles": {"Old one": {}}}');
    final second = cacheWith(
      'second',
      '{"profiles": {"Real collection": {"dat": "Nintendo - Game Boy"}}}',
    );
    final controller = RunController(first.path);
    addTearDown(controller.dispose);
    await tester.runAsync(controller.load);
    await pumpApp(tester, controller);
    await tester.tap(find.byKey(const ValueKey('profile-name')));
    await tester.pump();
    expect(find.text('Old one'), findsOneWidget);
    controller
      ..rename('collection')
      ..edit('dat', ['My system']);
    await tester.runAsync(() => controller.load(directory: second.path));
    await tester.pump();
    expect(find.text('Old one'), findsNothing);
    expect(find.text('Real collection'), findsOneWidget);
    expect(controller.name, 'collection');
    expect(controller.options!.dats, ['My system']);
  });

  testWidgets('language count shows only while it is in the priority', (
    tester,
  ) async {
    final dir = cacheWith('cache', '{"profiles": {}}');
    final controller = RunController(dir.path);
    addTearDown(controller.dispose);
    await tester.runAsync(controller.load);
    await pumpApp(tester, controller);
    expect(find.text('Most languages'), findsNothing);
    controller.edit('priority', ['lang', 'langcount']);
    await tester.pump();
    expect(controller.draft['langcount'], 'most');
    expect(controller.options, isNotNull);
    expect(find.text('Most languages'), findsOneWidget);
    controller.edit('priority', ['lang']);
    await tester.pump();
    expect(controller.draft['langcount'], isNull);
    expect(find.text('Most languages'), findsNothing);
  });

  testWidgets('a typed name loads, saves and deletes like a plain preset', (
    tester,
  ) async {
    final dir = cacheWith(
      'cache',
      '{"defaults": {"layout": "extracted"},'
          ' "profiles": {"gb": {"dat": "Nintendo - Game Boy"},'
          ' "gba": {"dat": "Nintendo - Game Boy Advance"}}}',
    );
    final controller = RunController(dir.path);
    addTearDown(controller.dispose);
    await tester.runAsync(controller.load);
    await pumpApp(tester, controller);
    expect(controller.draft['layout'], 'extracted');
    await tester.tap(find.byKey(const ValueKey('profile-name')));
    await tester.pump();
    expect(find.text('gb'), findsOneWidget);
    await tester.tap(find.text('gba'));
    await tester.pump();
    expect(controller.name, 'gba');
    expect(find.text('gb'), findsNothing);
    expect(controller.draft['dat'], isEmpty);
    await tester.tap(find.text('Load'));
    await tester.pump();
    expect(controller.draft['dat'], ['Nintendo - Game Boy Advance']);
    await tester.enterText(find.byKey(const ValueKey('profile-name')), 'gb');
    await tester.pump();
    expect(controller.nameExists, isTrue);
    expect(find.text('Nintendo - Game Boy Advance'), findsWidgets);
    await tester.runAsync(controller.saveProfile);
    expect(
      (await tester.runAsync(() => Profiles.load(controller.profilesFile)))!
          .resolve('gb')
          .dats,
      ['Nintendo - Game Boy Advance'],
    );
    await tester.enterText(find.byKey(const ValueKey('profile-name')), 'nes');
    await tester.pump();
    expect(controller.nameExists, isFalse);
    await tester.tap(find.byKey(const ValueKey('profile-name')));
    await tester.pump();
    expect(find.text('No profile matches; Save creates it.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the output panel docks, floats and hides', (tester) async {
    final dir = cacheWith('cache', '{"profiles": {}}');
    final controller = RunController(dir.path);
    addTearDown(controller.dispose);
    await tester.runAsync(controller.load);
    final layout = OutputLayout();
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MinervaApp(controller: controller, layout: layout));
    await tester.pump();
    expect(find.text('Output'), findsOneWidget);
    await tester.tap(find.byTooltip('Dock to the bottom'));
    await tester.pump();
    expect(layout.dock, Dock.bottom);
    final title = tester.getCenter(find.text('Output'));
    final gesture = await tester.startGesture(title);
    await gesture.moveBy(const Offset(0, -200));
    await tester.pump();
    expect(layout.dock, Dock.floating);
    await gesture.moveBy(const Offset(300, -100));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(layout.dock, Dock.floating);
    final start = tester.getCenter(find.text('Output'));
    final toEdge = await tester.startGesture(start);
    await toEdge.moveTo(Offset(1590, start.dy));
    await tester.pump();
    await toEdge.up();
    await tester.pump();
    expect(layout.dock, Dock.right);
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();
    expect(layout.visible, isFalse);
    expect(find.text('Output'), findsNothing);
    await tester.tap(find.text('Show output'));
    await tester.pump();
    expect(layout.visible, isTrue);
    await tester.pump(const Duration(seconds: 2));
  });

  test('the output panel remembers where it was', () async {
    final settings = AppSettings(File(p.join(temporary.path, 'settings.json')));
    final layout = OutputLayout(settings: settings);
    layout.update(() {
      layout.dock = Dock.bottom;
      layout.bottom = 333;
    });
    await settings.setValue('flush', true);
    final restored = OutputLayout(settings: settings);
    await restored.restore();
    expect(restored.dock, Dock.bottom);
    expect(restored.bottom, 333);
  });

  testWidgets('priority badges reorder by dragging', (tester) async {
    final dir = cacheWith('cache', '{"profiles": {}}');
    final controller = RunController(dir.path);
    addTearDown(controller.dispose);
    await tester.runAsync(controller.load);
    await pumpApp(tester, controller);
    expect(controller.draft['priority'], ['lang', 'region', 'ra']);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('3  RetroAchievements')),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('1  Language')));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(controller.draft['priority'], ['ra', 'lang', 'region']);
    expect(controller.draft['priority'], isNot(['lang', 'region', 'ra']));
  });

  test('Clear puts back the settings the app starts with', () async {
    final dir = cacheWith(
      'cache',
      '{"defaults": {"layout": "extracted"},'
          ' "profiles": {"gb": {"dat": "Nintendo - Game Boy"}}}',
    );
    final controller = RunController(dir.path);
    addTearDown(controller.dispose);
    await controller.load();
    final start = {...controller.draft};
    controller
      ..rename('gb')
      ..loadProfile()
      ..edit('layout', 'zip');
    controller.clear();
    expect(controller.name, isEmpty);
    expect(controller.draft, start);
  });

  testWidgets('the interface follows a forced language and theme', (
    tester,
  ) async {
    final dir = cacheWith('cache', '{"profiles": {}}');
    final controller = RunController(dir.path);
    addTearDown(controller.dispose);
    await tester.runAsync(controller.load);
    final preferences = AppPreferences()..locale = const Locale('es');
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MinervaApp(controller: controller, preferences: preferences),
    );
    await tester.pump();
    expect(find.text('Cargar'), findsOneWidget);
    expect(find.text('Colección'), findsOneWidget);
    expect(find.text('Vista previa'), findsOneWidget);
    preferences.setLocale(const Locale('en'));
    preferences.setTheme(ThemeMode.dark);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Load'), findsOneWidget);
    expect(
      FluentTheme.of(tester.element(find.text('Load'))).brightness,
      Brightness.dark,
    );
  });

  test('the language and theme are remembered', () async {
    final settings = AppSettings(File(p.join(temporary.path, 'settings.json')));
    AppPreferences(settings: settings)
      ..setLocale(const Locale('es'))
      ..setTheme(ThemeMode.light);
    await settings.setValue('flush', true);
    final restored = AppPreferences(settings: settings);
    await restored.restore();
    expect(restored.locale, const Locale('es'));
    expect(restored.theme, ThemeMode.light);
  });
}
