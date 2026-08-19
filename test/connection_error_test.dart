import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:landa_app/core/network/api_client.dart';
import 'package:landa_app/core/network/api_constants.dart';
import 'package:landa_app/core/network/auth_token_storage.dart';
import 'package:landa_app/features/marketplace/controllers/marketplace_controller.dart';
import 'package:landa_app/features/marketplace/services/marketplace_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cover for the offline path: transport failures must arrive at the UI as a
/// retry-able [NetworkException] carrying a human message, never as a raw
/// "SocketException: Failed host lookup" string.
void main() {
  late String originalBaseUrl;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthTokenStorage.clear();
    await AuthTokenStorage.saveTokens(
      access: 'test-access-token',
      refresh: 'test-refresh-token',
    );
    originalBaseUrl = ApiConstants.baseUrl;
    ApiConstants.baseUrl = 'https://api.example.test/api/users';
  });

  tearDown(() {
    ApiConstants.baseUrl = originalBaseUrl;
  });

  ApiClient clientThatThrows(Object error) =>
      ApiClient(client: MockClient((_) async => throw error));

  test('a dead socket surfaces as a friendly NetworkException', () async {
    final api = clientThatThrows(
      const SocketException('Failed host lookup: api.example.test'),
    );

    await expectLater(
      api.get('/payments/'),
      throwsA(
        isA<NetworkException>().having(
          (e) => e.message,
          'message',
          contains('No internet connection'),
        ),
      ),
    );
  });

  test('http client failures are treated as connection failures', () async {
    final api = clientThatThrows(http.ClientException('Connection closed'));

    await expectLater(api.get('/payments/'), throwsA(isA<NetworkException>()));
  });

  test('friendlyErrorMessage never leaks a raw transport error string', () {
    final message = friendlyErrorMessage(
      const SocketException('Failed host lookup: api.example.test'),
    );

    expect(message, isNot(contains('SocketException')));
    expect(message, contains('No internet connection'));
  });

  test('isConnectionError separates transport from server rejections', () {
    expect(isConnectionError(NetworkException()), isTrue);
    expect(isConnectionError(TimeoutException('slow')), isTrue);
    expect(
      isConnectionError(ApiException('Invalid credentials', statusCode: 401)),
      isFalse,
    );
  });

  test(
    'an offline load leaves the controller with a retry-able failure',
    () async {
      final controller = MarketplaceController(
        service: MarketplaceService(
          apiClient: clientThatThrows(
            const SocketException('Failed host lookup'),
          ),
        ),
      );

      await controller.loadLandlordApplications();

      expect(controller.hasError, isTrue);
      expect(controller.errorIsConnection, isTrue);
      expect(controller.errorMessage, contains('No internet connection'));
      // "Attempt finished" must still be recorded, or the screen shimmers
      // forever instead of offering Try again.
      expect(controller.hasLoadedLandlordApplications, isTrue);
      expect(controller.isLoading, isFalse);
    },
  );

  test('a server rejection is not reported as an offline failure', () async {
    final controller = MarketplaceController(
      service: MarketplaceService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => http.Response('{"detail": "Nope."}', 403),
          ),
        ),
      ),
    );

    await controller.loadLandlordApplications();

    expect(controller.hasError, isTrue);
    expect(controller.errorIsConnection, isFalse);
    expect(controller.errorMessage, 'Nope.');
  });
}
