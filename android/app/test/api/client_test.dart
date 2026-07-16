import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart' hide Matcher;
import 'package:spendarr/api/api_error.dart';
import 'package:spendarr/api/client.dart';
import 'package:spendarr/api/endpoints.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late DioApiClient client;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    adapter = DioAdapter(dio: dio);
    client = DioApiClient(dio);
  });

  Matcher throwsApiErrorOfKind(ApiErrorKind kind) => throwsA(
        isA<ApiError>().having((e) => e.kind, 'kind', kind),
      );

  test('200 → completes normally', () async {
    adapter.onGet(Endpoints.health, (s) => s.reply(200, {'status': 'ok'}));
    await expectLater(client.health(), completes);
  });

  test('401 → unauthorized', () async {
    adapter.onGet(Endpoints.health, (s) => s.reply(401, {'detail': 'bad token'}));
    await expectLater(
        client.health(), throwsApiErrorOfKind(ApiErrorKind.unauthorized));
  });

  test('403 → forbidden', () async {
    adapter.onGet(Endpoints.health, (s) => s.reply(403, {'detail': 'no scope'}));
    await expectLater(
        client.health(), throwsApiErrorOfKind(ApiErrorKind.forbidden));
  });

  test('422 → unprocessable, surfaces detail', () async {
    adapter.onGet(
        Endpoints.health, (s) => s.reply(422, {'detail': 'bad field'}));
    await expectLater(
      client.health(),
      throwsA(isA<ApiError>()
          .having((e) => e.kind, 'kind', ApiErrorKind.unprocessable)
          .having((e) => e.message, 'message', 'bad field')),
    );
  });

  test('500 → server', () async {
    adapter.onGet(Endpoints.health, (s) => s.reply(500, {'detail': 'boom'}));
    await expectLater(
        client.health(), throwsApiErrorOfKind(ApiErrorKind.server));
  });

  test('other 4xx → unknown', () async {
    adapter.onGet(Endpoints.health, (s) => s.reply(418, {'detail': 'teapot'}));
    await expectLater(
        client.health(), throwsApiErrorOfKind(ApiErrorKind.unknown));
  });

  group('ApiError.fromDio mapping', () {
    test('no response (connection error) → network', () {
      final err = ApiError.fromDio(DioException.connectionError(
        requestOptions: RequestOptions(path: Endpoints.health),
        reason: 'no route to host',
      ));
      expect(err.kind, ApiErrorKind.network);
      expect(err.statusCode, isNull);
    });
  });
}
