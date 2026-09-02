import '../models/api_result.dart';
import '../models/authentication.dart';
import '../models/user.dart';

abstract interface class AuthenticationRepository {
  Future<ApiResult<AuthenticationOutcome>> signIn(
      {required String identifier, required String password});
  Future<ApiResult<Authenticated>> verifyMfa(
      {required String challengeId, required String code});
  Future<void> signOut();
  Future<User?> currentUser();
}
