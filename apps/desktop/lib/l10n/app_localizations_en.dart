// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'MiNERVA Archivist';

  @override
  String get preview => 'Preview';

  @override
  String get apply => 'Apply';

  @override
  String get stop => 'Stop';

  @override
  String get showOutput => 'Show output';

  @override
  String get hideOutput => 'Hide output';

  @override
  String get clear => 'Clear';

  @override
  String get clearTooltip => 'Start over from the default settings';

  @override
  String get languageMenu => 'Language';

  @override
  String get languageSystem => 'System language';

  @override
  String get themeMenu => 'Theme';

  @override
  String get themeSystem => 'System theme';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get problemCache => 'Cache folder';

  @override
  String get problemProfile => 'Profile';

  @override
  String get problemSettings => 'These settings cannot run';

  @override
  String cannotRead(String path, String detail) {
    return 'Cannot read $path: $detail';
  }

  @override
  String cannotSave(String path, String detail) {
    return 'Cannot save $path: $detail';
  }

  @override
  String subjectProblem(String subject, String detail) {
    return '$subject: $detail';
  }

  @override
  String get profileName => 'Profile name';

  @override
  String get load => 'Load';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get deleteTitle => 'Delete profile?';

  @override
  String deleteBody(String name, String file) {
    return '\"$name\" is removed from $file. The settings on screen stay as they are.';
  }

  @override
  String get noProfilesYet => 'No profiles yet. Type a name and Save.';

  @override
  String get noProfileMatches => 'No profile matches; Save creates it.';

  @override
  String get cacheFolder => 'Cache folder';

  @override
  String get cacheFolderHelp =>
      'Where profiles.jsonc, the DATs and the metadata live. Remembered for the next launch.';

  @override
  String get cachePlaceholder => 'Folder with profiles.jsonc';

  @override
  String get folderNotFound => 'Folder not found.';

  @override
  String get noProfilesFile => 'No profiles.jsonc here yet; saving creates it.';

  @override
  String get browse => 'Browse';

  @override
  String get useFolder => 'Use folder';

  @override
  String get output => 'Output';

  @override
  String get copyAll => 'Copy all';

  @override
  String get dockLeft => 'Dock to the left';

  @override
  String get dockBottom => 'Dock to the bottom';

  @override
  String get dockRight => 'Dock to the right';

  @override
  String get float => 'Float';

  @override
  String get hidePanel => 'Hide (F12)';

  @override
  String get menuCopy => 'Copy';

  @override
  String get menuSelectAll => 'Select all';

  @override
  String get menuCut => 'Cut';

  @override
  String get menuPaste => 'Paste';

  @override
  String get logIdle =>
      'Preview shows what a run would do without touching any file. Apply does it.';

  @override
  String get logStarting => 'Starting…';

  @override
  String get logRun => 'Run';

  @override
  String get logPreview => ' (preview)';

  @override
  String logSync(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count metadata files updated',
      one: '1 metadata file updated',
    );
    return '$_temp0';
  }

  @override
  String logSyncErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: ', $count errors',
      one: ', 1 error',
    );
    return '$_temp0';
  }

  @override
  String logSelected(int selected, int total) {
    return 'Selected $selected of $total';
  }

  @override
  String logWishlistUnmatched(String entry) {
    return 'Wishlist entry matches nothing: $entry';
  }

  @override
  String logAudit(int present, int total, int missing, int unknown) {
    return '$present/$total on disk, $missing missing, $unknown unknown';
  }

  @override
  String logToDownload(int count, String size) {
    return '$count to download, $size';
  }

  @override
  String logSeeders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: ', $count seeders',
      one: ', 1 seeder',
    );
    return '$_temp0';
  }

  @override
  String logNotDistributed(String name) {
    return 'Not distributed: $name';
  }

  @override
  String logHeld(String name) {
    return 'Held by a curated folder: $name';
  }

  @override
  String logTransfer(
    int done,
    int files,
    String doneSize,
    String totalSize,
    String speed,
    int seeds,
    int peers,
  ) {
    return '$done/$files files  $doneSize of $totalSize  $speed/s  $seeds seeds, $peers peers';
  }

  @override
  String logDownloaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files downloaded',
      one: '1 file downloaded',
    );
    return '$_temp0';
  }

  @override
  String logOrganize(String summary) {
    return 'Organize: $summary';
  }

  @override
  String logPlaylists(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count playlists',
      one: '1 playlist',
    );
    return '$_temp0';
  }

  @override
  String logPruned(int count, String folder) {
    return '$count moved to $folder';
  }

  @override
  String get notUsed => 'Not used:';

  @override
  String get dropToLeaveOut => 'Drag a badge here to leave it out.';

  @override
  String get filter => 'Filter';

  @override
  String get filterOrType => 'Filter, or type a value';

  @override
  String useTyped(String value) {
    return 'Use \"$value\"';
  }

  @override
  String get nothingMatches => 'Nothing matches.';

  @override
  String get sectionCollection => 'Collection';

  @override
  String get systems => 'Systems';

  @override
  String get systemsHelp =>
      'DATs from the cache, a .dat file or a folder of them. Several are merged into one collection.';

  @override
  String get noSystem => 'No system yet.';

  @override
  String get addSystem => 'Add system';

  @override
  String get browseDat => 'Browse .dat…';

  @override
  String get romFolder => 'ROM folder';

  @override
  String get romFolderHelp =>
      'Where the collection lives. Empty only previews the selection.';

  @override
  String get noRomFolder => 'No ROM folder';

  @override
  String get layout => 'Layout';

  @override
  String get layoutHelp => 'How each game sits under the ROM folder.';

  @override
  String get layoutZip => 'Zip';

  @override
  String get layoutZipInFolder => 'Zip in a folder';

  @override
  String get layoutExtracted => 'Extracted';

  @override
  String get layoutExtractedInFolder => 'Extracted in a folder';

  @override
  String layoutEsDe(String shape) {
    return '$shape, which ES-DE launches as one entry';
  }

  @override
  String get protectedFolders => 'Protected folders';

  @override
  String get protectedFoldersHelp =>
      'Top-level folders under the ROM folder that are never touched.';

  @override
  String get addFolder => 'Add folder';

  @override
  String get searchDepth => 'Search depth';

  @override
  String get searchDepthHelp =>
      'How many folders below the ROM folder are scanned.';

  @override
  String get unlimited => 'Unlimited';

  @override
  String get sectionOneRelease => 'Choosing one release per game';

  @override
  String get priority => 'Priority';

  @override
  String get priorityHelp =>
      'The tie-breaks in the order they decide. Drag to reorder, or down to drop one. Region still applies when dropped, after the rest.';

  @override
  String get axisLang => 'Language';

  @override
  String get axisRegion => 'Region';

  @override
  String get axisRa => 'RetroAchievements';

  @override
  String get axisLangcount => 'Language count';

  @override
  String get languageCount => 'Language count';

  @override
  String get languageCountHelp =>
      'Which way the number of languages in a dump ranks.';

  @override
  String get langMost => 'Most languages';

  @override
  String get langMostHelp => 'The dump that speaks more languages wins.';

  @override
  String get langFewest => 'Fewest languages';

  @override
  String get langFewestHelp => 'The smaller dump wins; useful for large discs.';

  @override
  String get languages => 'Languages';

  @override
  String get languagesHelp =>
      'Earlier is better. A code also covers its variants: Es covers Es-MX.';

  @override
  String get noLanguage => 'No language: none is preferred.';

  @override
  String get addLanguage => 'Add language';

  @override
  String get anyOtherLanguage => 'Any other language';

  @override
  String get regions => 'Regions';

  @override
  String get regionsHelp =>
      'Earlier is better. Empty keeps the full default order.';

  @override
  String get defaultOrder => 'Default order.';

  @override
  String get addRegion => 'Add region';

  @override
  String get achievements => 'Achievements';

  @override
  String get achievementsHelp =>
      'Whether a game needs a RetroAchievements set to be kept.';

  @override
  String get achievementsOff => 'Not required';

  @override
  String get achievementsAny => 'Any dump';

  @override
  String get achievementsAnyHelp =>
      'The game has a set; the priority picks the dump.';

  @override
  String get achievementsApproved => 'Approved dumps only';

  @override
  String get achievementsApprovedHelp => 'Only the dumps the set was made for.';

  @override
  String get supersets => 'Editions with extra content';

  @override
  String get supersetsPrefer => 'Prefer';

  @override
  String get supersetsPreferHelp =>
      'An edition that contains the original takes its place.';

  @override
  String get supersetsIgnore => 'Ignore';

  @override
  String get supersetsIgnoreHelp => 'Treated like any other release.';

  @override
  String get compilations => 'Compilations';

  @override
  String get compilationsNever => 'Never';

  @override
  String get compilationsNeverHelp => 'A pack only competes in its own group.';

  @override
  String get compilationsFill => 'Fill gaps';

  @override
  String get compilationsFillHelp =>
      'A pack stands in only for games with no release.';

  @override
  String get compilationsPrefer => 'Prefer';

  @override
  String get compilationsPreferHelp =>
      'A pack takes the slots; the priority still decides first.';

  @override
  String get compilationsFirst => 'First';

  @override
  String get compilationsFirstHelp =>
      'A pack takes the slots ahead of the priority too.';

  @override
  String get exclude => 'Exclude';

  @override
  String get excludeHelp => 'Kinds of releases left out of the collection.';

  @override
  String get excludeAddOns => 'Add-ons';

  @override
  String get excludeApplications => 'Applications';

  @override
  String get excludeAudio => 'Audio';

  @override
  String get excludeBadDumps => 'Bad dumps';

  @override
  String get excludeBios => 'BIOS';

  @override
  String get excludeBonusDiscs => 'Bonus discs';

  @override
  String get excludeCoverdiscs => 'Coverdiscs';

  @override
  String get excludeDemos => 'Demos';

  @override
  String get excludeEducational => 'Educational';

  @override
  String get excludeManuals => 'Manuals';

  @override
  String get excludeMia => 'Missing dumps (MIA)';

  @override
  String get excludeMultimedia => 'Multimedia';

  @override
  String get excludePirate => 'Pirate';

  @override
  String get excludePreproduction => 'Preproduction';

  @override
  String get excludePromotional => 'Promotional';

  @override
  String get excludeUnlicensed => 'Unlicensed';

  @override
  String get excludeVideo => 'Video';

  @override
  String get sectionWishlist => 'Wishlist';

  @override
  String get wishlistHelp => 'A JSONC list of titles to collect.';

  @override
  String get noWishlist => 'No wishlist';

  @override
  String get wishlistMode => 'Mode';

  @override
  String get wishlistAbsolute => 'Absolute';

  @override
  String get wishlistAbsoluteHelp =>
      'Everything listed is kept; the other rules only choose which dump.';

  @override
  String get wishlistSubset => 'Subset';

  @override
  String get wishlistSubsetHelp =>
      'Listed titles still have to pass the language, region and achievement rules.';

  @override
  String get sectionStages => 'Stages';

  @override
  String get stagesHelp => 'Unchecked stages are skipped.';

  @override
  String get stageSync => 'Update metadata and DATs';

  @override
  String get stageDownload => 'Download what is missing';

  @override
  String get stageOrganize => 'Arrange files into the layout';

  @override
  String get stagePlaylists => 'Write multi-disc playlists';

  @override
  String get stagePrune => 'Move files outside the selection to .trash';
}
