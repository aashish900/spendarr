import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers/settings.dart';
import 'api_error.dart';
import 'endpoints.dart';

part 'client.g.dart';

/// Backend operations exposed to the app. An interface so widget/unit tests
/// can inject a fake without a live dio.
///
/// `ApiError` mapping lives at this layer (call sites catch [DioException] and
/// rethrow [ApiError]) rather than in a dio interceptor: with a single live
/// endpoint that is simpler and easier to test. Revisit at B7 when sync adds
/// several endpoints.
abstract interface class ApiClient {
  /// Hits `/health`. Returns normally on success; throws [ApiError] otherwise.
  Future<void> health();
}

class DioApiClient implements ApiClient {
  DioApiClient(this._dio);

  final Dio _dio;

  @override
  Future<void> health() async {
    try {
      await _dio.get(Endpoints.health);
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }
}

/// A [Dio] configured from current [Settings]: base URL + bearer interceptor.
/// Rebuilds when settings change.
@riverpod
Dio dio(Ref ref) {
  final settings = ref.watch(settingsProvider).value;
  final dio = Dio(BaseOptions(baseUrl: settings?.baseUrl ?? ''));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = ref.read(settingsProvider).value?.token;
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ),
  );
  return dio;
}

@riverpod
ApiClient apiClient(Ref ref) => DioApiClient(ref.watch(dioProvider));
