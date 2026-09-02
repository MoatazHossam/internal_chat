import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/authentication.dart';
import 'contracts.dart';

class PlatformTokenStorageService implements TokenStorageService {
  PlatformTokenStorageService({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  // Web tokens are kept in memory only — never persisted to browser storage.
  AuthTokens? _webTokens;

  @override
  Future<AuthTokens?> read() async {
    if (kIsWeb) return _webTokens;

    final access = await _secure.read(key: 'access_token');
    if (access == null) return null;

    return AuthTokens(
      accessToken: access,
      refreshToken: await _secure.read(key: 'refresh_token'),
    );
  }

  @override
  Future<void> write(AuthTokens tokens) async {
    if (kIsWeb) {
      _webTokens = tokens;
      return;
    }

    await _secure.write(key: 'access_token', value: tokens.accessToken);
    if (tokens.refreshToken != null) {
      await _secure.write(key: 'refresh_token', value: tokens.refreshToken);
    }
  }

  @override
  Future<void> clear() async {
    _webTokens = null;
    if (!kIsWeb) {
      await _secure.delete(key: 'access_token');
      await _secure.delete(key: 'refresh_token');
    }
  }
}
