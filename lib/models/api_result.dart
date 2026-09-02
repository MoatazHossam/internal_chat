sealed class ApiResult<T> {
  const ApiResult();
}

final class ApiSuccess<T> extends ApiResult<T> {
  const ApiSuccess(this.value);
  final T value;
}

enum ApiErrorKind { network, timeout, unauthorized, server, parsing, unknown }

final class ApiFailure<T> extends ApiResult<T> {
  const ApiFailure(this.error);
  final ApiError error;
}

class ApiError {
  const ApiError(this.kind, this.message, {this.statusCode});
  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
}
