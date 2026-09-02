import 'package:get/get.dart';

import '../../repositories/authentication_repository.dart';
import 'settings_controller.dart';

class SettingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => SettingsController(Get.find<AuthenticationRepository>()),
    );
  }
}
