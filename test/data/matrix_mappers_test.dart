import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/data/matrix/matrix_mappers.dart';
import 'package:internal_chat/data/matrix/outbox/forward_content.dart';
import 'package:internal_chat/data/matrix/outbox/outbox_entry.dart';
import 'package:internal_chat/models/chat_message.dart';
import 'package:matrix/matrix.dart';
// Not exported by the SDK's public library; needed to build a Timeline
// without a sync loop.
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _me = '@me:example.org';
const _bob = '@bob:example.org';

void main() {
  late Client client;
  late Room room;

  setUp(() async {
    final database = await MatrixSdkDatabase.init(
      'mapper_test_${DateTime.now().microsecondsSinceEpoch}',
      database: await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      ),
      sqfliteFactory: databaseFactoryFfi,
    );
    client = Client('mapper_test', database: database);
    client.setUserId(_me);
    room = Room(
      id: '!room:example.org',
      client: client,
      // Bob has read up to $2.
      receiptState: LatestReceiptState.fromJson({
        'global': {
          'others': {
            _bob: {'e': r'$2', 'ts': 2000},
          },
        },
      }),
    );
    // Known members, so the SDK does not look them up in the background
    // (which would outlive the test's database).
    for (final (id, name) in [(_me, 'Me'), (_bob, 'Bob')]) {
      room.setState(
        Event(
          type: EventTypes.RoomMember,
          content: {'membership': 'join', 'displayname': name},
          eventId: '\$member-$id',
          senderId: id,
          stateKey: id,
          originServerTs: DateTime(2026),
          room: room,
        ),
      );
    }
  });

  tearDown(() => client.dispose(closeDatabase: true));

  Event event(
    String id,
    String sender,
    Map<String, Object?> content, {
    String type = EventTypes.Message,
    String? stateKey,
    int ts = 0,
    Map<String, Object?>? unsigned,
  }) => Event.fromMatrixEvent(
    MatrixEvent(
      type: type,
      content: content,
      eventId: id,
      senderId: sender,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
      stateKey: stateKey,
      unsigned: unsigned,
    ),
    room,
  );

  Timeline timelineOf(List<Event> newestFirst) => Timeline(
    room: room,
    chunk: TimelineChunk(events: newestFirst),
  );

  test('maps a timeline to domain messages', () {
    final timeline = timelineOf([
      // A reaction from me on Bob's message: folded into $4.
      event(
        r'$6',
        _me,
        {
          'm.relates_to': {
            'rel_type': RelationshipTypes.reaction,
            'event_id': r'$4',
            'key': '👍',
          },
        },
        type: EventTypes.Reaction,
        ts: 6000,
      ),
      // An edit of $2: folded into $2.
      event(r'$5', _me, {
        'msgtype': MessageTypes.Text,
        'body': '* first, edited',
        'm.new_content': {
          'msgtype': MessageTypes.Text,
          'body': 'first, edited',
        },
        'm.relates_to': {'rel_type': RelationshipTypes.edit, 'event_id': r'$2'},
      }, ts: 5000),
      event(r'$4', _bob, {
        'msgtype': MessageTypes.Text,
        'body': 'hello',
      }, ts: 4000),
      event(r'$3', _me, {
        'msgtype': MessageTypes.Text,
        'body': 'second',
      }, ts: 3000),
      event(r'$2', _me, {
        'msgtype': MessageTypes.Text,
        'body': 'first',
      }, ts: 2000),
      // State events are not message-list items.
      event(
        r'$1',
        _bob,
        {'membership': 'join'},
        type: EventTypes.RoomMember,
        stateKey: _bob,
        ts: 1000,
      ),
      // Could not be decrypted: the SDK puts the error text in `body`.
      event(
        r'$0',
        _bob,
        {
          'msgtype': MessageTypes.BadEncrypted,
          'body': 'Exception: internal decryption detail',
          'algorithm': AlgorithmTypes.megolmV1AesSha2,
          'session_id': 'session',
          'sender_key': 'key',
          'ciphertext': 'xyz',
        },
        type: EventTypes.Encrypted,
        ts: 500,
      ),
    ]);

    final messages = mapTimeline(timeline);
    timeline.cancelSubscriptions();

    expect(messages.map((m) => m.id), [r'$4', r'$3', r'$2', r'$0']);

    final hello = messages[0];
    expect(hello.isOwn, isFalse);
    expect(hello.senderId.value, _bob);
    expect(hello.reactions.single.key, '👍');
    expect(hello.reactions.single.includesMe, isTrue);

    // Newer than Bob's receipt: sent, not read. There is no "delivered".
    expect(messages[1].status, MessageDeliveryStatus.sent);
    expect(messages[1].canEdit, isTrue);

    final first = messages[2];
    expect(first.status, MessageDeliveryStatus.read);
    expect(first.edited, isTrue);
    expect(first.body, 'first, edited');

    final undecryptable = messages[3];
    expect(undecryptable.kind, MessageKind.undecryptable);
    expect(undecryptable.body, isEmpty, reason: 'never show SDK error text');
  });

  test('pending and failed local echoes keep their local ID', () {
    final timeline = timelineOf([
      event(
        'txn-failed',
        _me,
        {'msgtype': MessageTypes.Text, 'body': 'b'},
        unsigned: {
          messageSendingStatusKey: EventStatus.error.intValue,
          'transaction_id': 'txn-failed',
        },
      ),
      event(
        'txn-sending',
        _me,
        {'msgtype': MessageTypes.Text, 'body': 'a'},
        ts: DateTime.now().millisecondsSinceEpoch,
        unsigned: {
          messageSendingStatusKey: EventStatus.sending.intValue,
          'transaction_id': 'txn-sending',
        },
      ),
    ]);

    final messages = mapTimeline(timeline);
    timeline.cancelSubscriptions();

    expect(messages[0].status, MessageDeliveryStatus.failed);
    expect(messages[0].localId?.value, 'txn-failed');
    expect(messages[0].canEdit, isFalse);
    expect(messages[1].status, MessageDeliveryStatus.pending);
    expect(messages[1].localId?.value, 'txn-sending');
  });

  test('classifies message kinds', () {
    Event message(Map<String, Object?> content) => event(r'$x', _bob, content);

    expect(
      kindOf(message({'msgtype': MessageTypes.Image, 'body': 'a.png'})),
      MessageKind.image,
    );
    expect(
      kindOf(message({'msgtype': MessageTypes.File, 'body': 'a.pdf'})),
      MessageKind.file,
    );
    expect(
      kindOf(
        message({
          'msgtype': MessageTypes.Audio,
          'body': 'voice',
          'org.matrix.msc3245.voice': <String, Object?>{},
        }),
      ),
      MessageKind.voice,
    );
    expect(
      kindOf(message({'msgtype': MessageTypes.Audio, 'body': 'song'})),
      MessageKind.audio,
    );
    expect(
      kindOf(message({'msgtype': 'com.example.custom', 'body': '?'})),
      MessageKind.unsupported,
    );
    expect(
      kindOf(event(r'$p', _bob, {}, type: 'm.poll.start')),
      MessageKind.unsupported,
    );
  });

  test('verification events are not message-list items', () {
    expect(
      isTimelineItem(
        event(r'$v', _bob, {
          'msgtype': 'm.key.verification.request',
        }, type: 'm.key.verification.ready'),
      ),
      isFalse,
    );
  });

  test('marks forwarded messages', () {
    final timeline = timelineOf([
      event(r'$f', _bob, {
        'msgtype': MessageTypes.Text,
        'body': 'passed on',
        forwardedMarker: true,
      }, ts: 1000),
    ]);
    expect(mapTimeline(timeline).single.forwarded, isTrue);
  });

  group('outbox entries', () {
    OutboxEntry entry(
      String txnId, {
      OutboxKind kind = OutboxKind.text,
      Map<String, Object?> payload = const {'body': 'hi'},
      OutboxState state = OutboxState.queued,
      SendErrorClass? lastError,
      int at = 0,
    }) => OutboxEntry(
      txnId: txnId,
      userId: _me,
      deviceId: 'DEVICE',
      roomId: room.id,
      kind: kind,
      payload: payload,
      createdAt: DateTime.fromMillisecondsSinceEpoch(10000 + at),
      state: state,
      lastError: lastError,
    );

    test('show their state, newest first', () {
      final timeline = timelineOf([
        event(r'$1', _bob, {'msgtype': MessageTypes.Text, 'body': 'x'}),
      ]);
      final messages = mapOutbox(
        [
          entry('sending', at: 1),
          entry('waiting', lastError: SendErrorClass.network, at: 2),
          entry(
            'failed',
            state: OutboxState.failed,
            lastError: SendErrorClass.uncertain,
            at: 3,
          ),
        ],
        timeline,
        online: true,
        isInFlight: (txnId) => txnId == 'sending',
      );

      expect(messages.map((m) => m.id), ['failed', 'waiting', 'sending']);
      expect(messages[2].status, MessageDeliveryStatus.pending);
      expect(messages[2].canDelete, isFalse);
      expect(messages[1].status, MessageDeliveryStatus.waitingForNetwork);
      expect(messages[0].status, MessageDeliveryStatus.failed);
      expect(messages[0].failureReason, SendFailureReason.uncertain);
      expect(messages.every((m) => m.isOwn && m.localId != null), isTrue);
    });

    test('show as waiting while offline', () {
      final message = mapOutbox(
        [entry('t1')],
        timelineOf([]),
        online: false,
        isInFlight: (_) => false,
      ).single;
      expect(message.status, MessageDeliveryStatus.waitingForNetwork);
      expect(message.isPending, isTrue);
    });

    test('map files, voice notes and forwards', () {
      final messages = mapOutbox(
        [
          entry(
            'img',
            kind: OutboxKind.file,
            payload: const {
              'name': 'p.png',
              'mimeType': 'image/png',
              'size': 10,
            },
            at: 3,
          ),
          entry(
            'voice',
            kind: OutboxKind.voice,
            payload: const {'name': 'v.m4a', 'durationMs': 4200},
            at: 2,
          ),
          entry(
            'fwd',
            kind: OutboxKind.forward,
            payload: const {
              'content': {
                'msgtype': 'm.file',
                'body': 'report.pdf',
                'info': {'mimetype': 'application/pdf', 'size': 99},
              },
            },
            at: 1,
          ),
        ],
        timelineOf([]),
        online: true,
        isInFlight: (_) => false,
      );

      expect(messages[0].kind, MessageKind.image);
      expect(messages[0].attachmentSizeBytes, 10);
      expect(messages[1].kind, MessageKind.voice);
      expect(messages[1].attachmentDurationMs, 4200);
      expect(messages[2].kind, MessageKind.file);
      expect(messages[2].forwarded, isTrue);
      expect(messages[2].attachmentName, 'report.pdf');
      expect(messages[2].attachmentSizeBytes, 99);
    });
  });
}
