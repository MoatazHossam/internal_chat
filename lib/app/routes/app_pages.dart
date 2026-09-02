import 'package:get/get.dart';
import '../../features/auth/bindings/auth_binding.dart';
import '../../features/auth/views/login_view.dart';
import '../../features/auth/views/mfa_view.dart';
import '../../features/chat/bindings/chat_binding.dart';
import '../../features/chat/views/channel_list_view.dart';
import '../../features/chat/views/chat_view.dart';
import '../../features/files/bindings/files_binding.dart';
import '../../features/files/views/file_picker_view.dart';
import '../middlewares/auth_middleware.dart';
import 'app_routes.dart';

class AppPages {
  static final pages = [
    GetPage(
      name: AppRoutes.login,
      page: () => const LoginView(),
      binding: AuthBinding(),
    ),
    GetPage(
      name: AppRoutes.mfa,
      page: () => const MfaView(),
      binding: AuthBinding(),
    ),
    GetPage(
      name: AppRoutes.channels,
      page: () => const ChannelListView(),
      binding: ChatBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: AppRoutes.chat,
      page: () => ChatView(),
      binding: ChatBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: AppRoutes.files,
      page: () => const FilePickerView(),
      binding: FilesBinding(),
      middlewares: [AuthMiddleware()],
    ),
  ];
}
