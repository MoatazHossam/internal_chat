import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/data/matrix/outbox/outbox_entry.dart';
import 'package:internal_chat/data/matrix/outbox/outbox_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late SqliteOutboxStore store;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    store = await SqliteOutboxStore.open(database);
  });

  tearDown(() => database.close());

  final created = DateTime.fromMillisecondsSinceEpoch(1_000_000);

  OutboxEntry entry(String txnId, {String user = '@me:x', int at = 0}) =>
      OutboxEntry(
        txnId: txnId,
        userId: user,
        deviceId: 'DEVICE',
        roomId: '!room:x',
        kind: OutboxKind.file,
        payload: const {'name': 'a.pdf', 'mimeType': 'application/pdf'},
        createdAt: created.add(Duration(seconds: at)),
        hasFile: true,
      );

  test('round-trips every field, oldest first, per account', () async {
    final failed = entry('b', at: 2).copyWith(
      state: OutboxState.failed,
      attempts: 2,
      failuresInARow: 3,
      firstAttemptAt: created,
      lastAttemptAt: created,
      nextAttemptAt: created,
      lastError: SendErrorClass.uncertain,
      preparedContent: {
        'file': {'url': 'mxc://x/y'},
      },
    );
    await store.add(failed, file: Uint8List.fromList([1, 2]));
    await store.add(entry('a', at: 1));
    await store.add(entry('other', user: '@other:x'));

    final entries = await store.entriesFor('@me:x');
    expect(entries.map((e) => e.txnId), ['a', 'b']);
    final read = entries[1];
    expect(read.state, OutboxState.failed);
    expect(read.attempts, 2);
    expect(read.failuresInARow, 3);
    expect(read.firstAttemptAt, created);
    expect(read.lastError, SendErrorClass.uncertain);
    expect(read.preparedContent, {
      'file': {'url': 'mxc://x/y'},
    });
    expect(read.fileName, 'a.pdf');
    expect(await store.file('b'), [1, 2]);
  });

  test('renaming keeps the file; removing deletes it', () async {
    await store.add(entry('old'), file: Uint8List.fromList([7]));
    await store.rename('old', entry('new'));

    expect(await store.file('old'), isNull);
    expect(await store.file('new'), [7]);

    await store.remove('new');
    expect(await store.file('new'), isNull);
    expect(await store.entriesFor('@me:x'), isEmpty);
  });
}
