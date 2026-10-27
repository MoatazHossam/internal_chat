import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/data/matrix/outbox/forward_content.dart';

void main() {
  test('text keeps only the body, not the relation or formatting', () {
    final content = forwardContent({
      'msgtype': 'm.text',
      'body': '> <@bob:example.org> earlier\n\nthe answer',
      'format': 'org.matrix.custom.html',
      'formatted_body': '<mx-reply>…</mx-reply>the answer',
      'm.relates_to': {
        'm.in_reply_to': {'event_id': r'$original'},
      },
    });

    expect(content, {
      'msgtype': 'm.text',
      'body': 'the answer',
      forwardedMarker: true,
    });
  });

  test('media reuse the encrypted file, info and voice markers', () {
    final file = {
      'url': 'mxc://example.org/abc',
      'mimetype': 'audio/mp4',
      'v': 'v2',
      'key': {'k': 'secret', 'alg': 'A256CTR'},
      'iv': 'iv',
      'hashes': {'sha256': 'hash'},
    };
    final source = {
      'msgtype': 'm.audio',
      'body': 'voice-message.m4a',
      'filename': 'voice-message.m4a',
      'file': file,
      'info': {
        'mimetype': 'audio/mp4',
        'size': 1234,
        'duration': 4200,
        'thumbnail_file': {'url': 'mxc://example.org/thumb'},
      },
      'org.matrix.msc3245.voice': <String, Object?>{},
      'org.matrix.msc1767.audio': {'duration': 4200},
      'm.relates_to': {
        'm.in_reply_to': {'event_id': r'$x'},
      },
      'm.new_content': {'body': 'edited'},
    };

    final content = forwardContent(source)!;

    expect(content['file'], file);
    expect(content['info'], source['info']);
    expect(content['org.matrix.msc3245.voice'], <String, Object?>{});
    expect(content['org.matrix.msc1767.audio'], {'duration': 4200});
    expect(content[forwardedMarker], true);
    expect(content.containsKey('m.relates_to'), isFalse);
    expect(content.containsKey('m.new_content'), isFalse);
    // A copy: changing it does not change the source.
    (content['file']! as Map)['url'] = 'changed';
    expect(file['url'], 'mxc://example.org/abc');
  });

  test('images keep the thumbnail', () {
    final content = forwardContent({
      'msgtype': 'm.image',
      'body': 'photo.jpg',
      'file': {'url': 'mxc://example.org/img'},
      'info': {
        'w': 100,
        'h': 80,
        'thumbnail_file': {'url': 'mxc://example.org/thumb'},
        'thumbnail_info': {'w': 50, 'h': 40},
      },
    })!;

    expect(content['msgtype'], 'm.image');
    expect((content['info']! as Map)['thumbnail_file'], {
      'url': 'mxc://example.org/thumb',
    });
  });

  test('anything else cannot be forwarded', () {
    expect(forwardContent({'msgtype': 'm.location', 'body': 'x'}), isNull);
    expect(forwardContent({'msgtype': 'm.image', 'body': 'no file'}), isNull);
    expect(forwardContent({'body': 'no type'}), isNull);
    expect(forwardContent({'msgtype': 'm.text', 'body': '   '}), isNull);
  });
}
