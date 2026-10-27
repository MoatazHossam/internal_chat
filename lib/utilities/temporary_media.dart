import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _directoryName = 'internal_chat_media';

/// Older builds wrote recordings and decrypted voice notes straight into the
/// temporary directory.
final _legacyNames = RegExp(r'^(vn|voice)-\d+\.(m4a|ogg|mp3|wav)$');

/// Plaintext media that has to exist as a file for a moment: a recording
/// until its bytes are read, a decrypted voice note while the platform
/// player plays it. Everything lives in one directory, so files left behind
/// when the app is killed are removed at the next start and at sign-out.
Future<Directory> temporaryMediaDirectory() async {
  final base = await getTemporaryDirectory();
  final directory = Directory(p.join(base.path, _directoryName));
  await directory.create(recursive: true);
  return directory;
}

/// Deletes all temporary plaintext media, including the file picker's
/// copies. Call when nothing is playing or recording.
Future<void> deleteTemporaryMedia() async {
  if (kIsWeb) return;
  try {
    final base = await getTemporaryDirectory();
    final directory = Directory(p.join(base.path, _directoryName));
    if (await directory.exists()) await directory.delete(recursive: true);
    await for (final entity in base.list()) {
      if (entity is File && _legacyNames.hasMatch(p.basename(entity.path))) {
        await entity.delete();
      }
    }
  } catch (_) {
    // Best effort; the next start tries again.
  }
  try {
    await FilePicker.platform.clearTemporaryFiles();
  } catch (_) {
    // Not supported on every platform.
  }
}
