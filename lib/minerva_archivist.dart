/// MiNERVA Archivist — public API.
///
/// A dependency-free Dart core for auditing, filtering (1G1R), and selectively
/// downloading ROM sets, with its own clone-grouping and
/// RetroAchievements-tagging engine.
library;

// Models (parse-level entities).
export 'src/models/dat.dart';
export 'src/models/metadata.dart';

// Data (I/O boundaries + implementations).
export 'src/data/archive_source.dart';
export 'src/data/aria2_client.dart';
export 'src/data/dat_loader.dart';
export 'src/data/file_scanner.dart';
export 'src/data/metadata_repository.dart';
export 'src/data/torrent.dart';

// Domain (pipeline stages; result types live with their producers).
export 'src/domain/auditor.dart';
export 'src/domain/download.dart';
export 'src/domain/enrichment.dart';
export 'src/domain/library.dart';
export 'src/domain/organize.dart';
export 'src/domain/selection.dart';

// CLI.
export 'src/cli/runner.dart' show runCli;
