import 'package:get/get.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_service.dart';
import '../../core/services/socket_service.dart';
import '../../features/auth/controllers/auth_controller.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(StorageService(), permanent: true);
    Get.put(ApiService(), permanent: true);
    Get.put(SocketService(), permanent: true);
    Get.put(AuthController(), permanent: true);
  }
}
