/// UI-only marker on forwarded copies. It proves nothing about where the
/// message came from.
const forwardedMarker = 'im.internal_chat.forwarded';

const _textTypes = {'m.text', 'm.notice', 'm.emote'};
const _mediaTypes = {'m.image', 'm.file', 'm.audio', 'm.video'};

/// Extensible-event keys that make an `m.audio` a voice note.
const _voiceKeys = ['org.matrix.msc3245.voice', 'org.matrix.msc1767.audio'];

/// The content of a new message that forwards [source], the decrypted
/// content of a message (after applying edits), or null if it cannot be
/// forwarded.
///
/// Text keeps only its body. Media reuse the original encrypted `file`
/// (`url`, `key`, `iv`, `hashes`) and `info`, including `thumbnail_file`, so
/// nothing is uploaded again; the key travels inside the new encrypted event.
/// Relations (`m.relates_to`), edits and formatted bodies are never copied:
/// they point into the original room.
Map<String, Object?>? forwardContent(Map<String, Object?> source) {
  final msgtype = source['msgtype'];
  final body = source['body'];
  if (msgtype is! String || body is! String) return null;

  if (_textTypes.contains(msgtype)) {
    final text = stripReplyFallback(body);
    if (text.trim().isEmpty) return null;
    return {'msgtype': msgtype, 'body': text, forwardedMarker: true};
  }

  if (_mediaTypes.contains(msgtype)) {
    final file = source['file'];
    final url = source['url'];
    if (file is! Map && url is! String) return null;
    final info = source['info'];
    final filename = source['filename'];
    return {
      'msgtype': msgtype,
      'body': stripReplyFallback(body),
      if (filename is String) 'filename': filename,
      if (file is Map) 'file': _copy(file),
      if (file is! Map && url is String) 'url': url,
      if (info is Map) 'info': _copy(info),
      for (final key in _voiceKeys)
        if (source[key] is Map) key: _copy(source[key]! as Map),
      forwardedMarker: true,
    };
  }
  return null;
}

/// Removes the quoted "> <@user> ..." lines older clients put in front of a
/// reply's body.
String stripReplyFallback(String body) {
  if (!body.startsWith('> <@')) return body;
  final lines = body.split('\n');
  var index = 0;
  while (index < lines.length &&
      (lines[index].startsWith('> ') || lines[index].isEmpty)) {
    index++;
  }
  return lines.sublist(index).join('\n');
}

Map<String, Object?> _copy(Map<Object?, Object?> map) => {
  for (final entry in map.entries)
    entry.key! as String: switch (entry.value) {
      final Map<Object?, Object?> nested => _copy(nested),
      final List<Object?> list => [
        for (final item in list) item is Map ? _copy(item) : item,
      ],
      final value => value,
    },
};
