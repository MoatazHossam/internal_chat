import 'dart:async';

import 'package:get/get.dart';

import '../../domain/chat_backend.dart';
import '../../domain/chat_failure.dart';
import '../../domain/device_trust_state.dart';
import 'verification_dialog.dart';

/// App-wide: this device's verification state, recovery-key actions, and the
/// dialog for verification requests from other devices.
class DeviceTrustController extends GetxController {
  DeviceTrustController(this._trust);

  final DeviceTrust _trust;

  final state = TrustState.unknown.obs;
  final busy = false.obs;
  final failure = Rxn<ChatFailure>();

  StreamSubscription<TrustState>? _stateSubscription;
  StreamSubscription<VerificationRequest>? _incomingSubscription;
  bool _dialogOpen = false;

  @override
  void onInit() {
    super.onInit();
    _stateSubscription = _trust.trustState.listen(
      (value) => state.value = value,
    );
    _incomingSubscription = _trust.incomingVerifications.listen(
      _presentVerification,
    );
  }

  Future<void> refreshState() => _run(_trust.refreshTrust);

  /// Returns the new recovery key, to be shown to the user once.
  Future<RecoveryKey?> setUpRecovery(String password) =>
      _run(() => _trust.setUpRecovery(password: password));

  Future<bool> restoreWithRecoveryKey(String key) async {
    final restored = await _run(() async {
      await _trust.restoreWithRecoveryKey(RecoveryKey(key));
      return true;
    });
    return restored ?? false;
  }

  Future<void> verifyWithOtherDevice() async {
    final request = await _run(_trust.verifyWithOtherDevice);
    if (request != null) await _presentVerification(request);
  }

  Future<void> _presentVerification(VerificationRequest request) async {
    // One verification at a time; a second request simply times out.
    if (_dialogOpen) return;
    _dialogOpen = true;
    try {
      await Get.dialog<void>(
        VerificationDialog(request: request),
        barrierDismissible: false,
      );
    } finally {
      _dialogOpen = false;
    }
  }

  Future<T?> _run<T>(Future<T> Function() action) async {
    if (busy.value) return null;
    busy.value = true;
    try {
      return await action();
    } on ChatFailure catch (error) {
      failure.value = error;
      failure.refresh();
      return null;
    } finally {
      busy.value = false;
    }
  }

  @override
  void onClose() {
    _stateSubscription?.cancel();
    _incomingSubscription?.cancel();
    super.onClose();
  }
}
