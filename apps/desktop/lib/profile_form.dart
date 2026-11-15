import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:minerva_core/minerva_core.dart';
import 'package:path/path.dart' as p;

import 'controls.dart';
import 'l10n/app_localizations.dart';
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
    final l = AppLocalizations.of(context);
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
        title: l.sectionCollection,
        children: [
          Field(
            label: l.systems,
            help: l.systemsHelp,
            child: BadgeFlow<String>(
              values: list('dat'),
              label: (dat) => dat,
              empty: l.noSystem,
              onChanged: edit('dat'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Picker(
                    label: l.addSystem,
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
                    child: Text(l.browseDat),
                  ),
                ],
              ),
            ),
          ),
          Field(
            label: l.romFolder,
            help: l.romFolderHelp,
            child: PathBox(
              value: root,
              placeholder: l.noRomFolder,
              onChanged: edit('root'),
              browse: () => getDirectoryPath(
                initialDirectory: _existing(root),
                confirmButtonText: l.useFolder,
              ),
            ),
          ),
          Field(
            label: l.layout,
            help: l.layoutHelp,
            child: ChoiceBox<String>(
              value: draft['layout'] as String? ?? Layout.zip.cli,
              choices: [
                for (final layout in Layout.values)
                  (
                    value: layout.cli,
                    title: _layoutTitle(l, layout),
                    detail: layout == Layout.extractedInFolder
                        ? l.layoutEsDe(_layoutShapes[layout]!)
                        : _layoutShapes[layout],
                  ),
              ],
              onChanged: edit('layout'),
            ),
          ),
          Field(
            label: l.protectedFolders,
            help: l.protectedFoldersHelp,
            child: BadgeFlow<String>(
              values: list('protect'),
              label: (folder) => folder,
              onChanged: edit('protect'),
              trailing: Picker(
                label: l.addFolder,
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
            label: l.searchDepth,
            help: l.searchDepthHelp,
            child: SizedBox(
              width: 200,
              child: NumberBox<int>(
                value: draft['depth'] as int?,
                min: 0,
                placeholder: l.unlimited,
                mode: SpinButtonPlacementMode.inline,
                onChanged: edit('depth'),
              ),
            ),
          ),
        ],
      ),
      Section(
        title: l.sectionOneRelease,
        children: [
          Field(
            label: l.priority,
            help: l.priorityHelp,
            child: BadgeFlow<String>(
              values: priority,
              numbered: true,
              label: (axis) => _axisTitle(l, axis),
              pool: [for (final axis in ScoreAxis.values) axis.name],
              onChanged: edit('priority'),
            ),
          ),
          if (priority.contains(ScoreAxis.langcount.name))
            Field(
              label: l.languageCount,
              help: l.languageCountHelp,
              child: ChoiceBox<String>(
                value: draft['langcount'] as String? ?? LangCount.most.name,
                choices: [
                  (value: 'most', title: l.langMost, detail: l.langMostHelp),
                  (
                    value: 'fewest',
                    title: l.langFewest,
                    detail: l.langFewestHelp,
                  ),
                ],
                onChanged: edit('langcount'),
              ),
            ),
          Field(
            label: l.languages,
            help: l.languagesHelp,
            child: BadgeFlow<String>(
              values: list('lang'),
              label: (code) => code,
              tooltip: (code) => _languageName(l, c, code),
              empty: l.noLanguage,
              onChanged: edit('lang'),
              trailing: Picker(
                label: l.addLanguage,
                custom: c.catalog.languages.length <= 1,
                choices: [
                  for (final MapEntry(key: code, value: name)
                      in c.catalog.languages.entries)
                    if (!list('lang').contains(code))
                      (
                        value: code,
                        title: name.isEmpty ? l.anyOtherLanguage : name,
                        detail: code,
                      ),
                ],
                onPicked: enabled
                    ? (code) => c.edit('lang', [...list('lang'), code])
                    : null,
              ),
            ),
          ),
          Field(
            label: l.regions,
            help: l.regionsHelp,
            child: BadgeFlow<String>(
              values: list('region'),
              label: (region) => region,
              empty: l.defaultOrder,
              onChanged: edit('region'),
              trailing: Picker(
                label: l.addRegion,
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
            label: l.achievements,
            help: l.achievementsHelp,
            child: ChoiceBox<String>(
              value: draft['achievements'] as String? ?? _off,
              choices: [
                (value: _off, title: l.achievementsOff, detail: null),
                (
                  value: 'any',
                  title: l.achievementsAny,
                  detail: l.achievementsAnyHelp,
                ),
                (
                  value: 'approved',
                  title: l.achievementsApproved,
                  detail: l.achievementsApprovedHelp,
                ),
              ],
              onChanged: enabled
                  ? (scope) =>
                        c.edit('achievements', scope == _off ? null : scope)
                  : null,
            ),
          ),
          Field(
            label: l.supersets,
            child: ChoiceBox<String>(
              value: draft['supersets'] as String? ?? SupersetMode.prefer.name,
              choices: [
                (
                  value: 'prefer',
                  title: l.supersetsPrefer,
                  detail: l.supersetsPreferHelp,
                ),
                (
                  value: 'ignore',
                  title: l.supersetsIgnore,
                  detail: l.supersetsIgnoreHelp,
                ),
              ],
              onChanged: edit('supersets'),
            ),
          ),
          Field(
            label: l.compilations,
            child: ChoiceBox<String>(
              value:
                  draft['compilations'] as String? ?? CompilationMode.fill.name,
              choices: [
                (
                  value: 'never',
                  title: l.compilationsNever,
                  detail: l.compilationsNeverHelp,
                ),
                (
                  value: 'fill',
                  title: l.compilationsFill,
                  detail: l.compilationsFillHelp,
                ),
                (
                  value: 'prefer',
                  title: l.compilationsPrefer,
                  detail: l.compilationsPreferHelp,
                ),
                (
                  value: 'first',
                  title: l.compilationsFirst,
                  detail: l.compilationsFirstHelp,
                ),
              ],
              onChanged: edit('compilations'),
            ),
          ),
          Field(
            label: l.exclude,
            help: l.excludeHelp,
            child: _Checks(
              values: [for (final kind in ExcludeKind.values) kind.cli],
              checked: list('exclude').toSet(),
              label: (kind) => _excludeTitle(l, kind),
              onChanged: edit('exclude'),
            ),
          ),
        ],
      ),
      Section(
        title: l.sectionWishlist,
        children: [
          Field(
            help: l.wishlistHelp,
            child: PathBox(
              value: wishlist,
              placeholder: l.noWishlist,
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
              label: l.wishlistMode,
              child: ChoiceBox<String>(
                value:
                    draft['wishlist-mode'] as String? ??
                    WishlistMode.absolute.name,
                choices: [
                  (
                    value: 'absolute',
                    title: l.wishlistAbsolute,
                    detail: l.wishlistAbsoluteHelp,
                  ),
                  (
                    value: 'subset',
                    title: l.wishlistSubset,
                    detail: l.wishlistSubsetHelp,
                  ),
                ],
                onChanged: edit('wishlist-mode'),
              ),
            ),
        ],
      ),
      Section(
        title: l.sectionStages,
        children: [
          Field(
            help: l.stagesHelp,
            child: _Checks(
              values: [for (final stage in Stage.values) stage.name],
              checked: {
                for (final stage in Stage.values)
                  if (!list('skip').contains(stage.name)) stage.name,
              },
              label: (stage) => _stageTitle(l, stage),
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

  static String? _languageName(
    AppLocalizations l,
    RunController c,
    String code,
  ) => switch (c.catalog.languages[code]) {
    '' => l.anyOtherLanguage,
    final name => name,
  };

  static String _excludeTitle(AppLocalizations l, String cli) => switch (cli) {
    'add-ons' => l.excludeAddOns,
    'applications' => l.excludeApplications,
    'audio' => l.excludeAudio,
    'bad-dumps' => l.excludeBadDumps,
    'bios' => l.excludeBios,
    'bonus-discs' => l.excludeBonusDiscs,
    'coverdiscs' => l.excludeCoverdiscs,
    'demos' => l.excludeDemos,
    'educational' => l.excludeEducational,
    'manuals' => l.excludeManuals,
    'mia' => l.excludeMia,
    'multimedia' => l.excludeMultimedia,
    'pirate' => l.excludePirate,
    'preproduction' => l.excludePreproduction,
    'promotional' => l.excludePromotional,
    'unlicensed' => l.excludeUnlicensed,
    'video' => l.excludeVideo,
    _ => cli,
  };

  static String _axisTitle(AppLocalizations l, String axis) => switch (axis) {
    'lang' => l.axisLang,
    'region' => l.axisRegion,
    'ra' => l.axisRa,
    'langcount' => l.axisLangcount,
    _ => axis,
  };

  static String _layoutTitle(AppLocalizations l, Layout layout) =>
      switch (layout) {
        Layout.zip => l.layoutZip,
        Layout.zipInFolder => l.layoutZipInFolder,
        Layout.extracted => l.layoutExtracted,
        Layout.extractedInFolder => l.layoutExtractedInFolder,
      };

  static const _layoutShapes = {
    Layout.zip: '<root>/<game>.zip',
    Layout.zipInFolder: '<root>/<game>/<game>.zip',
    Layout.extracted: '<root>/<game>.<ext>',
    Layout.extractedInFolder: '<root>/<game>.<ext>/<game>.<ext>',
  };

  static String _stageTitle(AppLocalizations l, String stage) =>
      switch (stage) {
        'sync' => l.stageSync,
        'download' => l.stageDownload,
        'organize' => l.stageOrganize,
        'playlists' => l.stagePlaylists,
        'prune' => l.stagePrune,
        _ => stage,
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
