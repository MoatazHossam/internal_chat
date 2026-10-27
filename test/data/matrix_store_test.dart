import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/data/matrix/matrix_store.dart';

void main() {
  test('data without its key is never replaced automatically', () {
    expect(
      planDatabaseKey(keyStored: false, filesExist: true),
      DatabaseKeyPlan.refuse,
    );
  });

  test('a first start creates a key; a stored key is used', () {
    expect(
      planDatabaseKey(keyStored: false, filesExist: false),
      DatabaseKeyPlan.createNew,
    );
    expect(
      planDatabaseKey(keyStored: true, filesExist: true),
      DatabaseKeyPlan.useStored,
    );
    expect(
      planDatabaseKey(keyStored: true, filesExist: false),
      DatabaseKeyPlan.useStored,
    );
  });
}
