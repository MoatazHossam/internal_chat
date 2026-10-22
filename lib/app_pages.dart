import 'package:get/get.dart';

import 'app_routes.dart';
import 'modules/authentication/authentication_binding.dart';
import 'modules/authentication/login_page.dart';
import 'modules/chat/chat_binding.dart';
import 'modules/chat/conversation_info_page.dart';
import 'modules/chat/conversation_list_page.dart';
import 'modules/chat/conversation_page.dart';
import 'modules/security/security_page.dart';
import 'modules/session/splash_page.dart';
import 'modules/settings/settings_binding.dart';
import 'modules/settings/settings_page.dart';

abstract final class AppPages {
  static final pages = <GetPage<dynamic>>[
    GetPage(name: AppRoutes.splash, page: () => const SplashPage()),
    GetPage(
      name: AppRoutes.login,
      page: () => const LoginPage(),
      binding: AuthenticationBinding(),
    ),
    GetPage(
      name: AppRoutes.conversations,
      page: () => const ConversationListPage(),
      binding: ChatBinding(),
    ),
    GetPage(
      name: AppRoutes.conversation,
      page: () => ConversationPage(),
      binding: ChatBinding(),
    ),
    GetPage(
      name: AppRoutes.conversationInfo,
      page: () => const ConversationInfoPage(),
      binding: ConversationInfoBinding(),
    ),
    GetPage(
      name: AppRoutes.settings,
      page: () => const SettingsPage(),
      binding: SettingsBinding(),
    ),
    GetPage(name: AppRoutes.security, page: () => const SecurityPage()),
  ];
}
