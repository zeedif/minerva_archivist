import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'controls.dart';
import 'l10n/app_localizations.dart';
import 'profile_form.dart';
import 'run_controller.dart';
import 'output.dart';
import 'settings.dart';

/// Opens the last cache folder used; [args] or the nearest `.minerva-cache`
/// only seed the first launch.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.standard();
  final cacheDir =
      await settings.cacheDir() ??
      args.firstOrNull ??
      findCacheDir(Directory.current.path);
  final controller = RunController(cacheDir, settings: settings);
  final layout = OutputLayout(settings: settings);
  final preferences = AppPreferences(settings: settings);
  await (layout.restore(), preferences.restore()).wait;
  unawaited(controller.load());
  runApp(
    MinervaApp(
      controller: controller,
      layout: layout,
      preferences: preferences,
    ),
  );
}

class MinervaApp extends StatelessWidget {
  MinervaApp({
    super.key,
    required this.controller,
    OutputLayout? layout,
    AppPreferences? preferences,
  }) : layout = layout ?? OutputLayout(),
       preferences = preferences ?? AppPreferences();

  final RunController controller;
  final OutputLayout layout;
  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => _app(),
  );

  Widget _app() => FluentApp(
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    debugShowCheckedModeBanner: false,
    locale: preferences.locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...FluentLocalizations.localizationsDelegates,
    ],
    themeMode: preferences.theme,
    theme: FluentThemeData(
      brightness: Brightness.light,
      accentColor: Colors.blue,
      visualDensity: VisualDensity.standard,
      fontFamily: 'Segoe UI Variable',
    ),
    darkTheme: FluentThemeData(
      brightness: Brightness.dark,
      accentColor: Colors.blue,
      visualDensity: VisualDensity.standard,
      fontFamily: 'Segoe UI Variable',
    ),
    home: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f12): () =>
            layout.update(() => layout.visible = !layout.visible),
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: Listenable.merge([controller, layout]),
          builder: (context, _) => _Shell(controller, layout, preferences),
        ),
      ),
    ),
  );
}

/// [problem] in the current language.
String describe(AppLocalizations l, Problem problem) => switch (problem.kind) {
  ProblemKind.unreadable => l.cannotRead(problem.subject, problem.detail),
  ProblemKind.unwritable => l.cannotSave(problem.subject, problem.detail),
  ProblemKind.invalid => l.subjectProblem(problem.subject, problem.detail),
};

class _Shell extends StatelessWidget {
  const _Shell(this.controller, this.layout, this.preferences);

  final RunController controller;
  final OutputLayout layout;
  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final l = AppLocalizations.of(context);
    final theme = FluentTheme.of(context);
    final runnable =
        !c.running && !c.loading && (c.options?.dats.isNotEmpty ?? false);
    return ColoredBox(
      color: theme.resources.solidBackgroundFillColorBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                _ProfileBar(c),
                const SizedBox(width: 16),
                Expanded(
                  child: CommandBar(
                    mainAxisAlignment: MainAxisAlignment.end,
                    overflowBehavior:
                        CommandBarOverflowBehavior.dynamicOverflow,
                    primaryItems: [
                      CommandBarButton(
                        icon: const Icon(FluentIcons.view),
                        label: Text(l.preview),
                        onPressed: runnable
                            ? () => c.start(apply: false)
                            : null,
                      ),
                      CommandBarButton(
                        icon: const Icon(FluentIcons.play),
                        label: Text(l.apply),
                        onPressed: runnable ? () => c.start(apply: true) : null,
                      ),
                      if (c.running)
                        CommandBarButton(
                          icon: const Icon(FluentIcons.stop),
                          label: Text(l.stop),
                          onPressed: c.stop,
                        ),
                      const CommandBarSeparator(),
                      CommandBarButton(
                        icon: const Icon(FluentIcons.command_prompt),
                        label: Text(
                          layout.visible ? l.hideOutput : l.showOutput,
                        ),
                        tooltip: 'F12',
                        onPressed: () => layout.update(
                          () => layout.visible = !layout.visible,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Preferences(preferences),
              ],
            ),
          ),
          for (final (title, message) in [
            if (c.cacheError case final error?)
              (l.problemCache, describe(l, error)),
            if (c.actionError case final error?)
              (l.problemProfile, describe(l, error)),
            if (c.optionsError case final error?) (l.problemSettings, error),
          ])
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: InfoBar(
                title: Text(title),
                content: Text(message),
                severity: InfoBarSeverity.error,
              ),
            ),
          SizedBox(
            height: 2,
            child: c.running || c.loading ? const ProgressBar() : null,
          ),
          Expanded(
            child: OutputHost(
              layout: layout,
              controller: c,
              content: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 4, 16),
                child: ProfileForm(
                  c,
                  footer: Section(
                    title: l.cacheFolder,
                    children: [
                      Field(help: l.cacheFolderHelp, child: _CacheField(c)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The profile name with its suggestions, and the buttons that act on it.
class _ProfileBar extends StatelessWidget {
  const _ProfileBar(this.controller);

  final RunController controller;

  Future<void> _delete(BuildContext context) async {
    final c = controller;
    final l = AppLocalizations.of(context);
    final name = c.name.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(l.deleteTitle),
        content: Text(l.deleteBody(name, p.basename(c.profilesFile.path))),
        actions: [
          Button(
            child: Text(l.cancel),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            child: Text(l.delete),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true) await c.deleteProfile();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final l = AppLocalizations.of(context);
    final idle = !c.running && c.profiles != null;
    return Row(
      spacing: 6,
      children: [
        SizedBox(width: 300, child: _ProfileBox(c, enabled: idle)),
        Button(
          onPressed: idle && c.nameExists ? c.loadProfile : null,
          child: Text(l.load),
        ),
        Button(
          onPressed: c.canSave ? c.saveProfile : null,
          child: Text(l.save),
        ),
        Button(
          onPressed: idle && c.nameExists ? () => _delete(context) : null,
          child: Text(l.delete),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: l.clearTooltip,
          child: Button(
            onPressed: c.running ? null : c.clear,
            child: Text(l.clear),
          ),
        ),
      ],
    );
  }
}

/// A text box that lists the stored profiles matching what is typed, read
/// afresh on every build so a new cache folder shows its own names at once.
class _ProfileBox extends StatefulWidget {
  const _ProfileBox(this.controller, {required this.enabled});

  final RunController controller;
  final bool enabled;

  @override
  State<_ProfileBox> createState() => _ProfileBoxState();
}

class _ProfileBoxState extends State<_ProfileBox> {
  final _focus = FocusNode();
  final _overlay = OverlayPortalController();
  final _link = LayerLink();
  int _active = -1;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      _open();
    } else {
      _overlay.hide();
    }
  }

  void _open() {
    _active = -1;
    _overlay.show();
    setState(() {});
  }

  List<String> get _matches {
    final c = widget.controller;
    final query = c.name.trim().toLowerCase();
    final names = c.profiles?.names.toList() ?? const <String>[];
    final filtered = [
      for (final name in names)
        if (name.toLowerCase().contains(query)) name,
    ];
    return c.nameExists ? names : filtered;
  }

  void _pick(String name) {
    widget.controller.rename(name);
    _overlay.hide();
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final matches = _matches;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        if (!_overlay.isShowing) _open();
        setState(() => _active = (_active + 1).clamp(0, matches.length - 1));
      case LogicalKeyboardKey.arrowUp:
        setState(() => _active = (_active - 1).clamp(0, matches.length - 1));
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter
          when _overlay.isShowing && _active >= 0 && _active < matches.length:
        _pick(matches[_active]);
      case LogicalKeyboardKey.escape when _overlay.isShowing:
        _overlay.hide();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = FluentTheme.of(context);
    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: (context) {
        final matches = _matches;
        return Positioned(
          width: 420,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(0, 4),
            child: TextFieldTapRegion(
              child: FlyoutContent(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(maxHeight: 420),
                child: matches.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          c.profiles?.names.isEmpty ?? true
                              ? AppLocalizations.of(context).noProfilesYet
                              : AppLocalizations.of(context).noProfileMatches,
                          style: theme.typography.caption,
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: matches.length,
                        itemBuilder: (context, index) {
                          final name = matches[index];
                          return ListTile.selectable(
                            selected:
                                index == _active ||
                                (_active < 0 && name == c.name.trim()),
                            title: Text(name, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              c.summary(name),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onSelectionChange: (_) => _pick(name),
                          );
                        },
                      ),
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: Focus(
          onKeyEvent: _key,
          skipTraversal: true,
          child: SyncedTextBox(
            key: const ValueKey('profile-name'),
            value: c.name,
            focusNode: _focus,
            placeholder: AppLocalizations.of(context).profileName,
            enabled: widget.enabled,
            onChanged: (text) {
              c.rename(text);
              if (!_overlay.isShowing) _open();
              setState(() => _active = -1);
            },
            onSubmitted: (_) => c.nameExists ? c.loadProfile() : null,
            suffix: IconButton(
              icon: const Icon(FluentIcons.chevron_down, size: 10),
              onPressed: widget.enabled
                  ? () => _overlay.isShowing ? _overlay.hide() : _open()
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// The cache path: typing, pasting or browsing loads a folder, but only one
/// that exists and differs from the folder already loaded.
class _CacheField extends StatefulWidget {
  const _CacheField(this.controller);

  final RunController controller;

  @override
  State<_CacheField> createState() => _CacheFieldState();
}

class _CacheFieldState extends State<_CacheField> {
  late final _text = TextEditingController(text: widget.controller.cacheDir);
  final _focus = FocusNode();
  Timer? _debounce;
  bool _missing = false;
  late String _shown = widget.controller.cacheDir;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_follow);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_follow);
    _debounce?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Shows the folder the controller settled on unless the user is typing.
  void _follow() {
    final dir = widget.controller.cacheDir;
    if (!_focus.hasFocus && _text.text != dir) {
      _text.text = dir;
      _shown = dir;
    }
  }

  void _changed(String text) {
    _debounce?.cancel();
    final target = text.trim();
    final pasted = (text.length - _shown.length).abs() > 1;
    _shown = text;
    if (target.isNotEmpty && widget.controller.isCurrent(target)) {
      setState(() => _missing = false);
      return;
    }
    _debounce = Timer(
      pasted ? Duration.zero : const Duration(milliseconds: 600),
      () => _apply(target),
    );
  }

  Future<void> _apply(String target) async {
    _debounce?.cancel();
    final c = widget.controller;
    if (target.isEmpty || c.isCurrent(target)) return;
    if (!await Directory(target).exists()) {
      if (mounted) setState(() => _missing = true);
      return;
    }
    if (mounted) setState(() => _missing = false);
    await c.load(directory: target);
  }

  Future<void> _browse() async {
    final c = widget.controller;
    final typed = _text.text.trim();
    final picked = await getDirectoryPath(
      initialDirectory: Directory(typed).existsSync() ? typed : c.cacheDir,
      confirmButtonText: AppLocalizations.of(context).useFolder,
    );
    if (picked == null || !mounted) return;
    _text.text = picked;
    _shown = picked;
    await _apply(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final l = AppLocalizations.of(context);
    final theme = FluentTheme.of(context);
    final error = _missing
        ? l.folderNotFound
        : switch (c.cacheError) {
            final problem? => describe(l, problem),
            null => null,
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextBox(
                controller: _text,
                focusNode: _focus,
                enabled: !c.running,
                placeholder: l.cachePlaceholder,
                onChanged: _changed,
                onSubmitted: (text) => _apply(text.trim()),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: l.browse,
              child: Button(
                onPressed: c.running ? null : _browse,
                child: const Icon(FluentIcons.open_folder_horizontal, size: 14),
              ),
            ),
          ],
        ),
        if (c.loading)
          const Padding(padding: EdgeInsets.only(top: 6), child: ProgressBar())
        else if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error,
              style: theme.typography.caption?.copyWith(
                color: Colors.errorPrimaryColor,
              ),
            ),
          )
        else if (c.profiles != null && !c.profilesFile.existsSync())
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l.noProfilesFile, style: theme.typography.caption),
          ),
      ],
    );
  }
}

/// Forces the language or the theme; the first choice of each follows
/// Windows.
class _Preferences extends StatelessWidget {
  const _Preferences(this.preferences);

  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final language = preferences.locale?.languageCode ?? _system;
    return Row(
      spacing: 4,
      children: [
        Tooltip(
          message: l.languageMenu,
          child: DropDownButton(
            leading: const Icon(FluentIcons.locale_language, size: 14),
            items: [
              for (final (code, label) in [
                (_system, l.languageSystem),
                ('en', 'English'),
                ('es', 'Español'),
              ])
                RadioMenuFlyoutItem<String>(
                  text: Text(label),
                  value: code,
                  groupValue: language,
                  onChanged: (code) => preferences.setLocale(
                    code == _system ? null : Locale(code),
                  ),
                ),
            ],
          ),
        ),
        Tooltip(
          message: l.themeMenu,
          child: DropDownButton(
            leading: Icon(switch (preferences.theme) {
              ThemeMode.light => FluentIcons.sunny,
              ThemeMode.dark => FluentIcons.clear_night,
              ThemeMode.system => FluentIcons.color,
            }, size: 14),
            items: [
              for (final (mode, label) in [
                (ThemeMode.system, l.themeSystem),
                (ThemeMode.light, l.themeLight),
                (ThemeMode.dark, l.themeDark),
              ])
                RadioMenuFlyoutItem<ThemeMode>(
                  text: Text(label),
                  value: mode,
                  groupValue: preferences.theme,
                  onChanged: preferences.setTheme,
                ),
            ],
          ),
        ),
      ],
    );
  }

  static const _system = 'system';
}
