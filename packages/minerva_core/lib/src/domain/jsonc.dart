/// Text-level edits of a JSONC object that leave comments and formatting alone.
library;

import 'dart:convert';

/// Where one object member sits in the source: [start] is its key's opening
/// quote, [end] is one past its value.
typedef JsoncMember = ({int start, int valueStart, int end});

/// The members of a JSONC object, keyed by name, in source order.
typedef JsoncObject = ({int open, int close, Map<String, JsoncMember> members});

/// The object at [path] below the root object of [source], or null when a
/// step is missing or not an object.
///
/// Throws [FormatException] when [source] is not well-formed.
JsoncObject? jsoncObjectAt(String source, List<String> path) {
  final scanner = _Scanner(source)..skip();
  if (scanner.peek != '{') throw const FormatException('Expected an object.');
  var object = scanner.object();
  for (final key in path) {
    final member = object.members[key];
    if (member == null) return null;
    scanner.at = member.valueStart;
    if (scanner.peek != '{') return null;
    object = scanner.object();
  }
  return object;
}

/// [source] with member [key] of [object] set to [value], already encoded.
///
/// A new member goes after the last one, on its own line, indented like it.
String jsoncPut(String source, JsoncObject object, String key, String value) {
  if (object.members[key] case final member?) {
    return source.replaceRange(member.valueStart, member.end, value);
  }
  final newline = source.contains('\r\n') ? '\r\n' : '\n';
  final entry = '${jsonEncode(key)}: $value';
  final last = object.members.values.lastOrNull;
  if (last != null) {
    final indent = _indentOf(source, last.start) ?? '    ';
    return source.replaceRange(last.end, last.end, ',$newline$indent$entry');
  }
  final outer = _lineIndent(source, object.open);
  final inner = '$outer  ';
  final body = source.substring(object.open + 1, object.close);
  final closing = body.contains('\n') ? '' : '$newline$outer';
  return source.replaceRange(
    object.open + 1,
    object.open + 1,
    '$newline$inner$entry$closing',
  );
}

/// [source] without member [key] of [object]; comments around it stay.
String jsoncRemove(String source, JsoncObject object, String key) {
  final member = object.members[key];
  if (member == null) return source;
  final members = object.members.values.toList();
  final index = members.indexOf(member);
  var from = member.start;
  if (_indentOf(source, from) != null) {
    from = source.lastIndexOf('\n', from - 1) + 1;
  }
  var to = member.end;
  final scanner = _Scanner(source)..at = to;
  scanner.skipBlank();
  final hasComma = scanner.peek == ',';
  if (hasComma) to = scanner.at + 1;
  final lineEnd = source.indexOf('\n', to);
  final rest = source.substring(to, lineEnd < 0 ? source.length : lineEnd);
  if (from != member.start && (rest.trim().isEmpty || _isLineComment(rest))) {
    to = lineEnd < 0 ? source.length : lineEnd + 1;
  }
  var result = source.replaceRange(from, to, '');
  if (!hasComma && index > 0) {
    final comma = _Scanner(source)
      ..at = members[index - 1].end
      ..skip();
    if (comma.peek == ',' && comma.at < from) {
      result = result.replaceRange(comma.at, comma.at + 1, '');
    }
  }
  return result;
}

bool _isLineComment(String text) => text.trimLeft().startsWith('//');

/// The whitespace before [offset] when nothing else precedes it on its line.
String? _indentOf(String source, int offset) {
  final lineStart = source.lastIndexOf('\n', offset - 1) + 1;
  final prefix = source.substring(lineStart, offset);
  return prefix.trim().isEmpty ? prefix : null;
}

String _lineIndent(String source, int offset) {
  final lineStart = source.lastIndexOf('\n', offset - 1) + 1;
  final line = source.substring(lineStart, offset);
  return line.substring(0, line.length - line.trimLeft().length);
}

final class _Scanner {
  _Scanner(this.source);

  final String source;
  int at = 0;

  String? get peek => at < source.length ? source[at] : null;

  /// Skips whitespace and comments.
  void skip() {
    while (at < source.length) {
      if (source.startsWith('//', at)) {
        final end = source.indexOf('\n', at);
        at = end < 0 ? source.length : end;
      } else if (source.startsWith('/*', at)) {
        final end = source.indexOf('*/', at + 2);
        if (end < 0) throw const FormatException('Unterminated comment.');
        at = end + 2;
      } else if (source[at].trim().isEmpty || source[at] == '﻿') {
        at++;
      } else {
        return;
      }
    }
  }

  /// Skips whitespace only, stopping at comments.
  void skipBlank() {
    while (at < source.length && source[at].trim().isEmpty) {
      at++;
    }
  }

  JsoncObject object() {
    final open = at++;
    final members = <String, JsoncMember>{};
    skip();
    if (peek == '}') return (open: open, close: at++, members: members);
    while (true) {
      skip();
      if (peek != '"') throw FormatException('Expected a key.', source, at);
      final start = at;
      final key = string();
      skip();
      if (peek != ':') throw FormatException('Expected ":".', source, at);
      at++;
      skip();
      final valueStart = at;
      value();
      members[key] = (start: start, valueStart: valueStart, end: at);
      skip();
      switch (peek) {
        case ',':
          at++;
        case '}':
          return (open: open, close: at++, members: members);
        default:
          throw FormatException('Expected "," or "}".', source, at);
      }
    }
  }

  String string() {
    final start = at++;
    while (at < source.length && source[at] != '"') {
      at += source[at] == r'\' ? 2 : 1;
    }
    if (at >= source.length) {
      throw FormatException('Unterminated string.', source, start);
    }
    return jsonDecode(source.substring(start, ++at)) as String;
  }

  void value() {
    switch (peek) {
      case '"':
        string();
      case '{':
        object();
      case '[':
        at++;
        skip();
        if (peek == ']') {
          at++;
          return;
        }
        while (true) {
          skip();
          value();
          skip();
          if (peek == ',') {
            at++;
          } else if (peek == ']') {
            at++;
            return;
          } else {
            throw FormatException('Expected "," or "]".', source, at);
          }
        }
      case null:
        throw const FormatException('Unexpected end of input.');
      default:
        final start = at;
        while (at < source.length && !',]} \t\r\n/'.contains(source[at])) {
          at++;
        }
        if (at == start) throw FormatException('Expected a value.', source, at);
    }
  }
}
