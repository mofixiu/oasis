import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What happens when a session ends on its own.
///
/// A refresh token expires eventually, and when it does the backend answers
/// every request with `Given token not valid for any token type`. The network
/// layer used to clear storage and say nothing, so the app kept rendering a
/// signed-in shell over an account with no credentials: the user sat looking
/// at a raw JWT error with no route back to sign-in short of force-quitting.
void main() {
  late String originalBaseUrl;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthTokenStorage.clear();
    await AuthTokenStorage.saveTokens(access: 'stale', refresh: 'also-stale');
    originalBaseUrl = ApiConstants.baseUrl;
    ApiConstants.baseUrl = 'https://api.example.test/api/users';
  });

  tearDown(() async {
    ApiConstants.baseUrl = originalBaseUrl;
    ApiClient.onSessionExpired = null;
  });

  test(
    'a rejected refresh clears the tokens and announces the sign-out',
    () async {
      var expired = 0;
      ApiClient.onSessionExpired = () => expired++;

      final client = ApiClient(
        client: MockClient(
          (request) async => _json({
            'detail': 'Given token not valid for any token type',
          }, status: 401),
        ),
      );

      await expectLater(client.get('/profile/'), throwsA(isA<ApiException>()));

      // Both halves matter. Clearing alone was the old behaviour, and it is why
      // the app carried on believing it was signed in.
      expect(await AuthTokenStorage.getAccessToken(), isNull);
      expect(await AuthTokenStorage.getRefreshToken(), isNull);
      expect(expired, 1);
    },
  );

  test('a refresh that succeeds keeps the session and says nothing', () async {
    var expired = 0;
    ApiClient.onSessionExpired = () => expired++;

    var attempt = 0;
    final client = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/token/refresh/')) {
          return _json({'access': 'fresh-token'});
        }
        // Rejected once, accepted on the retry with the new token.
        attempt++;
        return attempt == 1
            ? _json({'detail': 'Token is expired'}, status: 401)
            : _json({'id': 'user-1', 'email': 'a@b.test'});
      }),
    );

    final profile = await client.get('/profile/');

    expect((profile as Map)['id'], 'user-1');
    expect(await AuthTokenStorage.getAccessToken(), 'fresh-token');
    // An ordinary expired *access* token is not the session ending, and
    // signing the user out here would be the bug in the other direction.
    expect(expired, isZero);
  });

  test('a refresh that throws does not sign anybody out', () async {
    var expired = 0;
    ApiClient.onSessionExpired = () => expired++;

    final client = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/token/refresh/')) {
          throw const SocketExceptionStub();
        }
        return _json({'detail': 'expired'}, status: 401);
      }),
    );

    await expectLater(client.get('/profile/'), throwsA(isA<ApiException>()));

    // Only the server saying no is evidence the credentials are dead. An
    // exception on the way (offline, a TLS failure, a malformed body) is
    // evidence that we do not know, and signing somebody out on "do not
    // know" is how a blip in coverage becomes a forced re-login.
    expect(expired, isZero);
    expect(await AuthTokenStorage.getRefreshToken(), 'also-stale');
  });
}

/// Stands in for a dead connection without depending on `dart:io` specifics.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketException: Failed host lookup';
}

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
