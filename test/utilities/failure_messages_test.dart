import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/utilities/failure_messages.dart';

void main() {
  test('formatBytes uses binary units', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(26214400), '25 MB');
  });
}
