// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'MiNERVA Archivist';

  @override
  String get preview => 'Vista previa';

  @override
  String get apply => 'Aplicar';

  @override
  String get stop => 'Detener';

  @override
  String get showOutput => 'Mostrar salida';

  @override
  String get hideOutput => 'Ocultar salida';

  @override
  String get clear => 'Limpiar';

  @override
  String get clearTooltip => 'Empezar de nuevo con los ajustes por defecto';

  @override
  String get languageMenu => 'Idioma';

  @override
  String get languageSystem => 'Idioma del sistema';

  @override
  String get themeMenu => 'Tema';

  @override
  String get themeSystem => 'Tema del sistema';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get problemCache => 'Carpeta de caché';

  @override
  String get problemProfile => 'Perfil';

  @override
  String get problemSettings => 'Con estos ajustes no se puede ejecutar';

  @override
  String cannotRead(String path, String detail) {
    return 'No se puede leer $path: $detail';
  }

  @override
  String cannotSave(String path, String detail) {
    return 'No se puede guardar $path: $detail';
  }

  @override
  String subjectProblem(String subject, String detail) {
    return '$subject: $detail';
  }

  @override
  String get profileName => 'Nombre del perfil';

  @override
  String get load => 'Cargar';

  @override
  String get save => 'Guardar';

  @override
  String get delete => 'Borrar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get deleteTitle => '¿Borrar el perfil?';

  @override
  String deleteBody(String name, String file) {
    return '«$name» se quita de $file. Los ajustes en pantalla se quedan como están.';
  }

  @override
  String get noProfilesYet =>
      'Aún no hay perfiles. Escribe un nombre y pulsa Guardar.';

  @override
  String get noProfileMatches => 'Ningún perfil coincide; Guardar lo crea.';

  @override
  String get cacheFolder => 'Carpeta de caché';

  @override
  String get cacheFolderHelp =>
      'Donde están profiles.jsonc, los DATs y los metadatos. Se recuerda para el próximo arranque.';

  @override
  String get cachePlaceholder => 'Carpeta con profiles.jsonc';

  @override
  String get folderNotFound => 'No se encuentra la carpeta.';

  @override
  String get noProfilesFile =>
      'Aún no hay profiles.jsonc aquí; al guardar se crea.';

  @override
  String get browse => 'Examinar';

  @override
  String get useFolder => 'Usar carpeta';

  @override
  String get output => 'Salida';

  @override
  String get copyAll => 'Copiar todo';

  @override
  String get dockLeft => 'Acoplar a la izquierda';

  @override
  String get dockBottom => 'Acoplar abajo';

  @override
  String get dockRight => 'Acoplar a la derecha';

  @override
  String get float => 'Flotante';

  @override
  String get hidePanel => 'Ocultar (F12)';

  @override
  String get menuCopy => 'Copiar';

  @override
  String get menuSelectAll => 'Seleccionar todo';

  @override
  String get menuCut => 'Cortar';

  @override
  String get menuPaste => 'Pegar';

  @override
  String get logIdle =>
      'La vista previa muestra lo que haría una ejecución sin tocar ningún archivo. Aplicar lo hace.';

  @override
  String get logStarting => 'Iniciando…';

  @override
  String get logRun => 'Ejecución';

  @override
  String get logPreview => ' (vista previa)';

  @override
  String logSync(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos de metadatos actualizados',
      one: '1 archivo de metadatos actualizado',
    );
    return '$_temp0';
  }

  @override
  String logSyncErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: ', $count errores',
      one: ', 1 error',
    );
    return '$_temp0';
  }

  @override
  String logSelected(int selected, int total) {
    return 'Seleccionados $selected de $total';
  }

  @override
  String logWishlistUnmatched(String entry) {
    return 'La entrada de la wishlist no coincide con nada: $entry';
  }

  @override
  String logAudit(int present, int total, int missing, int unknown) {
    return '$present/$total en disco, $missing faltan, $unknown desconocidos';
  }

  @override
  String logToDownload(int count, String size) {
    return '$count por descargar, $size';
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
    return 'No se distribuye: $name';
  }

  @override
  String logHeld(String name) {
    return 'Retenido por una carpeta curada: $name';
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
    return '$done/$files archivos  $doneSize de $totalSize  $speed/s  $seeds seeds, $peers peers';
  }

  @override
  String logDownloaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos descargados',
      one: '1 archivo descargado',
    );
    return '$_temp0';
  }

  @override
  String logOrganize(String summary) {
    return 'Organizar: $summary';
  }

  @override
  String logPlaylists(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count listas de reproducción',
      one: '1 lista de reproducción',
    );
    return '$_temp0';
  }

  @override
  String logPruned(int count, String folder) {
    return '$count movidos a $folder';
  }

  @override
  String get notUsed => 'Sin usar:';

  @override
  String get dropToLeaveOut => 'Arrastra una insignia aquí para quitarla.';

  @override
  String get filter => 'Filtrar';

  @override
  String get filterOrType => 'Filtra o escribe un valor';

  @override
  String useTyped(String value) {
    return 'Usar «$value»';
  }

  @override
  String get nothingMatches => 'Nada coincide.';

  @override
  String get sectionCollection => 'Colección';

  @override
  String get systems => 'Sistemas';

  @override
  String get systemsHelp =>
      'DATs de la caché, un archivo .dat o una carpeta con varios. Si hay varios, se fusionan en una sola colección.';

  @override
  String get noSystem => 'Aún no hay sistemas.';

  @override
  String get addSystem => 'Añadir sistema';

  @override
  String get browseDat => 'Examinar .dat…';

  @override
  String get romFolder => 'Carpeta de ROMs';

  @override
  String get romFolderHelp =>
      'Donde vive la colección. Vacía, solo se previsualiza la selección.';

  @override
  String get noRomFolder => 'Sin carpeta de ROMs';

  @override
  String get layout => 'Disposición';

  @override
  String get layoutHelp =>
      'Cómo queda cada juego dentro de la carpeta de ROMs.';

  @override
  String get layoutZip => 'Zip';

  @override
  String get layoutZipInFolder => 'Zip dentro de una carpeta';

  @override
  String get layoutExtracted => 'Extraído';

  @override
  String get layoutExtractedInFolder => 'Extraído dentro de una carpeta';

  @override
  String layoutEsDe(String shape) {
    return '$shape, que ES-DE abre como una sola entrada';
  }

  @override
  String get protectedFolders => 'Carpetas protegidas';

  @override
  String get protectedFoldersHelp =>
      'Carpetas de primer nivel dentro de la carpeta de ROMs que nunca se tocan.';

  @override
  String get addFolder => 'Añadir carpeta';

  @override
  String get searchDepth => 'Profundidad de búsqueda';

  @override
  String get searchDepthHelp =>
      'Cuántos niveles de carpetas bajo la carpeta de ROMs se revisan.';

  @override
  String get unlimited => 'Sin límite';

  @override
  String get sectionOneRelease => 'Elegir una versión por juego';

  @override
  String get priority => 'Prioridad';

  @override
  String get priorityHelp =>
      'Los desempates en el orden en que deciden. Arrastra para reordenar, o hacia abajo para quitar uno. La región sigue aplicándose aunque la quites, después de los demás.';

  @override
  String get axisLang => 'Idioma';

  @override
  String get axisRegion => 'Región';

  @override
  String get axisRa => 'RetroAchievements';

  @override
  String get axisLangcount => 'Número de idiomas';

  @override
  String get languageCount => 'Número de idiomas';

  @override
  String get languageCountHelp =>
      'En qué sentido cuenta el número de idiomas de un dump.';

  @override
  String get langMost => 'Más idiomas';

  @override
  String get langMostHelp => 'Gana el dump que trae más idiomas.';

  @override
  String get langFewest => 'Menos idiomas';

  @override
  String get langFewestHelp =>
      'Gana el dump más pequeño; útil con discos grandes.';

  @override
  String get languages => 'Idiomas';

  @override
  String get languagesHelp =>
      'Los primeros tienen prioridad. Un código cubre también sus variantes: Es cubre Es-MX.';

  @override
  String get noLanguage => 'Sin idiomas: no se prefiere ninguno.';

  @override
  String get addLanguage => 'Añadir idioma';

  @override
  String get anyOtherLanguage => 'Cualquier otro idioma';

  @override
  String get regions => 'Regiones';

  @override
  String get regionsHelp =>
      'Las primeras tienen prioridad. Vacío conserva el orden completo por defecto.';

  @override
  String get defaultOrder => 'Orden por defecto.';

  @override
  String get addRegion => 'Añadir región';

  @override
  String get achievements => 'Logros';

  @override
  String get achievementsHelp =>
      'Si un juego necesita un set de RetroAchievements para conservarse.';

  @override
  String get achievementsOff => 'No se exigen';

  @override
  String get achievementsAny => 'Cualquier dump';

  @override
  String get achievementsAnyHelp =>
      'El juego tiene un set; la prioridad elige el dump.';

  @override
  String get achievementsApproved => 'Solo dumps aprobados';

  @override
  String get achievementsApprovedHelp =>
      'Solo los dumps para los que se hizo el set.';

  @override
  String get supersets => 'Ediciones con contenido extra';

  @override
  String get supersetsPrefer => 'Preferir';

  @override
  String get supersetsPreferHelp =>
      'Una edición que contiene a la original ocupa su lugar.';

  @override
  String get supersetsIgnore => 'Ignorar';

  @override
  String get supersetsIgnoreHelp => 'Se trata como cualquier otra versión.';

  @override
  String get compilations => 'Recopilatorios';

  @override
  String get compilationsNever => 'Nunca';

  @override
  String get compilationsNeverHelp =>
      'Un recopilatorio solo compite en su propio grupo.';

  @override
  String get compilationsFill => 'Cubrir huecos';

  @override
  String get compilationsFillHelp =>
      'Un recopilatorio solo sustituye a juegos sin versión propia.';

  @override
  String get compilationsPrefer => 'Preferir';

  @override
  String get compilationsPreferHelp =>
      'Un recopilatorio ocupa los huecos; la prioridad sigue decidiendo antes.';

  @override
  String get compilationsFirst => 'Primero';

  @override
  String get compilationsFirstHelp =>
      'Un recopilatorio ocupa los huecos incluso antes que la prioridad.';

  @override
  String get exclude => 'Excluir';

  @override
  String get excludeHelp =>
      'Tipos de versiones que quedan fuera de la colección.';

  @override
  String get excludeAddOns => 'Complementos';

  @override
  String get excludeApplications => 'Aplicaciones';

  @override
  String get excludeAudio => 'Audio';

  @override
  String get excludeBadDumps => 'Dumps defectuosos';

  @override
  String get excludeBios => 'BIOS';

  @override
  String get excludeBonusDiscs => 'Discos extra';

  @override
  String get excludeCoverdiscs => 'Discos de revista';

  @override
  String get excludeDemos => 'Demos';

  @override
  String get excludeEducational => 'Educativos';

  @override
  String get excludeManuals => 'Manuales';

  @override
  String get excludeMia => 'Dumps perdidos (MIA)';

  @override
  String get excludeMultimedia => 'Multimedia';

  @override
  String get excludePirate => 'Piratas';

  @override
  String get excludePreproduction => 'Preproducción';

  @override
  String get excludePromotional => 'Promocionales';

  @override
  String get excludeUnlicensed => 'Sin licencia';

  @override
  String get excludeVideo => 'Vídeo';

  @override
  String get sectionWishlist => 'Wishlist';

  @override
  String get wishlistHelp => 'Una lista JSONC de títulos a coleccionar.';

  @override
  String get noWishlist => 'Sin wishlist';

  @override
  String get wishlistMode => 'Modo';

  @override
  String get wishlistAbsolute => 'Absoluto';

  @override
  String get wishlistAbsoluteHelp =>
      'Se conserva todo lo listado; las demás reglas solo eligen el dump.';

  @override
  String get wishlistSubset => 'Subconjunto';

  @override
  String get wishlistSubsetHelp =>
      'Los títulos listados aún deben cumplir las reglas de idioma, región y logros.';

  @override
  String get sectionStages => 'Etapas';

  @override
  String get stagesHelp => 'Las etapas sin marcar se omiten.';

  @override
  String get stageSync => 'Actualizar metadatos y DATs';

  @override
  String get stageDownload => 'Descargar lo que falta';

  @override
  String get stageOrganize => 'Ordenar los archivos según la disposición';

  @override
  String get stagePlaylists => 'Escribir listas de reproducción multidisco';

  @override
  String get stagePrune => 'Mover a .trash lo que está fuera de la selección';
}
