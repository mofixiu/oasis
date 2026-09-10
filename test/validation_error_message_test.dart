import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A `422 VALIDATION_ERROR` carries a generic `detail` and a specific `errors`
/// map. The app used to read `detail` first, so a landlord who left the city
/// blank uploaded three photos, a walkthrough and a deed, waited for all of it,
/// and got back "Some details are missing or invalid.", with the field that
/// was actually wrong sitting unread in the same response.
void main() {
  late String originalBaseUrl;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthTokenStorage.clear();
    await AuthTokenStorage.saveTokens(access: 'token', refresh: 'refresh');
    originalBaseUrl = ApiConstants.baseUrl;
    ApiConstants.baseUrl = 'https://api.example.test/api/users';
  });

  tearDown(() => ApiConstants.baseUrl = originalBaseUrl);

  test('the field error wins over the generic detail', () async {
    final client = ApiClient(
      client: MockClient(
        (_) async => _json({
          'code': 'VALIDATION_ERROR',
          'detail': 'Some details are missing or invalid.',
          'errors': {
            'city': ['This field may not be blank.'],
          },
        }, status: 422),
      ),
    );

    await expectLater(
      client.get('/properties/'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('city'),
        ),
      ),
    );
  });

  test('several bad fields are all named', () async {
    final client = ApiClient(
      client: MockClient(
        (_) async => _json({
          'code': 'VALIDATION_ERROR',
          'detail': 'Some details are missing or invalid.',
          'errors': {
            'city': ['This field may not be blank.'],
            'latitude': [
              'Ensure that there are no more than 6 decimal places.',
            ],
          },
        }, status: 422),
      ),
    );

    try {
      await client.get('/properties/');
      fail('expected an ApiException');
    } on ApiException catch (e) {
      expect(e.message, contains('city'));
      expect(e.message, contains('latitude'));
    }
  });

  test('an endpoint sending only a detail still surfaces it', () async {
    final client = ApiClient(
      client: MockClient(
        (_) async => _json({'detail': 'Not found.'}, status: 404),
      ),
    );

    // The change must not cost anything for the endpoints that send one good
    // sentence and no field map.
    await expectLater(
      client.get('/properties/'),
      throwsA(
        isA<ApiException>().having((e) => e.message, 'message', 'Not found.'),
      ),
    );
  });

  test('an empty errors map falls through to the detail', () async {
    final client = ApiClient(
      client: MockClient(
        (_) async => _json({
          'detail': 'Something went wrong.',
          'errors': <String, dynamic>{},
        }, status: 400),
      ),
    );

    await expectLater(
      client.get('/properties/'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Something went wrong.',
        ),
      ),
    );
  });
}

http.Response _json(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
