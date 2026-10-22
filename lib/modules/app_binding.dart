import 'package:get/get.dart';

import '../constants.dart';
import '../data/backend_factory.dart';
import '../domain/chat_backend.dart';
import 'security/device_trust_controller.dart';
import 'session/session_controller.dart';

/// Composition root. Replacing the backend (for example the SDK) happens here
/// and in `data/`, never in pages or controllers.
class AppBinding extends Bindings {
  AppBinding(this.configuration);

  final AppConfiguration configuration;

  @override
  void dependencies() {
    final backend = createChatBackend(configuration);

    Get.put<AppConfiguration>(configuration, permanent: true);
    Get.put<ChatSession>(backend, permanent: true);
    Get.put<Conversations>(backend, permanent: true);
    Get.put<Messages>(backend, permanent: true);
    Get.put<DeviceTrust>(backend, permanent: true);

    Get.put(SessionController(backend), permanent: true);
    Get.put(DeviceTrustController(backend), permanent: true);
  }
}
