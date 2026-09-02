import 'user.dart';

sealed class AuthenticationOutcome { const AuthenticationOutcome(); }
class Authenticated extends AuthenticationOutcome {
  const Authenticated(this.user, this.tokens);
  final User user;
  final AuthTokens tokens;
}
class MfaRequired extends AuthenticationOutcome {
  const MfaRequired(this.challengeId);
  final String challengeId;
}
class AuthTokens {
  const AuthTokens({required this.accessToken, this.refreshToken});
  final String accessToken;
  final String? refreshToken;
}
