import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:landa_app/core/network/api_client.dart';
import 'package:landa_app/core/network/api_constants.dart';
import 'package:landa_app/core/network/auth_token_storage.dart';
import 'package:landa_app/features/auth/models/user_model.dart';
import 'package:landa_app/features/auth/services/api_auth_service.dart';
import 'package:landa_app/features/fix/controllers/fix_controller.dart';
import 'package:landa_app/features/fix/models/fix_models.dart';
import 'package:landa_app/features/fix/services/fix_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fix is a directory. It used to be a marketplace: request, accept, quote,
/// pay into escrow, confirm, release, and API guide 18 removed every
/// endpoint behind that (§7B), so the tests that covered double-charging and
/// a withheld phone number went with it.
///
/// What is left is worth less drama and still worth pinning: a landlord who
/// cannot browse artisans cannot recommend one, and a recommendation that
/// does not lead the list is a recommendation nobody sees.
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

  tearDown(() => ApiConstants.baseUrl = originalBaseUrl);

  // -------------------------------------------------------------- directory

  test('the artisan list is filtered by category and unit', () async {
    Uri? sentUri;
    final service = FixService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentUri = request.url;
          return _json(const []);
        }),
      ),
    );

    await service.browseArtisans(category: 'PLUMBING', unitId: 'UNIT_UUID');

    expect(sentUri?.path, '/api/users/tenant/fix/artisans/');
    // The unit is what makes `is_recommended` come back at all: without it a
    // tenant never sees which artisan their landlord vouched for.
    expect(sentUri?.queryParameters, {
      'category': 'PLUMBING',
      'unit': 'UNIT_UUID',
    });
  });

  // ------------------------------------------------------------------ phone

  test('an empty phone string is treated as no phone', () {
    // The number is now always served (API guide 18: "no more null"), and it
    // is the only thing a directory card is for. A card whose single action
    // is "call" must not offer to dial "".
    final blank = ArtisanProfile.fromJson(const {
      'id': 'artisan-1',
      'phone': '   ',
    });
    expect(blank.phone, isNull);

    final real = ArtisanProfile.fromJson(const {
      'id': 'artisan-2',
      'phone': '08000000000',
    });
    expect(real.phone, '08000000000');
  });

  // ----------------------------------------------------------------- status

  // -------------------------------------------------------- recommendations

  test('removing a recommendation names the category in the body', () async {
    String? sentMethod;
    String? sentPath;
    String? sentBody;
    final service = FixService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentMethod = request.method;
          sentPath = request.url.path;
          sentBody = request.body;
          return http.Response('', 204);
        }),
      ),
    );

    await service.removeRecommendation(
      unitId: 'UNIT_UUID',
      category: 'PLUMBING',
    );

    expect(sentMethod, 'DELETE');
    expect(sentPath, '/api/users/units/UNIT_UUID/artisan-recommendations/');
    // A unit holds one recommendation per category, so the path alone does not
    // identify what to remove.
    expect(jsonDecode(sentBody!), {'category': 'PLUMBING'});
  });

  test('a recommendation is created with the documented body', () async {
    Map<String, dynamic>? sentBody;
    final service = FixService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'category': 'PLUMBING',
            'artisan': {'id': 'artisan-1', 'full_name': 'Ada Fixer'},
          }, status: 201);
        }),
      ),
    );

    final saved = await service.recommendArtisan(
      unitId: 'UNIT_UUID',
      category: 'PLUMBING',
      artisanId: 'artisan-1',
    );

    expect(sentBody, {'category': 'PLUMBING', 'artisan_id': 'artisan-1'});
    expect(saved.artisanId, 'artisan-1');
    expect(saved.artisan?.displayName, 'Ada Fixer');
  });

  test('the landlord directory has its own route, and only that', () async {
    // The path moved. It was guessed at as `/landlord/fix/artisans/` before
    // the route existed, and the app fell back to the tenant route on a 404,
    // which a landlord is refused with a 403, so the picker came up empty
    // and nobody could be recommended. API guide 18 documents the real path.
    final paths = <String>[];
    final service = FixService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          paths.add(request.url.path);
          return _json([
            {'id': 'artisan-1', 'full_name': 'Ada Fixer'},
          ]);
        }),
      ),
    );

    final artisans = await service.browseArtisansForLandlord(
      category: 'PLUMBING',
      unitId: 'UNIT_UUID',
    );

    expect(paths, ['/api/users/landlord/artisans/']);
    expect(artisans, hasLength(1));
  });

  test(
    'a failure on the landlord directory is reported, not papered over',
    () async {
      var calls = 0;
      final service = FixService(
        apiClient: ApiClient(
          client: MockClient((_) async {
            calls++;
            return _json({'detail': 'Boom.'}, status: 500);
          }),
        ),
      );

      await expectLater(
        service.browseArtisansForLandlord(category: 'PLUMBING'),
        throwsA(isA<ApiException>()),
      );
      // One call. Trying a second route would report the wrong reason for the
      // failure, and there is no second route to try.
      expect(calls, 1);
    },
  );

  // -------------------------------------------------------------- ordering

  test('the recommended artisan leads the list', () async {
    final controller = FixController(
      service: FixService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json([
              {'id': 'a', 'full_name': 'Older Hand', 'years_of_experience': 9},
              {
                'id': 'b',
                'full_name': 'Landlord Pick',
                'years_of_experience': 2,
                'is_recommended': true,
              },
              {
                'id': 'c',
                'full_name': 'Online Now',
                'years_of_experience': 4,
                'recently_online': true,
              },
            ]),
          ),
        ),
      ),
    );

    await controller.loadCategories();
    await controller.loadArtisans(unitId: 'UNIT_UUID');

    expect(controller.artisans.map((artisan) => artisan.id).toList(), [
      'b',
      'c',
      'a',
    ]);
    expect(controller.recommendedArtisan?.id, 'b');
  });

  test('only verified, active artisans are offered', () {
    final verified = ArtisanProfile.fromJson(const {
      'id': 'a',
      'verification_status': 'VERIFIED',
      'is_active': true,
    });
    final unverified = ArtisanProfile.fromJson(const {
      'id': 'b',
      'verification_status': 'PENDING',
      'is_active': true,
    });
    final switchedOff = ArtisanProfile.fromJson(const {
      'id': 'c',
      'verification_status': 'VERIFIED',
      'is_active': false,
    });

    expect(verified.canBeContacted, isTrue);
    expect(unverified.canBeContacted, isFalse);
    expect(switchedOff.canBeContacted, isFalse);
  });

  test('a category the app has not seen still renders readably', () {
    expect(ArtisanCategory.prettify('GENERATOR_REPAIR'), 'Generator Repair');
    expect(
      ArtisanCategory.fromJson(const {'value': 'AC_REPAIR'}).label,
      'Ac Repair',
    );
  });

  // ------------------------------------------------------------ registration

  test('artisan trade fields are sent only for an artisan', () async {
    final bodies = <Map<String, dynamic>>[];
    http.Response respond(http.Request request) {
      if (request.url.path.endsWith('/register/')) {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _json({'id': 'user-1'}, status: 201);
      }
      return _json({
        'access': 'a',
        'refresh': 'r',
        'user': {'id': 'user-1', 'email': 'x@example.com', 'role': 'ARTISAN'},
      });
    }

    final service = ApiAuthService(
      apiClient: ApiClient(client: MockClient((r) async => respond(r))),
    );

    await service.register(
      email: 'artisan@example.com',
      password: 'Strongpass123!',
      phone: '08000000000',
      role: UserRole.artisan,
      category: 'PLUMBING',
      location: 'Lekki Phase 1',
      bio: 'Reliable plumber.',
      yearsOfExperience: 5,
    );

    expect(bodies.single, {
      'email': 'artisan@example.com',
      'password': 'Strongpass123!',
      'phone': '08000000000',
      'role': 'ARTISAN',
      'category': 'PLUMBING',
      'location': 'Lekki Phase 1',
      'bio': 'Reliable plumber.',
      'years_of_experience': 5,
    });

    bodies.clear();
    await service.register(
      email: 'tenant@example.com',
      password: 'Strongpass123!',
      phone: '08000000001',
      role: UserRole.tenant,
      // A stray value left on a half-filled form must never reach the wire
      // against a tenant: the backend rejects the whole registration.
      category: 'PLUMBING',
      location: 'Lekki Phase 1',
    );

    expect(bodies.single.keys, ['email', 'password', 'phone', 'role']);
    expect(bodies.single['role'], 'TENANT');
  });

  test('an ARTISAN role survives a round trip through the profile', () {
    final user = UserModel.fromJson(const {
      'id': 'user-1',
      'email': 'artisan@example.com',
      'role': 'ARTISAN',
      'verification_status': 'VERIFIED',
    });

    expect(user.role, UserRole.artisan);
    expect(user.role.isArtisan, isTrue);
    // An artisan is not a tenant. Read the other way round, they would inherit
    // every tenant-only affordance in the app.
    expect(user.role.isTenant, isFalse);
    expect(UserModel.fromJson(user.toJson()).role, UserRole.artisan);
  });

  // ---------------------------------------------------------------- session

  test('signing out clears artisans and the artisan profile', () async {
    // These carry a description of somebody's home and, once accepted, a phone
    // number. Left behind, the next person to sign in would see them.
    final controller = FixController(
      service: FixService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json([
              {'id': 'artisan-1', 'full_name': 'Ada Fixer'},
            ]),
          ),
        ),
      ),
    );

    await controller.loadCategories();
    await controller.loadArtisans();
    expect(controller.artisans, isNotEmpty);

    controller.resetSessionState();
    // An artisan's phone number and a landlord's recommendations both belong
    // to whoever was signed in.
    expect(controller.artisans, isEmpty);
    expect(controller.myProfile, isNull);
    expect(controller.selectedCategory, isNull);
  });
}

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
