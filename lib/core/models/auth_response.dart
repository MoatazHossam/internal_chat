import 'user.dart';

class AuthResponse {
  final String accessToken;
  final String refreshToken;
  final User user;
  final bool requiresMfa;

  const AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    this.requiresMfa = false,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> j) => AuthResponse(
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String,
        user: User.fromJson(j['user'] as Map<String, dynamic>),
        requiresMfa: j['requires_mfa'] as bool? ?? false,
      );
}
