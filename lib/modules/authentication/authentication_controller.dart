import 'package:get/get.dart';

import '../../models/api_result.dart';
import '../../models/authentication.dart';
import '../../models/user.dart';
import '../../repositories/authentication_repository.dart';

class AuthenticationController extends GetxController {
  AuthenticationController(this._repository);

  final AuthenticationRepository _repository;

  final user = Rxn<User>();
  final error = RxnString();
  final loading = false.obs;
  final mfaChallenge = RxnString();

  Future<bool> signIn(String identifier, String password) async {
    loading.value = true;
    error.value = null;

    final result = await _repository.signIn(
      identifier: identifier,
      password: password,
    );

    loading.value = false;

    switch (result) {
      case ApiSuccess(value: final Authenticated auth):
        user.value = auth.user;
        return true;
      case ApiSuccess(value: final MfaRequired mfa):
        mfaChallenge.value = mfa.challengeId;
        return false;
      case ApiFailure(error: final e):
        error.value = e.message;
        return false;
    }
  }

  Future<bool> verifyMfa(String code) async {
    final challenge = mfaChallenge.value;
    if (challenge == null) return false;

    loading.value = true;
    error.value = null;

    final result = await _repository.verifyMfa(
      challengeId: challenge,
      code: code,
    );

    loading.value = false;

    switch (result) {
      case ApiSuccess(value: final auth):
        user.value = auth.user;
        mfaChallenge.value = null;
        return true;
      case ApiFailure(error: final e):
        error.value = e.message;
        return false;
    }
  }

  Future<void> signOut() async {
    await _repository.signOut();
    user.value = null;
    mfaChallenge.value = null;
  }
}
