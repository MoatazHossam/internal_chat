import 'package:get/get.dart';

import '../../domain/chat_backend.dart';
import 'chat_controller.dart';

class ChatBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => ChatController(
        Get.find<Conversations>(),
        Get.find<Messages>(),
        Get.find<ChatSession>(),
      ),
    );
  }
}
