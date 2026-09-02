import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/api_result.dart';
import '../services/contracts.dart';

typedef UnauthorizedHandler = Future<void> Function();

/// Generic HTTP client that handles JWT auth, timeouts, and safe error mapping.
///
/// This client is transport-only: it does not know about domain models,
/// repositories, or business logic. Callers supply a [decode] function to
/// convert the raw JSON payload into a typed result.
class HttpApiClient {
  HttpApiClient({
    required http.Client client,
    required Uri baseUrl,
    required TokenStorageService tokens,
    required UnauthorizedHandler onUnauthorized,
    this.timeout = const Duration(seconds: 15),
  })  : _client = client,
        _baseUrl = baseUrl,
        _tokens = tokens,
        _onUnauthorized = onUnauthorized;

  final http.Client _client;
  final Uri _baseUrl;
  final TokenStorageService _tokens;
  final UnauthorizedHandler _onUnauthorized;
  final Duration timeout;

  Future<ApiResult<T>> send<T>({
    required String method,
    required String path,
    required T Function(Object?) decode,
    Object? body,
  }) async {
    try {
      final token = await _tokens.read();
      final request = http.Request(method, _baseUrl.resolve(path));

      request.headers['Accept'] = 'application/json';

      if (token != null) {
        request.headers['Authorization'] = 'Bearer ${token.accessToken}';
      }

      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }

      final response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      );

      if (response.statusCode == 401) {
        await _onUnauthorized();
        return const ApiFailure(
          ApiError(
            ApiErrorKind.unauthorized,
            'Session expired',
            statusCode: 401,
          ),
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ApiFailure(
          ApiError(
            ApiErrorKind.server,
            'Request failed',
            statusCode: response.statusCode,
          ),
        );
      }

      try {
        final payload =
            response.body.isEmpty ? null : jsonDecode(response.body);
        return ApiSuccess(decode(payload));
      } catch (_) {
        return const ApiFailure(
          ApiError(ApiErrorKind.parsing, 'Invalid server response'),
        );
      }
    } on TimeoutException {
      return const ApiFailure(
        ApiError(ApiErrorKind.timeout, 'Request timed out'),
      );
    } on SocketException {
      return const ApiFailure(
        ApiError(ApiErrorKind.network, 'Network unavailable'),
      );
    } catch (_) {
      return const ApiFailure(
        ApiError(ApiErrorKind.unknown, 'Request could not be completed'),
      );
    }
  }

  void close() => _client.close();
}
