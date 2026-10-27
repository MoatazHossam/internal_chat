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

/// What to do about the database key at startup.
enum DatabaseKeyPlan {
  /// Open the databases with the stored key.
  useStored,

  /// First start (or after a reset): create a key; there is nothing to lose.
  createNew,

  /// Data files exist but their key is gone. They can never be read again,
  /// but deleting them is the user's decision, not the app's.
  refuse,
}

DatabaseKeyPlan planDatabaseKey({
  required bool keyStored,
  required bool filesExist,
}) => keyStored
    ? DatabaseKeyPlan.useStored
    : filesExist
    ? DatabaseKeyPlan.refuse
    : DatabaseKeyPlan.createNew;

/// Opens both local databases.
///
/// Fails closed and never deletes anything:
/// * the key cannot be read from platform secure storage, or SQLCipher is
///   not linked: [SecureStorageUnavailable] (retrying may help);
/// * the files exist but the key is missing, or the stored key does not
///   open them: [LocalDataUnreadable]. Only the user can then choose to
///   reset local data ([deleteEncryptedStores]).
///
/// It never falls back to a plaintext database.
Future<EncryptedStores> openEncryptedStores(String name) async {
  final String sdkPath;
  final String outboxPath;
  String? key;
  final bool filesExist;
  try {
    sdkPath = await _databasePath(name);
    outboxPath = await _databasePath(_outboxName(name));
    key = await _secureStorage.read(key: _databaseKeyName);
    filesExist = await _filesExist(sdkPath) || await _filesExist(outboxPath);
  } catch (_) {
    throw const SecureStorageUnavailable();
  }

  switch (planDatabaseKey(keyStored: key != null, filesExist: filesExist)) {
    case DatabaseKeyPlan.refuse:
      throw const LocalDataUnreadable();
    case DatabaseKeyPlan.createNew:
      try {
        key = await _createDatabaseKey();
      } catch (_) {
        throw const SecureStorageUnavailable();
      }
    case DatabaseKeyPlan.useStored:
      break;
  }

  final factory = createDatabaseFactoryFfi();
  Database? sdkDatabase;
  try {
    sdkDatabase = await _openEncrypted(
      factory,
      sdkPath,
      key!,
      migratePlaintext: true,
    );
    final outbox = await _openEncrypted(factory, outboxPath, key);
    // No `fileStorageLocation`: with one, the SDK writes decrypted
    // attachments to plain files. Without it, media is never cached on disk.
    final sdk = await MatrixSdkDatabase.init(name, database: sdkDatabase);
    return EncryptedStores(sdk: sdk, outbox: outbox);
  } on StateError {
    // Thrown by applyPragmaKey when the bundled SQLite is not SQLCipher.
    await _closeQuietly(sdkDatabase);
    throw const SecureStorageUnavailable();
  } catch (_) {
    // For example "file is not a database": the key does not open it.
    await _closeQuietly(sdkDatabase);
    throw const LocalDataUnreadable();
  }
}

Future<void> _closeQuietly(Database? database) async {
  try {
    await database?.close();
  } catch (_) {
    // Already failing; closing is best effort.
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

/// Deletes both databases and their key: after the user signs out, or when
/// the user resets unreadable local data. The databases must be closed.
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

Future<bool> _filesExist(String path) async {
  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    if (await File('$path$suffix').exists()) return true;
  }
  return false;
}

Future<String> _createDatabaseKey() async {
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
