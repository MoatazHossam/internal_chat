import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

class StorageService extends GetxService {
  final _box = GetStorage();

  String? getToken() => _box.read<String>('access_token');
  String? getRefreshToken() => _box.read<String>('refresh_token');

  Future<void> saveToken(String token) => _box.write('access_token', token);
  Future<void> saveRefreshToken(String token) =>
      _box.write('refresh_token', token);

  Future<void> clearAll() async {
    await _box.erase();
  }
}
