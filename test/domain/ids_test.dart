import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/domain/ids.dart';

void main() {
  const server = 'secure-chat-poc.duckdns.org';

  group('parseUserId', () {
    test('accepts a full Matrix ID', () {
      expect(
        parseUserId('@moataz:$server', defaultServer: 'other.example'),
        const UserId('@moataz:$server'),
      );
    });

    test('completes a bare name with the default server', () {
      expect(
        parseUserId(' moataz ', defaultServer: server),
        const UserId('@moataz:$server'),
      );
      expect(
        parseUserId('@moataz', defaultServer: server),
        const UserId('@moataz:$server'),
      );
    });

    test('lower-cases the localpart only', () {
      expect(
        parseUserId('@Moataz:Example.ORG', defaultServer: server),
        const UserId('@moataz:Example.ORG'),
      );
    });

    test('rejects empty and malformed input', () {
      expect(parseUserId('', defaultServer: server), isNull);
      expect(parseUserId('two words', defaultServer: server), isNull);
      expect(parseUserId('@:$server', defaultServer: server), isNull);
      expect(parseUserId('name', defaultServer: ''), isNull);
    });
  });

  test('UserId exposes its server', () {
    expect(const UserId('@a:$server').server, server);
    expect(const UserId('@a').server, '');
  });

  test('LocalMessageId.generate creates a new ID each time', () {
    final ids = {for (var i = 0; i < 100; i++) LocalMessageId.generate()};
    expect(ids, hasLength(100));
  });
}
