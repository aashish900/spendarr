import 'package:dio/dio.dart';

/// Coarse classification of a failed API call, mapped to the UX in
/// CONTEXT.md "Error UX".
enum ApiErrorKind {
  /// 401 — bad/expired bearer token.
  unauthorized,

  /// 403 — token valid but lacks the required scope.
  forbidden,

  /// 422 — request body failed server validation.
  unprocessable,

  /// Could not reach the backend (DNS, connect/receive timeout, socket).
  network,

  /// 5xx — server-side failure.
  server,

  /// Anything else (other 4xx, malformed response, etc.).
  unknown,
}

/// Typed boundary for all backend failures. Call sites catch [DioException]
/// and rethrow this so the UI layer never touches dio types.
class ApiError implements Exception {
  const ApiError({
    required this.kind,
    required this.message,
    this.statusCode,
    this.detail,
  });

  final ApiErrorKind kind;

  /// Short human-readable summary (used for snackbars).
  final String message;

  final int? statusCode;

  /// The `detail` field from the server error envelope, if present.
  final String? detail;

  /// Map a [DioException] to a typed [ApiError].
  factory ApiError.fromDio(DioException e) {
    // No HTTP response → connectivity problem.
    final response = e.response;
    if (response == null) {
      return const ApiError(
        kind: ApiErrorKind.network,
        message: "can't reach backend — check Tailscale",
      );
    }

    final status = response.statusCode;
    final detail = _detailOf(response.data);

    switch (status) {
      case 401:
        return ApiError(
          kind: ApiErrorKind.unauthorized,
          message: 'auth failed — check bearer token in Settings',
          statusCode: status,
          detail: detail,
        );
      case 403:
        return ApiError(
          kind: ApiErrorKind.forbidden,
          message: 'insufficient scope',
          statusCode: status,
          detail: detail,
        );
      case 422:
        return ApiError(
          kind: ApiErrorKind.unprocessable,
          message: detail ?? 'validation failed',
          statusCode: status,
          detail: detail,
        );
    }

    if (status != null && status >= 500) {
      return ApiError(
        kind: ApiErrorKind.server,
        message: detail ?? 'server error ($status)',
        statusCode: status,
        detail: detail,
      );
    }

    return ApiError(
      kind: ApiErrorKind.unknown,
      message: detail ?? 'request failed ($status)',
      statusCode: status,
      detail: detail,
    );
  }

  /// Pull `detail` out of a `{"detail": "..."}` error envelope when present.
  static String? _detailOf(Object? data) {
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return null;
  }

  @override
  String toString() => 'ApiError($kind, status=$statusCode, $message)';
}
