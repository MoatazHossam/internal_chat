import 'package:get/get.dart';

import '../../domain/chat_backend.dart';
import 'authentication_controller.dart';

class AuthenticationBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => AuthenticationController(Get.find<ChatSession>()));
  }
}
