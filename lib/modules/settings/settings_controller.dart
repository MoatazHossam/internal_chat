import 'package:get/get.dart';

import '../../app_routes.dart';
import '../../models/user.dart';
import '../../repositories/authentication_repository.dart';

/// Retention options shown to the user.
/// Values match the list in the README.
enum RetentionOption {
  sessionOnly(0, 'Session only'),
  oneDay(1, '1 day'),
  sevenDays(7, '7 days'),
  thirtyDays(30, '30 days'),
  ninetyDays(90, '90 days'),
  oneEightyDays(180, '6 months'),
  oneYear(365, '1 year');

  const RetentionOption(this.days, this.label);

  final int days;
  final String label;
}

class SettingsController extends GetxController {
  SettingsController(this._repository);

  final AuthenticationRepository _repository;

  final currentUser = Rxn<User>();
  final selectedRetention = RetentionOption.thirtyDays.obs;
  final isDarkMode = false.obs;
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

  Future<void> signOut() async {
    loading.value = true;
    await _repository.signOut();
    loading.value = false;
    Get.offAllNamed(AppRoutes.login);
  }
}
