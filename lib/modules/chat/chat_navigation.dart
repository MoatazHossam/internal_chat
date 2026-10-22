import 'package:get/get.dart';

import '../../app_routes.dart';
import '../../domain/ids.dart';
import 'chat_controller.dart';

/// Opens [id] in the controller and shows the conversation page.
void openConversationPage(ChatController controller, ConversationId id) {
  controller.openConversation(id);
  // Matrix room IDs contain "!" and ":", so encode them for the route.
  Get.toNamed(
    AppRoutes.conversation.replaceFirst(':id', Uri.encodeComponent(id.value)),
  );
}
