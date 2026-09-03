import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../app_routes.dart';
import '../../models/user.dart';
import '../../repositories/authentication_repository.dart';
import '../../services/locale_service.dart';

/// Retention options shown to the user.
/// Values match the list in the README. Display labels are localized in
/// the page, keeping this controller free of UI/localization concerns.
enum RetentionOption {
  sessionOnly(0),
  oneDay(1),
  sevenDays(7),
  thirtyDays(30),
  ninetyDays(90),
  oneEightyDays(180),
  oneYear(365);

  const RetentionOption(this.days);

  final int days;
}

class SettingsController extends GetxController {
  SettingsController(this._repository);

  final AuthenticationRepository _repository;

  final currentUser = Rxn<User>();
  final selectedRetention = RetentionOption.thirtyDays.obs;
  final isDarkMode = false.obs;
  final locale = Rx<Locale>(LocaleService.current());
  final loading = false.obs;

  // The administrator maximum is mocked at 365 days.
  // In production this would come from the policy endpoint.
  static const int administratorMaximumDays = 365;

  @override
  void onInit() {
    super.onInit();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    currentUser.value = await _repository.currentUser();
  }

  void setRetention(RetentionOption option) {
    if (option.days <= administratorMaximumDays) {
      selectedRetention.value = option;
    }
  }

  List<RetentionOption> get availableRetentionOptions {
    return RetentionOption.values
        .where((o) => o.days <= administratorMaximumDays)
        .toList();
  }

  Future<void> setLocale(Locale value) async {
    if (locale.value == value) return;
    locale.value = value;
    await LocaleService.set(value);
    Get.updateLocale(value);
  }

  Future<void> signOut() async {
    loading.value = true;
    await _repository.signOut();
    loading.value = false;
    Get.offAllNamed(AppRoutes.login);
  }
}
