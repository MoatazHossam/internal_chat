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

/// The two local databases, both SQLCipher with the same key: the SDK store
/// (sync cursor, device keys, room keys, access token) and the outbox of
/// messages not sent yet (text, attachment bytes and attachment keys).
class EncryptedStores {
  const EncryptedStores({required this.sdk, required this.outbox});

  final MatrixSdkDatabase sdk;
  final Database outbox;
}

/// Opens both local databases.
///
/// Fails closed: if the key cannot be read from platform secure storage, or
/// SQLCipher is not linked, or a database does not open with the stored
/// key, this throws [SecureStorageUnavailable]. It never falls back to a
/// plaintext database and never deletes a database the stored key might
/// still open. Files are only removed when the key itself is gone (for
/// example not restored with a device backup): without it they can never be
/// read again.
Future<EncryptedStores> openEncryptedStores(String name) async {
  final ({String value, bool created}) key;
  final String sdkPath;
  final String outboxPath;
  try {
    sdkPath = await _databasePath(name);
    outboxPath = await _databasePath(_outboxName(name));
    key = await _databaseKey();
    if (key.created) {
      await _deleteFiles(sdkPath);
      await _deleteFiles(outboxPath);
    }
  } catch (_) {
    throw const SecureStorageUnavailable();
  }

  final factory = createDatabaseFactoryFfi();
  Database? sdkDatabase;
  try {
    sdkDatabase = await _openEncrypted(
      factory,
      sdkPath,
      key.value,
      migratePlaintext: true,
    );
    final outbox = await _openEncrypted(factory, outboxPath, key.value);
    // No `fileStorageLocation`: with one, the SDK writes decrypted
    // attachments to plain files. Without it, media is never cached on disk.
    final sdk = await MatrixSdkDatabase.init(name, database: sdkDatabase);
    return EncryptedStores(sdk: sdk, outbox: outbox);
  } catch (_) {
    // Includes the StateError thrown when the bundled SQLite is not
    // SQLCipher, and "file is not a database" for a wrong key.
    try {
      await sdkDatabase?.close();
    } catch (_) {
      // Already failing; closing is best effort.
    }
    throw const SecureStorageUnavailable();
  }
}

Future<Database> _openEncrypted(
  DatabaseFactory factory,
  String path,
  String cipher, {
  bool migratePlaintext = false,
}) async {
  final helper = SQfLiteEncryptionHelper(
    factory: factory,
    path: path,
    cipher: cipher,
  );
  // Encrypts a plaintext file left by an older build, if one exists.
  if (migratePlaintext) await helper.ensureDatabaseFileEncrypted();
  final database = await factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) =>
          helper.applyPragmaKey(db, ensureIncrementalAutoVacuum: true),
    ),
  );
  // Reading the schema fails here, not later, if the key is wrong.
  await database.rawQuery('SELECT count(*) FROM sqlite_master');
  return database;
}

/// Deletes both databases and their key after the user signs out. The
/// databases must already be closed.
Future<void> deleteEncryptedStores(String name) async {
  await _deleteFiles(await _databasePath(name));
  await _deleteFiles(await _databasePath(_outboxName(name)));
  await _secureStorage.delete(key: _databaseKeyName);
}

String _outboxName(String name) => '${name}_outbox';

Future<void> _deleteFiles(String path) async {
  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    final file = File('$path$suffix');
    if (await file.exists()) await file.delete();
  }
}

Future<({String value, bool created})> _databaseKey() async {
  final existing = await _secureStorage.read(key: _databaseKeyName);
  if (existing != null) return (value: existing, created: false);

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
  return (value: created, created: true);
}

Future<String> _databasePath(String name) async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return p.join(directory.path, '$name.sqlite');
}
