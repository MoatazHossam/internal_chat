import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../domain/chat_backend.dart';
import '../../models/user.dart';
import '../../services/locale_service.dart';
import '../push/push_controller.dart';

class SettingsController extends GetxController {
  SettingsController(this._session);

  final ChatSession _session;

  final currentUser = Rxn<User>();
  final isDarkMode = false.obs;
  final locale = Rx<Locale>(LocaleService.current());
  final loading = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadCurrentUser();
  }

  void _loadCurrentUser() {
    currentUser.value = _session.currentSessionState.user;
  }

  Future<void> setLocale(Locale value) async {
    if (locale.value == value) return;
    locale.value = value;
    await LocaleService.set(value);
    Get.updateLocale(value);
    // The lock-screen text is registered in the user's language.
    if (Get.isRegistered<PushController>()) {
      await Get.find<PushController>().updateRegistration();
    }
  }

  /// Deletes this device's local data and keys. The session controller
  /// returns to the login screen once sign-out has finished.
  Future<void> signOut() async {
    loading.value = true;
    try {
      await _session.signOut();
    } finally {
      loading.value = false;
    }
  }
}
