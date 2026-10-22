import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/chat_failure.dart';

const _databaseKeyName = 'matrix_database_key';

/// Keychain items are readable only while the device is unlocked, never
/// leave this device and are not restored from backups. Android uses
/// Keystore-backed storage.
const _secureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

/// Opens the SDK store as an SQLCipher database. The SDK keeps the sync
/// cursor, device keys, room keys and access token in it; the app does not
/// duplicate them.
///
/// Fails closed: if the key cannot be read from platform secure storage or
/// SQLCipher is not linked, this throws [SecureStorageUnavailable] instead of
/// falling back to a plaintext database.
Future<MatrixSdkDatabase> openEncryptedMatrixStore(String name) async {
  final String cipher;
  final String path;
  try {
    cipher = await _databaseKey();
    path = await _databasePath(name);
  } catch (_) {
    throw const SecureStorageUnavailable();
  }

  try {
    return await _open(name, path, cipher);
  } on StateError {
    // Thrown by applyPragmaKey when the bundled SQLite is not SQLCipher.
    throw const SecureStorageUnavailable();
  } catch (_) {
    // The file exists but this key cannot open it (for example the key was
    // lost with a device restore). Without the key its contents are
    // unreadable, so start a new encrypted store; messages come back from the
    // server and older keys from the key backup.
    await _deleteFiles(path);
    try {
      return await _open(name, path, cipher);
    } catch (_) {
      throw const SecureStorageUnavailable();
    }
  }
}

Future<MatrixSdkDatabase> _open(String name, String path, String cipher) async {
  final factory = createDatabaseFactoryFfi();
  final helper = SQfLiteEncryptionHelper(
    factory: factory,
    path: path,
    cipher: cipher,
  );
  // Encrypts a plaintext file left by an older build, if one exists.
  await helper.ensureDatabaseFileEncrypted();
  final database = await factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) =>
          helper.applyPragmaKey(db, ensureIncrementalAutoVacuum: true),
    ),
  );
  // No `fileStorageLocation`: with one, the SDK writes decrypted attachments
  // to plain files. Without it, media is never cached on disk.
  return MatrixSdkDatabase.init(name, database: database);
}

/// Deletes the database files and their key after the user signs out. The
/// database must already be closed.
Future<void> deleteEncryptedMatrixStore(String name) async {
  await _deleteFiles(await _databasePath(name));
  await _secureStorage.delete(key: _databaseKeyName);
}

Future<void> _deleteFiles(String path) async {
  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    final file = File('$path$suffix');
    if (await file.exists()) await file.delete();
  }
}

Future<String> _databaseKey() async {
  final existing = await _secureStorage.read(key: _databaseKeyName);
  if (existing != null) return existing;

  final random = Random.secure();
  final bytes = Uint8List.fromList(
    List<int>.generate(32, (_) => random.nextInt(256)),
  );
  final created = base64UrlEncode(bytes);
  await _secureStorage.write(key: _databaseKeyName, value: created);

  // Read back to make sure the platform really stored it; otherwise the next
  // launch could not open the database.
  final stored = await _secureStorage.read(key: _databaseKeyName);
  if (stored != created) throw const SecureStorageUnavailable();
  return created;
}

Future<String> _databasePath(String name) async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return p.join(directory.path, '$name.sqlite');
}
