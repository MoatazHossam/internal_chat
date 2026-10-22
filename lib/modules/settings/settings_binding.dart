import 'package:get/get.dart';

import '../../domain/chat_backend.dart';
import 'settings_controller.dart';

class SettingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => SettingsController(Get.find<ChatSession>()));
  }
}
