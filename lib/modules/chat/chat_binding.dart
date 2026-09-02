import 'package:get/get.dart';import '../../repositories/chat_repository.dart';import 'chat_controller.dart';
class ChatBinding extends Bindings{@override void dependencies()=>Get.lazyPut(()=>ChatController(Get.find<ChatRepository>()));}
