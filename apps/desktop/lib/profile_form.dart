import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:minerva_core/minerva_core.dart';
import 'package:path/path.dart' as p;

import 'controls.dart';
import 'run_controller.dart';

/// Every option of the draft, each limited to the values it accepts.
class ProfileForm extends StatelessWidget {
  const ProfileForm(this.controller, {super.key, this.footer});

  final RunController controller;

  /// Shown after every option.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final draft = c.draft;
    final enabled = !c.running;
    ValueChanged<T>? edit<T>(String key) =>
        enabled ? (value) => c.edit(key, value) : null;
    List<String> list(String key) => [
      for (final value in draft[key] as List? ?? const []) '$value',
    ];
    final root = draft['root'] as String?;
    final priority = list('priority');
    final wishlist = draft['wishlist'] as String?;

    final sections = [
      Section(
        title: 'Collection',
        children: [
          Field(
            label: 'Systems',
            help:
                'DATs from the cache, a .dat file or a folder of them. '
                'Several are merged into one collection.',
            child: BadgeFlow<String>(
              values: list('dat'),
              label: (dat) => dat,
              empty: 'No system yet.',
              onChanged: edit('dat'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Picker(
                    label: 'Add system',
                    custom: true,
                    choices: [
                      for (final dat in c.catalog.dats)
                        if (!list('dat').contains(dat))
                          (
                            value: dat,
                            title: dat.substring(dat.indexOf(':') + 1),
                            detail: dat.substring(0, dat.indexOf(':')),
                          ),
                    ],
                    onPicked: enabled
                        ? (dat) => c.edit('dat', [...list('dat'), dat])
                        : null,
                  ),
                  Button(
                    onPressed: enabled
                        ? () async {
                            final file = await openFile(
                              initialDirectory: c.cacheDir,
                              acceptedTypeGroups: const [
                                XTypeGroup(
                                  label: 'DAT',
                                  extensions: ['dat', 'xml'],
                                ),
                              ],
                            );
                            if (file != null) {
                              c.edit('dat', [...list('dat'), file.path]);
                            }
                          }
                        : null,
                    child: const Text('Browse .dat…'),
                  ),
                ],
              ),
            ),
          ),
          Field(
            label: 'ROM folder',
            help: 'Where the collection lives. Empty only previews the selection.',
            child: PathBox(
              value: root,
              placeholder: 'No ROM folder',
              onChanged: edit('root'),
              browse: () => getDirectoryPath(
                initialDirectory: _existing(root),
                confirmButtonText: 'Use folder',
              ),
            ),
          ),
          Field(
            label: 'Layout',
            help: 'How each game sits under the ROM folder.',
            child: ChoiceBox<String>(
              value: draft['layout'] as String? ?? Layout.zip.cli,
              choices: [
                for (final layout in Layout.values)
                  (
                    value: layout.cli,
                    title: _layoutTitles[layout]!,
                    detail: _layoutShapes[layout],
                  ),
              ],
              onChanged: edit('layout'),
            ),
          ),
          Field(
            label: 'Protected folders',
            help: 'Top-level folders under the ROM folder that are never touched.',
            child: BadgeFlow<String>(
              values: list('protect'),
              label: (folder) => folder,
              onChanged: edit('protect'),
              trailing: Picker(
                label: 'Add folder',
                custom: true,
                load: () => _folders(root, except: list('protect')),
                onPicked: enabled
                    ? (folder) =>
                          c.edit('protect', [...list('protect'), folder])
                    : null,
              ),
            ),
          ),
          Field(
            label: 'Search depth',
            help: 'How many folders below the ROM folder are scanned.',
            child: SizedBox(
              width: 200,
              child: NumberBox<int>(
                value: draft['depth'] as int?,
                min: 0,
                placeholder: 'Unlimited',
                mode: SpinButtonPlacementMode.inline,
                onChanged: edit('depth'),
              ),
            ),
          ),
        ],
      ),
      Section(
        title: 'Choosing one release per game',
        children: [
          Field(
            label: 'Priority',
            help:
                'The tie-breaks in the order they decide. Drag to reorder, '
                'or down to drop one. Region still applies when dropped, '
                'after the rest.',
            child: BadgeFlow<String>(
              values: priority,
              numbered: true,
              label: (axis) => _axisTitles[axis] ?? axis,
              pool: [for (final axis in ScoreAxis.values) axis.name],
              onChanged: edit('priority'),
            ),
          ),
          if (priority.contains(ScoreAxis.langcount.name))
            Field(
              label: 'Language count',
              help: 'Which way the number of languages in a dump ranks.',
              child: ChoiceBox<String>(
                value: draft['langcount'] as String? ?? LangCount.most.name,
                choices: const [
                  (
                    value: 'most',
                    title: 'Most languages',
                    detail: 'The dump that speaks more languages wins.',
                  ),
                  (
                    value: 'fewest',
                    title: 'Fewest languages',
                    detail: 'The smaller dump wins; useful for large discs.',
                  ),
                ],
                onChanged: edit('langcount'),
              ),
            ),
          Field(
            label: 'Languages',
            help: 'Earlier is better. A code also covers its variants: Es covers Es-MX.',
            child: BadgeFlow<String>(
              values: list('lang'),
              label: (code) => code,
              tooltip: (code) => c.catalog.languages[code],
              empty: 'No language: none is preferred.',
              onChanged: edit('lang'),
              trailing: Picker(
                label: 'Add language',
                custom: c.catalog.languages.length <= 1,
                choices: [
                  for (final MapEntry(key: code, value: name)
                      in c.catalog.languages.entries)
                    if (!list('lang').contains(code))
                      (value: code, title: name, detail: code),
                ],
                onPicked: enabled
                    ? (code) => c.edit('lang', [...list('lang'), code])
                    : null,
              ),
            ),
          ),
          Field(
            label: 'Regions',
            help: 'Earlier is better. Empty keeps the full default order.',
            child: BadgeFlow<String>(
              values: list('region'),
              label: (region) => region,
              empty: 'Default order.',
              onChanged: edit('region'),
              trailing: Picker(
                label: 'Add region',
                custom: c.catalog.regions.length <= 2,
                choices: [
                  for (final region in c.catalog.regions)
                    if (!list('region').contains(region))
                      (value: region, title: region, detail: null),
                ],
                onPicked: enabled
                    ? (region) => c.edit('region', [...list('region'), region])
                    : null,
              ),
            ),
          ),
          Field(
            label: 'Achievements',
            help: 'Whether a game needs a RetroAchievements set to be kept.',
            child: ChoiceBox<String>(
              value: draft['achievements'] as String? ?? _off,
              choices: const [
                (value: _off, title: 'Not required', detail: null),
                (
                  value: 'any',
                  title: 'Any dump',
                  detail: 'The game has a set; the priority picks the dump.',
                ),
                (
                  value: 'approved',
                  title: 'Approved dumps only',
                  detail: 'Only the dumps the set was made for.',
                ),
              ],
              onChanged: enabled
                  ? (scope) =>
                        c.edit('achievements', scope == _off ? null : scope)
                  : null,
            ),
          ),
          Field(
            label: 'Editions with extra content',
            child: ChoiceBox<String>(
              value: draft['supersets'] as String? ?? SupersetMode.prefer.name,
              choices: const [
                (
                  value: 'prefer',
                  title: 'Prefer',
                  detail:
                      'An edition that contains the original takes its place.',
                ),
                (
                  value: 'ignore',
                  title: 'Ignore',
                  detail: 'Treated like any other release.',
                ),
              ],
              onChanged: edit('supersets'),
            ),
          ),
          Field(
            label: 'Compilations',
            child: ChoiceBox<String>(
              value:
                  draft['compilations'] as String? ?? CompilationMode.fill.name,
              choices: const [
                (
                  value: 'never',
                  title: 'Never',
                  detail: 'A pack only competes in its own group.',
                ),
                (
                  value: 'fill',
                  title: 'Fill gaps',
                  detail: 'A pack stands in only for games with no release.',
                ),
                (
                  value: 'prefer',
                  title: 'Prefer',
                  detail: 'A pack takes the slots; the priority still decides first.',
                ),
                (
                  value: 'first',
                  title: 'First',
                  detail: 'A pack takes the slots ahead of the priority too.',
                ),
              ],
              onChanged: edit('compilations'),
            ),
          ),
          Field(
            label: 'Exclude',
            help: 'Kinds of releases left out of the collection.',
            child: _Checks(
              values: [for (final kind in ExcludeKind.values) kind.cli],
              checked: list('exclude').toSet(),
              label: _sentence,
              onChanged: edit('exclude'),
            ),
          ),
        ],
      ),
      Section(
        title: 'Wishlist',
        children: [
          Field(
            help: 'A JSONC list of titles to collect.',
            child: PathBox(
              value: wishlist,
              placeholder: 'No wishlist',
              onChanged: edit('wishlist'),
              browse: () async => (await openFile(
                initialDirectory:
                    _existing(wishlist == null ? null : p.dirname(wishlist)) ??
                    _existing(p.join(c.cacheDir, 'wishlists')),
                acceptedTypeGroups: const [
                  XTypeGroup(label: 'Wishlist', extensions: ['jsonc', 'json']),
                ],
              ))?.path,
            ),
          ),
          if (wishlist != null)
            Field(
              label: 'Mode',
              child: ChoiceBox<String>(
                value:
                    draft['wishlist-mode'] as String? ??
                    WishlistMode.absolute.name,
                choices: const [
                  (
                    value: 'absolute',
                    title: 'Absolute',
                    detail:
                        'Everything listed is kept; the other rules only '
                        'choose which dump.',
                  ),
                  (
                    value: 'subset',
                    title: 'Subset',
                    detail:
                        'Listed titles still have to pass the language, '
                        'region and achievement rules.',
                  ),
                ],
                onChanged: edit('wishlist-mode'),
              ),
            ),
        ],
      ),
      Section(
        title: 'Stages',
        children: [
          Field(
            help: 'Unchecked stages are skipped.',
            child: _Checks(
              values: [for (final stage in Stage.values) stage.name],
              checked: {
                for (final stage in Stage.values)
                  if (!list('skip').contains(stage.name)) stage.name,
              },
              label: (stage) => _stageTitles[stage]!,
              columns: false,
              onChanged: enabled
                  ? (run) => c.edit('skip', [
                      for (final stage in Stage.values)
                        if (!run.contains(stage.name)) stage.name,
                    ])
                  : null,
            ),
          ),
        ],
      ),
      ?footer,
    ];
    return ListView.separated(
      padding: const EdgeInsets.only(right: 12),
      itemCount: sections.length,
      itemBuilder: (context, index) => sections[index],
      separatorBuilder: (context, index) => const SizedBox(height: 12),
    );
  }

  /// Stands for no achievement requirement, which the drop-down cannot hold
  /// as null.
  static const _off = 'off';

  static String? _existing(String? path) =>
      path != null && Directory(path).existsSync() ? path : null;

  /// The folders directly under [root], for the protected-folder picker.
  static Future<List<Choice<String>>> _folders(
    String? root, {
    required List<String> except,
  }) async {
    if (root == null || !await Directory(root).exists()) return const [];
    return [
      await for (final entity in Directory(root).list())
        if (entity is Directory && !except.contains(p.basename(entity.path)))
          (
            value: p.basename(entity.path),
            title: p.basename(entity.path),
            detail: null,
          ),
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  static String _sentence(String cli) => switch (cli) {
    'add-ons' => 'Add-ons',
    'bios' => 'BIOS',
    'mia' => 'Missing dumps (MIA)',
    _ => '${cli[0].toUpperCase()}${cli.substring(1).replaceAll('-', ' ')}',
  };

  static const _axisTitles = {
    'lang': 'Language',
    'region': 'Region',
    'ra': 'RetroAchievements',
    'langcount': 'Language count',
  };

  static const _layoutTitles = {
    Layout.zip: 'Zip',
    Layout.zipInFolder: 'Zip in a folder',
    Layout.extracted: 'Extracted',
    Layout.extractedInFolder: 'Extracted in a folder',
  };

  static const _layoutShapes = {
    Layout.zip: '<root>/<game>.zip',
    Layout.zipInFolder: '<root>/<game>/<game>.zip',
    Layout.extracted: '<root>/<game>.<ext>',
    Layout.extractedInFolder:
        '<root>/<game>.<ext>/<game>.<ext>, which ES-DE launches as one entry',
  };

  static const _stageTitles = {
    'sync': 'Update metadata and DATs',
    'download': 'Download what is missing',
    'organize': 'Arrange files into the layout',
    'playlists': 'Write multi-disc playlists',
    'prune': 'Move files outside the selection to .trash',
  };
}

/// A wrap of check boxes; [onChanged] receives the checked values in order.
class _Checks extends StatelessWidget {
  const _Checks({
    required this.values,
    required this.checked,
    required this.label,
    required this.onChanged,
    this.columns = true,
  });

  final List<String> values;
  final Set<String> checked;

  /// Lays the boxes out in fixed-width columns rather than one per line.
  final bool columns;
  final String Function(String value) label;
  final ValueChanged<List<String>>? onChanged;

  Widget _check(String value) {
    final onChanged = this.onChanged;
    void toggle(bool on) => onChanged?.call([
      for (final v in values)
        if (v == value ? on : checked.contains(v)) v,
    ]);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          checked: checked.contains(value),
          semanticLabel: label(value),
          onChanged: onChanged == null ? null : (on) => toggle(on ?? false),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: GestureDetector(
            onTap: onChanged == null
                ? null
                : () => toggle(!checked.contains(value)),
            child: Text(label(value), overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => columns
      ? Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final value in values)
              SizedBox(width: 200, child: _check(value)),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [for (final value in values) _check(value)],
        );
}
