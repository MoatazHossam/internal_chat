import 'package:get/get.dart';

import '../../domain/chat_backend.dart';
import '../../domain/chat_failure.dart';

/// Password sign-in. The server offers no SSO, MFA or registration; accounts
/// are created by an administrator. Navigation after sign-in is handled by
/// the session controller.
class AuthenticationController extends GetxController {
  AuthenticationController(this._session);

  final ChatSession _session;

  final failure = Rxn<ChatFailure>();
  final loading = false.obs;

  Future<bool> signIn(String username, String password) async {
    if (loading.value) return false;
    if (username.trim().isEmpty || password.isEmpty) {
      failure.value = const InvalidCredentials();
      return false;
    }
    loading.value = true;
    failure.value = null;
    try {
      await _session.signIn(username: username, password: password);
      return true;
    } on ChatFailure catch (error) {
      failure.value = error;
      return false;
    } finally {
      loading.value = false;
    }
  }
}
