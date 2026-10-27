import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'outbox_entry.dart';

/// Durable storage for pending messages. In the app it is an SQLCipher
/// database keyed from Keychain/Keystore, so text, attachment bytes and
/// attachment keys are encrypted at rest.
abstract interface class OutboxStore {
  /// Persists [entry] (and its file) before the first attempt.
  Future<void> add(OutboxEntry entry, {Uint8List? file});
  Future<void> update(OutboxEntry entry);

  /// Moves an entry to a new transaction ID, keeping its file.
  Future<void> rename(String oldTxnId, OutboxEntry entry);
  Future<void> remove(String txnId);

  /// Entries of one account, oldest first, without file bytes.
  Future<List<OutboxEntry>> entriesFor(String userId);
  Future<Uint8List?> file(String txnId);
}

final class SqliteOutboxStore implements OutboxStore {
  SqliteOutboxStore._(this._db);

  final Database _db;

  static const _table = 'outbox';

  static Future<SqliteOutboxStore> open(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        txn_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        room_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        has_file INTEGER NOT NULL,
        file BLOB,
        state TEXT NOT NULL,
        attempts INTEGER NOT NULL,
        failures_in_a_row INTEGER NOT NULL,
        first_attempt_at INTEGER,
        last_attempt_at INTEGER,
        next_attempt_at INTEGER,
        last_error TEXT,
        prepared_content TEXT
      )
    ''');
    return SqliteOutboxStore._(db);
  }

  static const _columns = [
    'txn_id',
    'user_id',
    'device_id',
    'room_id',
    'kind',
    'payload',
    'created_at',
    'has_file',
    'state',
    'attempts',
    'failures_in_a_row',
    'first_attempt_at',
    'last_attempt_at',
    'next_attempt_at',
    'last_error',
    'prepared_content',
  ];

  @override
  Future<void> add(OutboxEntry entry, {Uint8List? file}) => _db.insert(_table, {
    ...entry.toRow(),
    'file': file,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> update(OutboxEntry entry) => _db.update(
    _table,
    entry.toRow(),
    where: 'txn_id = ?',
    whereArgs: [entry.txnId],
  );

  @override
  Future<void> rename(String oldTxnId, OutboxEntry entry) => _db.update(
    _table,
    entry.toRow(),
    where: 'txn_id = ?',
    whereArgs: [oldTxnId],
  );

  @override
  Future<void> remove(String txnId) =>
      _db.delete(_table, where: 'txn_id = ?', whereArgs: [txnId]);

  @override
  Future<List<OutboxEntry>> entriesFor(String userId) async {
    final rows = await _db.query(
      _table,
      columns: _columns,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
    return rows.map(OutboxEntry.fromRow).toList();
  }

  @override
  Future<Uint8List?> file(String txnId) async {
    final rows = await _db.query(
      _table,
      columns: ['file'],
      where: 'txn_id = ?',
      whereArgs: [txnId],
    );
    final value = rows.firstOrNull?['file'];
    return value is Uint8List ? value : null;
  }
}
