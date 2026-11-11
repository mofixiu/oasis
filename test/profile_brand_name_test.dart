import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/features/profile/services/profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A host's brand name can be added, changed or cleared after sign-up with
/// `PATCH /profile/` (API guide 22).
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

  Future<Map<String, dynamic>> patchBody(
    Future<void> Function(ProfileService) action,
  ) async {
    Map<String, dynamic>? sent;
    final service = ProfileService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/users/profile/');
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    await action(service);
    return sent!;
  }

  test('a new brand name is sent as brand_name', () async {
    final body = await patchBody(
      (s) => s.updateProfile(brandName: 'Lekki Luxe Stays'),
    );
    expect(body, {'brand_name': 'Lekki Luxe Stays'});
  });

  test('an empty brand name is sent, which clears it', () async {
    final body = await patchBody((s) => s.updateProfile(brandName: ''));
    expect(body, {'brand_name': ''});
  });

  test('an unchanged brand name is left out of the request', () async {
    final body = await patchBody((s) => s.updateProfile(bio: 'Hello'));
    expect(body.containsKey('brand_name'), isFalse);
  });
}
