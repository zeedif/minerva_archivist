import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'MiNERVA Archivist'**
  String get appTitle;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @showOutput.
  ///
  /// In en, this message translates to:
  /// **'Show output'**
  String get showOutput;

  /// No description provided for @hideOutput.
  ///
  /// In en, this message translates to:
  /// **'Hide output'**
  String get hideOutput;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @clearTooltip.
  ///
  /// In en, this message translates to:
  /// **'Start over from the default settings'**
  String get clearTooltip;

  /// No description provided for @languageMenu.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageMenu;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System language'**
  String get languageSystem;

  /// No description provided for @themeMenu.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeMenu;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System theme'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @problemCache.
  ///
  /// In en, this message translates to:
  /// **'Cache folder'**
  String get problemCache;

  /// No description provided for @problemProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get problemProfile;

  /// No description provided for @problemSettings.
  ///
  /// In en, this message translates to:
  /// **'These settings cannot run'**
  String get problemSettings;

  /// No description provided for @cannotRead.
  ///
  /// In en, this message translates to:
  /// **'Cannot read {path}: {detail}'**
  String cannotRead(String path, String detail);

  /// No description provided for @cannotSave.
  ///
  /// In en, this message translates to:
  /// **'Cannot save {path}: {detail}'**
  String cannotSave(String path, String detail);

  /// No description provided for @subjectProblem.
  ///
  /// In en, this message translates to:
  /// **'{subject}: {detail}'**
  String subjectProblem(String subject, String detail);

  /// No description provided for @profileName.
  ///
  /// In en, this message translates to:
  /// **'Profile name'**
  String get profileName;

  /// No description provided for @load.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get load;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @deleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete profile?'**
  String get deleteTitle;

  /// No description provided for @deleteBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is removed from {file}. The settings on screen stay as they are.'**
  String deleteBody(String name, String file);

  /// No description provided for @noProfilesYet.
  ///
  /// In en, this message translates to:
  /// **'No profiles yet. Type a name and Save.'**
  String get noProfilesYet;

  /// No description provided for @noProfileMatches.
  ///
  /// In en, this message translates to:
  /// **'No profile matches; Save creates it.'**
  String get noProfileMatches;

  /// No description provided for @cacheFolder.
  ///
  /// In en, this message translates to:
  /// **'Cache folder'**
  String get cacheFolder;

  /// No description provided for @cacheFolderHelp.
  ///
  /// In en, this message translates to:
  /// **'Where profiles.jsonc, the DATs and the metadata live. Remembered for the next launch.'**
  String get cacheFolderHelp;

  /// No description provided for @cachePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Folder with profiles.jsonc'**
  String get cachePlaceholder;

  /// No description provided for @folderNotFound.
  ///
  /// In en, this message translates to:
  /// **'Folder not found.'**
  String get folderNotFound;

  /// No description provided for @noProfilesFile.
  ///
  /// In en, this message translates to:
  /// **'No profiles.jsonc here yet; saving creates it.'**
  String get noProfilesFile;

  /// No description provided for @browse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get browse;

  /// No description provided for @useFolder.
  ///
  /// In en, this message translates to:
  /// **'Use folder'**
  String get useFolder;

  /// No description provided for @output.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get output;

  /// No description provided for @copyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get copyAll;

  /// No description provided for @dockLeft.
  ///
  /// In en, this message translates to:
  /// **'Dock to the left'**
  String get dockLeft;

  /// No description provided for @dockBottom.
  ///
  /// In en, this message translates to:
  /// **'Dock to the bottom'**
  String get dockBottom;

  /// No description provided for @dockRight.
  ///
  /// In en, this message translates to:
  /// **'Dock to the right'**
  String get dockRight;

  /// No description provided for @float.
  ///
  /// In en, this message translates to:
  /// **'Float'**
  String get float;

  /// No description provided for @hidePanel.
  ///
  /// In en, this message translates to:
  /// **'Hide (F12)'**
  String get hidePanel;

  /// No description provided for @menuCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get menuCopy;

  /// No description provided for @menuSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get menuSelectAll;

  /// No description provided for @menuCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get menuCut;

  /// No description provided for @menuPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get menuPaste;

  /// No description provided for @logIdle.
  ///
  /// In en, this message translates to:
  /// **'Preview shows what a run would do without touching any file. Apply does it.'**
  String get logIdle;

  /// No description provided for @logStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get logStarting;

  /// No description provided for @logRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get logRun;

  /// No description provided for @logPreview.
  ///
  /// In en, this message translates to:
  /// **' (preview)'**
  String get logPreview;

  /// No description provided for @logSync.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 metadata file updated} other{{count} metadata files updated}}'**
  String logSync(int count);

  /// No description provided for @logSyncErrors.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{, 1 error} other{, {count} errors}}'**
  String logSyncErrors(int count);

  /// No description provided for @logSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected {selected} of {total}'**
  String logSelected(int selected, int total);

  /// No description provided for @logWishlistUnmatched.
  ///
  /// In en, this message translates to:
  /// **'Wishlist entry matches nothing: {entry}'**
  String logWishlistUnmatched(String entry);

  /// No description provided for @logAudit.
  ///
  /// In en, this message translates to:
  /// **'{present}/{total} on disk, {missing} missing, {unknown} unknown'**
  String logAudit(int present, int total, int missing, int unknown);

  /// No description provided for @logToDownload.
  ///
  /// In en, this message translates to:
  /// **'{count} to download, {size}'**
  String logToDownload(int count, String size);

  /// No description provided for @logSeeders.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{, 1 seeder} other{, {count} seeders}}'**
  String logSeeders(int count);

  /// No description provided for @logNotDistributed.
  ///
  /// In en, this message translates to:
  /// **'Not distributed: {name}'**
  String logNotDistributed(String name);

  /// No description provided for @logHeld.
  ///
  /// In en, this message translates to:
  /// **'Held by a curated folder: {name}'**
  String logHeld(String name);

  /// No description provided for @logTransfer.
  ///
  /// In en, this message translates to:
  /// **'{done}/{files} files  {doneSize} of {totalSize}  {speed}/s  {seeds} seeds, {peers} peers'**
  String logTransfer(
    int done,
    int files,
    String doneSize,
    String totalSize,
    String speed,
    int seeds,
    int peers,
  );

  /// No description provided for @logDownloaded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file downloaded} other{{count} files downloaded}}'**
  String logDownloaded(int count);

  /// No description provided for @logOrganize.
  ///
  /// In en, this message translates to:
  /// **'Organize: {summary}'**
  String logOrganize(String summary);

  /// No description provided for @logPlaylists.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 playlist} other{{count} playlists}}'**
  String logPlaylists(int count);

  /// No description provided for @logPruned.
  ///
  /// In en, this message translates to:
  /// **'{count} moved to {folder}'**
  String logPruned(int count, String folder);

  /// No description provided for @notUsed.
  ///
  /// In en, this message translates to:
  /// **'Not used:'**
  String get notUsed;

  /// No description provided for @dropToLeaveOut.
  ///
  /// In en, this message translates to:
  /// **'Drag a badge here to leave it out.'**
  String get dropToLeaveOut;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @filterOrType.
  ///
  /// In en, this message translates to:
  /// **'Filter, or type a value'**
  String get filterOrType;

  /// No description provided for @useTyped.
  ///
  /// In en, this message translates to:
  /// **'Use \"{value}\"'**
  String useTyped(String value);

  /// No description provided for @nothingMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches.'**
  String get nothingMatches;

  /// No description provided for @sectionCollection.
  ///
  /// In en, this message translates to:
  /// **'Collection'**
  String get sectionCollection;

  /// No description provided for @systems.
  ///
  /// In en, this message translates to:
  /// **'Systems'**
  String get systems;

  /// No description provided for @systemsHelp.
  ///
  /// In en, this message translates to:
  /// **'DATs from the cache, a .dat file or a folder of them. Several are merged into one collection.'**
  String get systemsHelp;

  /// No description provided for @noSystem.
  ///
  /// In en, this message translates to:
  /// **'No system yet.'**
  String get noSystem;

  /// No description provided for @addSystem.
  ///
  /// In en, this message translates to:
  /// **'Add system'**
  String get addSystem;

  /// No description provided for @browseDat.
  ///
  /// In en, this message translates to:
  /// **'Browse .dat…'**
  String get browseDat;

  /// No description provided for @romFolder.
  ///
  /// In en, this message translates to:
  /// **'ROM folder'**
  String get romFolder;

  /// No description provided for @romFolderHelp.
  ///
  /// In en, this message translates to:
  /// **'Where the collection lives. Empty only previews the selection.'**
  String get romFolderHelp;

  /// No description provided for @noRomFolder.
  ///
  /// In en, this message translates to:
  /// **'No ROM folder'**
  String get noRomFolder;

  /// No description provided for @layout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get layout;

  /// No description provided for @layoutHelp.
  ///
  /// In en, this message translates to:
  /// **'How each game sits under the ROM folder.'**
  String get layoutHelp;

  /// No description provided for @layoutZip.
  ///
  /// In en, this message translates to:
  /// **'Zip'**
  String get layoutZip;

  /// No description provided for @layoutZipInFolder.
  ///
  /// In en, this message translates to:
  /// **'Zip in a folder'**
  String get layoutZipInFolder;

  /// No description provided for @layoutExtracted.
  ///
  /// In en, this message translates to:
  /// **'Extracted'**
  String get layoutExtracted;

  /// No description provided for @layoutExtractedInFolder.
  ///
  /// In en, this message translates to:
  /// **'Extracted in a folder'**
  String get layoutExtractedInFolder;

  /// No description provided for @layoutEsDe.
  ///
  /// In en, this message translates to:
  /// **'{shape}, which ES-DE launches as one entry'**
  String layoutEsDe(String shape);

  /// No description provided for @protectedFolders.
  ///
  /// In en, this message translates to:
  /// **'Protected folders'**
  String get protectedFolders;

  /// No description provided for @protectedFoldersHelp.
  ///
  /// In en, this message translates to:
  /// **'Top-level folders under the ROM folder that are never touched.'**
  String get protectedFoldersHelp;

  /// No description provided for @addFolder.
  ///
  /// In en, this message translates to:
  /// **'Add folder'**
  String get addFolder;

  /// No description provided for @searchDepth.
  ///
  /// In en, this message translates to:
  /// **'Search depth'**
  String get searchDepth;

  /// No description provided for @searchDepthHelp.
  ///
  /// In en, this message translates to:
  /// **'How many folders below the ROM folder are scanned.'**
  String get searchDepthHelp;

  /// No description provided for @unlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get unlimited;

  /// No description provided for @sectionOneRelease.
  ///
  /// In en, this message translates to:
  /// **'Choosing one release per game'**
  String get sectionOneRelease;

  /// No description provided for @priority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priority;

  /// No description provided for @priorityHelp.
  ///
  /// In en, this message translates to:
  /// **'The tie-breaks in the order they decide. Drag to reorder, or down to drop one. Region still applies when dropped, after the rest.'**
  String get priorityHelp;

  /// No description provided for @axisLang.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get axisLang;

  /// No description provided for @axisRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get axisRegion;

  /// No description provided for @axisRa.
  ///
  /// In en, this message translates to:
  /// **'RetroAchievements'**
  String get axisRa;

  /// No description provided for @axisLangcount.
  ///
  /// In en, this message translates to:
  /// **'Language count'**
  String get axisLangcount;

  /// No description provided for @languageCount.
  ///
  /// In en, this message translates to:
  /// **'Language count'**
  String get languageCount;

  /// No description provided for @languageCountHelp.
  ///
  /// In en, this message translates to:
  /// **'Which way the number of languages in a dump ranks.'**
  String get languageCountHelp;

  /// No description provided for @langMost.
  ///
  /// In en, this message translates to:
  /// **'Most languages'**
  String get langMost;

  /// No description provided for @langMostHelp.
  ///
  /// In en, this message translates to:
  /// **'The dump that speaks more languages wins.'**
  String get langMostHelp;

  /// No description provided for @langFewest.
  ///
  /// In en, this message translates to:
  /// **'Fewest languages'**
  String get langFewest;

  /// No description provided for @langFewestHelp.
  ///
  /// In en, this message translates to:
  /// **'The smaller dump wins; useful for large discs.'**
  String get langFewestHelp;

  /// No description provided for @languages.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get languages;

  /// No description provided for @languagesHelp.
  ///
  /// In en, this message translates to:
  /// **'Earlier is better. A code also covers its variants: Es covers Es-MX.'**
  String get languagesHelp;

  /// No description provided for @noLanguage.
  ///
  /// In en, this message translates to:
  /// **'No language: none is preferred.'**
  String get noLanguage;

  /// No description provided for @addLanguage.
  ///
  /// In en, this message translates to:
  /// **'Add language'**
  String get addLanguage;

  /// No description provided for @anyOtherLanguage.
  ///
  /// In en, this message translates to:
  /// **'Any other language'**
  String get anyOtherLanguage;

  /// No description provided for @regions.
  ///
  /// In en, this message translates to:
  /// **'Regions'**
  String get regions;

  /// No description provided for @regionsHelp.
  ///
  /// In en, this message translates to:
  /// **'Earlier is better. Empty keeps the full default order.'**
  String get regionsHelp;

  /// No description provided for @defaultOrder.
  ///
  /// In en, this message translates to:
  /// **'Default order.'**
  String get defaultOrder;

  /// No description provided for @addRegion.
  ///
  /// In en, this message translates to:
  /// **'Add region'**
  String get addRegion;

  /// No description provided for @achievements.
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get achievements;

  /// No description provided for @achievementsHelp.
  ///
  /// In en, this message translates to:
  /// **'Whether a game needs a RetroAchievements set to be kept.'**
  String get achievementsHelp;

  /// No description provided for @achievementsOff.
  ///
  /// In en, this message translates to:
  /// **'Not required'**
  String get achievementsOff;

  /// No description provided for @achievementsAny.
  ///
  /// In en, this message translates to:
  /// **'Any dump'**
  String get achievementsAny;

  /// No description provided for @achievementsAnyHelp.
  ///
  /// In en, this message translates to:
  /// **'The game has a set; the priority picks the dump.'**
  String get achievementsAnyHelp;

  /// No description provided for @achievementsApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved dumps only'**
  String get achievementsApproved;

  /// No description provided for @achievementsApprovedHelp.
  ///
  /// In en, this message translates to:
  /// **'Only the dumps the set was made for.'**
  String get achievementsApprovedHelp;

  /// No description provided for @supersets.
  ///
  /// In en, this message translates to:
  /// **'Editions with extra content'**
  String get supersets;

  /// No description provided for @supersetsPrefer.
  ///
  /// In en, this message translates to:
  /// **'Prefer'**
  String get supersetsPrefer;

  /// No description provided for @supersetsPreferHelp.
  ///
  /// In en, this message translates to:
  /// **'An edition that contains the original takes its place.'**
  String get supersetsPreferHelp;

  /// No description provided for @supersetsIgnore.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get supersetsIgnore;

  /// No description provided for @supersetsIgnoreHelp.
  ///
  /// In en, this message translates to:
  /// **'Treated like any other release.'**
  String get supersetsIgnoreHelp;

  /// No description provided for @compilations.
  ///
  /// In en, this message translates to:
  /// **'Compilations'**
  String get compilations;

  /// No description provided for @compilationsNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get compilationsNever;

  /// No description provided for @compilationsNeverHelp.
  ///
  /// In en, this message translates to:
  /// **'A pack only competes in its own group.'**
  String get compilationsNeverHelp;

  /// No description provided for @compilationsFill.
  ///
  /// In en, this message translates to:
  /// **'Fill gaps'**
  String get compilationsFill;

  /// No description provided for @compilationsFillHelp.
  ///
  /// In en, this message translates to:
  /// **'A pack stands in only for games with no release.'**
  String get compilationsFillHelp;

  /// No description provided for @compilationsPrefer.
  ///
  /// In en, this message translates to:
  /// **'Prefer'**
  String get compilationsPrefer;

  /// No description provided for @compilationsPreferHelp.
  ///
  /// In en, this message translates to:
  /// **'A pack takes the slots; the priority still decides first.'**
  String get compilationsPreferHelp;

  /// No description provided for @compilationsFirst.
  ///
  /// In en, this message translates to:
  /// **'First'**
  String get compilationsFirst;

  /// No description provided for @compilationsFirstHelp.
  ///
  /// In en, this message translates to:
  /// **'A pack takes the slots ahead of the priority too.'**
  String get compilationsFirstHelp;

  /// No description provided for @exclude.
  ///
  /// In en, this message translates to:
  /// **'Exclude'**
  String get exclude;

  /// No description provided for @excludeHelp.
  ///
  /// In en, this message translates to:
  /// **'Kinds of releases left out of the collection.'**
  String get excludeHelp;

  /// No description provided for @excludeAddOns.
  ///
  /// In en, this message translates to:
  /// **'Add-ons'**
  String get excludeAddOns;

  /// No description provided for @excludeApplications.
  ///
  /// In en, this message translates to:
  /// **'Applications'**
  String get excludeApplications;

  /// No description provided for @excludeAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get excludeAudio;

  /// No description provided for @excludeBadDumps.
  ///
  /// In en, this message translates to:
  /// **'Bad dumps'**
  String get excludeBadDumps;

  /// No description provided for @excludeBios.
  ///
  /// In en, this message translates to:
  /// **'BIOS'**
  String get excludeBios;

  /// No description provided for @excludeBonusDiscs.
  ///
  /// In en, this message translates to:
  /// **'Bonus discs'**
  String get excludeBonusDiscs;

  /// No description provided for @excludeCoverdiscs.
  ///
  /// In en, this message translates to:
  /// **'Coverdiscs'**
  String get excludeCoverdiscs;

  /// No description provided for @excludeDemos.
  ///
  /// In en, this message translates to:
  /// **'Demos'**
  String get excludeDemos;

  /// No description provided for @excludeEducational.
  ///
  /// In en, this message translates to:
  /// **'Educational'**
  String get excludeEducational;

  /// No description provided for @excludeManuals.
  ///
  /// In en, this message translates to:
  /// **'Manuals'**
  String get excludeManuals;

  /// No description provided for @excludeMia.
  ///
  /// In en, this message translates to:
  /// **'Missing dumps (MIA)'**
  String get excludeMia;

  /// No description provided for @excludeMultimedia.
  ///
  /// In en, this message translates to:
  /// **'Multimedia'**
  String get excludeMultimedia;

  /// No description provided for @excludePirate.
  ///
  /// In en, this message translates to:
  /// **'Pirate'**
  String get excludePirate;

  /// No description provided for @excludePreproduction.
  ///
  /// In en, this message translates to:
  /// **'Preproduction'**
  String get excludePreproduction;

  /// No description provided for @excludePromotional.
  ///
  /// In en, this message translates to:
  /// **'Promotional'**
  String get excludePromotional;

  /// No description provided for @excludeUnlicensed.
  ///
  /// In en, this message translates to:
  /// **'Unlicensed'**
  String get excludeUnlicensed;

  /// No description provided for @excludeVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get excludeVideo;

  /// No description provided for @sectionWishlist.
  ///
  /// In en, this message translates to:
  /// **'Wishlist'**
  String get sectionWishlist;

  /// No description provided for @wishlistHelp.
  ///
  /// In en, this message translates to:
  /// **'A JSONC list of titles to collect.'**
  String get wishlistHelp;

  /// No description provided for @noWishlist.
  ///
  /// In en, this message translates to:
  /// **'No wishlist'**
  String get noWishlist;

  /// No description provided for @wishlistMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get wishlistMode;

  /// No description provided for @wishlistAbsolute.
  ///
  /// In en, this message translates to:
  /// **'Absolute'**
  String get wishlistAbsolute;

  /// No description provided for @wishlistAbsoluteHelp.
  ///
  /// In en, this message translates to:
  /// **'Everything listed is kept; the other rules only choose which dump.'**
  String get wishlistAbsoluteHelp;

  /// No description provided for @wishlistSubset.
  ///
  /// In en, this message translates to:
  /// **'Subset'**
  String get wishlistSubset;

  /// No description provided for @wishlistSubsetHelp.
  ///
  /// In en, this message translates to:
  /// **'Listed titles still have to pass the language, region and achievement rules.'**
  String get wishlistSubsetHelp;

  /// No description provided for @sectionStages.
  ///
  /// In en, this message translates to:
  /// **'Stages'**
  String get sectionStages;

  /// No description provided for @stagesHelp.
  ///
  /// In en, this message translates to:
  /// **'Unchecked stages are skipped.'**
  String get stagesHelp;

  /// No description provided for @stageSync.
  ///
  /// In en, this message translates to:
  /// **'Update metadata and DATs'**
  String get stageSync;

  /// No description provided for @stageDownload.
  ///
  /// In en, this message translates to:
  /// **'Download what is missing'**
  String get stageDownload;

  /// No description provided for @stageOrganize.
  ///
  /// In en, this message translates to:
  /// **'Arrange files into the layout'**
  String get stageOrganize;

  /// No description provided for @stagePlaylists.
  ///
  /// In en, this message translates to:
  /// **'Write multi-disc playlists'**
  String get stagePlaylists;

  /// No description provided for @stagePrune.
  ///
  /// In en, this message translates to:
  /// **'Move files outside the selection to .trash'**
  String get stagePrune;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
