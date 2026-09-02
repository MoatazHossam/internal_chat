import 'package:get/get.dart';

import '../app_routes.dart';
import 'contracts.dart';

/// Handles a 401 Unauthorized response by clearing stored tokens and routing
/// the user back to the login screen. Concurrent 401 responses will all
/// trigger this, but only the first navigation will take effect.
class SessionManager {
  SessionManager(this.tokens);

  final TokenStorageService tokens;

  Future<void> unauthorized() async {
    await tokens.clear();
    if (Get.currentRoute != AppRoutes.login) {
      Get.offAllNamed(AppRoutes.login);
    }
  }
}
