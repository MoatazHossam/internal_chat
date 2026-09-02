import 'package:get/get.dart';
import '../controllers/channel_controller.dart';
import '../controllers/chat_controller.dart';

class ChatBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => ChannelController());
    Get.lazyPut(() => ChatController());
  }
}
