import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/data/matrix/outbox/matrix_outbox_transport.dart';

final _until = DateTime.fromMillisecondsSinceEpoch(1_000_000);

Map<String, Object?> _event(String id, int ts) => {
  'event_id': id,
  'origin_server_ts': ts,
};

/// A room history served page by page; `null` ends it (no `end` token).
Future<bool?> _search(
  List<HistoryPage> pages, {
  String target = r'$target',
  int maxPages = 20,
  List<String?>? requested,
}) {
  var index = 0;
  return searchHistory(
    fetchPage: (from) async {
      requested?.add(from);
      return pages[index++];
    },
    isTarget: (event) => event['event_id'] == target,
    until: _until,
    maxPages: maxPages,
  );
}

void main() {
  test('keeps paging past empty pages that have a next token', () async {
    final requested = <String?>[];
    final found = await _search([
      (events: const [], end: 't1'),
      (events: const [], end: 't2'),
      (events: [_event(r'$target', 2_000_000)], end: 't3'),
    ], requested: requested);

    expect(found, isTrue);
    expect(requested, [null, 't1', 't2']);
  });

  test('an empty last page without a token means not delivered', () async {
    expect(
      await _search([
        (events: [_event(r'$other', 2_000_000)], end: 't1'),
        (events: const [], end: null),
      ]),
      isFalse,
    );
  });

  test('stops once history is older than the first attempt', () async {
    expect(
      await _search([
        (events: [_event(r'$old', 900_000)], end: 't1'),
        (events: [_event(r'$target', 800_000)], end: 't2'),
      ]),
      isFalse,
    );
  });

  test('cannot tell when the page budget runs out', () async {
    expect(
      await _search([
        for (var i = 0; i < 3; i++) (events: const [], end: 't$i'),
      ], maxPages: 3),
      isNull,
    );
  });

  test('cannot tell when the server does not move on', () async {
    expect(
      await _search([
        (events: const [], end: 't1'),
        (events: const [], end: 't1'),
      ]),
      isNull,
    );
  });
}
