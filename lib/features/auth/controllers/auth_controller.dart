import 'package:get/get.dart';
import '../../../core/models/user.dart';
import '../../../core/models/auth_response.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../app/routes/app_routes.dart';

class AuthController extends GetxController {
  final _api     = Get.find<ApiService>();
  final _storage = Get.find<StorageService>();

  final currentUser = Rx<User?>(null);
  final isLoading   = false.obs;
  final error       = RxnString();

  @override
  void onInit() {
    super.onInit();
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    final token = _storage.getToken();
    if (token == null) return;
    final result = await _api.get('/auth/me', User.fromJson);
    if (result is ApiSuccess<User>) currentUser.value = result.data;
  }

  Future<void> login(String email, String password) async {
    isLoading.value = true;
    error.value = null;
    final result = await _api.post(
      '/auth/login',
      {'email': email, 'password': password},
      AuthResponse.fromJson,
    );
    isLoading.value = false;
    if (result is ApiSuccess<AuthResponse>) {
      await _storage.saveToken(result.data.accessToken);
      await _storage.saveRefreshToken(result.data.refreshToken);
      currentUser.value = result.data.user;
      if (result.data.requiresMfa) {
        Get.toNamed(AppRoutes.mfa);
      } else {
        Get.offAllNamed(AppRoutes.channels);
      }
    } else if (result is ApiError) {
      error.value = (result as ApiError).message;
    }
  }

  Future<void> logout() async {
    await _api.post('/auth/logout', {}, (_) {});
    await _storage.clearAll();
    currentUser.value = null;
    Get.offAllNamed(AppRoutes.login);
  }
}
