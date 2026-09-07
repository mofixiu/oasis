import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:landa_app/core/network/api_client.dart';
import 'package:landa_app/core/network/api_constants.dart';
import 'package:landa_app/core/network/auth_token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Staging runs on Render's free tier, which sleeps after idle and then needs
/// most of a minute to wake. That wait is normal, not a fault, and the app has
/// to tell the two apart: a sleeping server is worth waiting for and worth
/// explaining, a genuinely unreachable one is not.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthTokenStorage.clear();
    await AuthTokenStorage.saveTokens(access: 'access', refresh: 'refresh');
    ApiConstants.baseUrl = 'https://api.example.test/api/users';
    ApiClient.resetWarmState();
  });

  tearDown(ApiClient.resetWarmState);

  test('the server is assumed asleep until it answers', () {
    expect(ApiClient.isServerWarm, isFalse);
  });

  test('any answer marks the server awake', () async {
    final client = ApiClient(
      client: MockClient(
        (_) async => http.Response('[]', 200, headers: _jsonHeaders),
      ),
    );

    await client.get('/properties/');
    expect(ApiClient.isServerWarm, isTrue);
  });

  test('even a server error proves the container is running', () async {
    final client = ApiClient(
      client: MockClient(
        (_) async =>
            http.Response('{"detail":"boom"}', 500, headers: _jsonHeaders),
      ),
    );

    // The call fails, but it fails *from the server*, so the next request has
    // no reason to keep paying the cold-start allowance.
    await expectLater(client.get('/properties/'), throwsA(isA<ApiException>()));
    expect(ApiClient.isServerWarm, isTrue);
  });

  test('a cold timeout says the server is waking up', () async {
    final client = ApiClient(
      client: MockClient((_) async => throw TimeoutException('slept')),
    );

    await expectLater(
      client.get('/properties/'),
      throwsA(
        isA<NetworkException>().having(
          (e) => e.message,
          'message',
          contains('waking up'),
        ),
      ),
    );
  });

  test('a warm timeout does not blame a cold start', () async {
    var shouldTimeout = false;
    final client = ApiClient(
      client: MockClient((_) async {
        if (shouldTimeout) throw TimeoutException('gone');
        return http.Response('[]', 200, headers: _jsonHeaders);
      }),
    );

    await client.get('/properties/');
    expect(ApiClient.isServerWarm, isTrue);

    // Now that the server has proven it is up, a timeout is a real problem and
    // must not be excused as a spin-up.
    shouldTimeout = true;
    await expectLater(
      client.get('/properties/'),
      throwsA(
        isA<NetworkException>().having(
          (e) => e.message,
          'message',
          allOf(contains('took too long'), isNot(contains('waking up'))),
        ),
      ),
    );
  });

  test('warmth expires, so a long-idle app waits properly again', () {
    // The window is deliberately shorter than Render's idle timeout: the app
    // should err towards granting the longer wait rather than towards failing
    // a request that was only ever going to be slow.
    expect(ApiClient.warmFor, lessThan(const Duration(minutes: 15)));
    expect(
      ApiClient.coldStartBudget,
      greaterThanOrEqualTo(const Duration(seconds: 45)),
      reason: 'a Render cold start regularly runs past 45 seconds',
    );
  });
}

const _jsonHeaders = {'content-type': 'application/json'};
