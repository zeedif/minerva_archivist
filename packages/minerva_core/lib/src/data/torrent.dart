/// `.torrent` metadata, read locally so a selective download can be planned
/// without contacting the swarm.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// One file inside a torrent. [index] is 0-based, in `info.files` order.
final class TorrentFile {
  const TorrentFile({
    required this.index,
    required this.path,
    required this.length,
  });

  final int index;

  /// `/`-separated, torrent name included.
  final String path;
  final int length;

  String get basename => p.posix.basename(path);
}

final class TorrentManifest {
  const TorrentManifest({
    required this.name,
    required this.infoHash,
    required this.files,
  });

  /// Decodes a bencoded `.torrent`.
  ///
  /// Throws [FormatException] when [bytes] is not one.
  factory TorrentManifest.parse(Uint8List bytes) {
    final decoder = _Bencode(bytes);
    final Object root;
    try {
      root = decoder.decode();
    } on RangeError {
      throw const FormatException('Torrent data is truncated.');
    }
    if (root case {'info': final Map<String, Object> info}) {
      final name = _text(info['name']);
      final files = switch (info['files']) {
        final List<Object> entries => [
          for (final (index, entry) in entries.indexed)
            if (entry case {
              'length': final int length,
              'path': final List path,
            })
              TorrentFile(
                index: index,
                path: [name, ...path.map(_text)].join('/'),
                length: length,
              ),
        ],
        _ => [
          TorrentFile(
            index: 0,
            path: name,
            length: info['length'] as int? ?? 0,
          ),
        ],
      };
      return TorrentManifest(
        name: name,
        infoHash: sha1
            .convert(bytes.sublist(decoder.infoStart!, decoder.infoEnd!))
            .toString(),
        files: files,
      );
    }
    throw const FormatException('Torrent has no info dictionary.');
  }

  final String name;

  /// Lowercase hex SHA-1 of the `info` dictionary.
  final String infoHash;
  final List<TorrentFile> files;

  static String _text(Object? raw) =>
      raw is Uint8List ? utf8.decode(raw, allowMalformed: true) : '';
}

/// Bencode decoder that records the byte range of the top-level `info` value.
final class _Bencode {
  _Bencode(this.data);

  final Uint8List data;
  var _pos = 0;
  int? infoStart;
  int? infoEnd;

  static const _i = 0x69, _l = 0x6c, _d = 0x64, _e = 0x65, _colon = 0x3a;

  Object decode() => switch (data[_pos]) {
    _i => _int(),
    _l => _list(),
    _d => _dict(),
    _ => _string(),
  };

  int _int() {
    final start = ++_pos;
    while (data[_pos] != _e) {
      _pos++;
    }
    return int.parse(ascii.decode(Uint8List.sublistView(data, start, _pos++)));
  }

  Uint8List _string() {
    var length = 0;
    while (data[_pos] != _colon) {
      final digit = data[_pos++] - 0x30;
      if (digit < 0 || digit > 9) {
        throw const FormatException('Malformed bencode string length.');
      }
      length = length * 10 + digit;
    }
    final start = ++_pos;
    _pos += length;
    return data.sublist(start, _pos);
  }

  List<Object> _list() {
    _pos++;
    final list = <Object>[];
    while (data[_pos] != _e) {
      list.add(decode());
    }
    _pos++;
    return list;
  }

  Map<String, Object> _dict() {
    final depth = _depth++;
    _pos++;
    final map = <String, Object>{};
    while (data[_pos] != _e) {
      final key = utf8.decode(_string(), allowMalformed: true);
      final start = _pos;
      map[key] = decode();
      if (depth == 0 && key == 'info') {
        infoStart = start;
        infoEnd = _pos;
      }
    }
    _pos++;
    _depth--;
    return map;
  }

  var _depth = 0;
}
