import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:landa_app/core/network/api_client.dart';
import 'package:landa_app/core/network/api_constants.dart';
import 'package:landa_app/core/network/auth_token_storage.dart';
import 'package:landa_app/core/session/session_scope.dart';
import 'package:landa_app/features/auth/controllers/auth_controller.dart';
import 'package:landa_app/features/auth/models/consent_model.dart';
import 'package:landa_app/features/auth/models/user_model.dart';
import 'package:landa_app/features/auth/services/i_auth_service.dart';
import 'package:landa_app/features/marketplace/controllers/marketplace_controller.dart';
import 'package:landa_app/features/marketplace/services/marketplace_service.dart';
import 'package:landa_app/features/notifications/controllers/notification_controller.dart';
import 'package:landa_app/features/notifications/services/notification_service.dart';
import 'package:landa_app/features/payments/controllers/payment_controller.dart';
import 'package:landa_app/features/payments/services/payment_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression cover for per-user data surviving a sign-out.
///
/// Feature controllers are process-lifetime singletons, so before the
/// SessionScope reset the next user to sign in briefly saw the previous
/// user's data rendered from memory while their own fetches were in flight.
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
    SessionScope.clearRegistrations();
  });

  test('signing out clears every registered controller', () async {
    final apiClient = ApiClient(
      client: MockClient((request) async {
        // Payments list for user A.
        if (request.url.path == '/api/users/payments/') {
          return _json([
            {
              'id': 'payment-a',
              'agreement': 'agreement-a',
              'agreement_status': 'EXECUTED',
              'tenant': 'tenant-a',
              'tenant_email': 'user-a@example.com',
              'amount': '450000.00',
              'reference': 'LR-USERA',
              'status': 'ESCROW',
              'is_ready_for_release': false,
            },
          ]);
        }
        if (request.url.path == '/api/users/notifications/') {
          return _json([
            {
              'id': 'notification-a',
              'notification_type': 'PAYMENT_RECORDED',
              'message': 'User A rent recorded.',
              'is_read': false,
              'created_at': '2026-08-17T09:00:00Z',
            },
          ]);
        }
        if (request.url.path == '/api/users/landlord/applications/') {
          return _json([
            {
              'id': 'application-a',
              'unit': 'unit-a',
              'unit_number': 'A1',
              'status': 'PENDING',
              'created_at': '2026-08-17T09:00:00Z',
            },
          ]);
        }
        fail('Unexpected request: ${request.method} ${request.url}');
      }),
    );

    final payments = PaymentController(
      paymentService: PaymentService(apiClient: apiClient),
    );
    final notifications = NotificationController(
      notificationService: NotificationService(apiClient: apiClient),
    );
    final marketplace = MarketplaceController(
      service: MarketplaceService(apiClient: apiClient),
    );

    SessionScope.register([payments, notifications, marketplace]);

    // --- User A populates the shared controllers.
    await payments.loadPayments();
    await notifications.loadNotifications();
    await marketplace.loadLandlordApplications();

    expect(payments.payments, hasLength(1));
    expect(notifications.notifications, hasLength(1));
    expect(notifications.unreadCount, 1);
    expect(marketplace.landlordApplications, hasLength(1));
    expect(marketplace.pendingLandlordApplicationCount, 1);

    // --- User A signs out.
    final auth = AuthController(authService: _FakeAuthService());
    await auth.logout();

    // Nothing belonging to user A may remain for the next sign-in to render.
    expect(payments.payments, isEmpty);
    expect(payments.selectedReceipt, isNull);
    expect(notifications.notifications, isEmpty);
    expect(
      notifications.unreadCount,
      0,
      reason: 'the app-bar badge is visible on every screen',
    );
    expect(marketplace.landlordApplications, isEmpty);
    expect(
      marketplace.pendingLandlordApplicationCount,
      0,
      reason: 'drives the red dot on the landlord nav bar',
    );
    expect(auth.currentUser, isNull);
    expect(auth.isAuthenticated, isFalse);
  });

  test(
    'signing in clears state left by a session that never logged out',
    () async {
      // An expired refresh token clears storage from inside ApiClient without
      // ever calling logout(), so login() must clear on the way in too.
      final notifications = NotificationController();
      final marketplace = MarketplaceController();
      SessionScope.register([notifications, marketplace]);

      final auth = AuthController(authService: _FakeAuthService());
      await auth.login('user-b@example.com', 'password');

      expect(auth.isAuthenticated, isTrue);
      expect(notifications.notifications, isEmpty);
      expect(notifications.unreadCount, 0);
      expect(marketplace.listings, isEmpty);
    },
  );

  test(
    'a reset controller reports "not loaded", not "loaded and empty"',
    () async {
      // Screens paint their first frame before initState's post-frame
      // callback starts the fetch. At that instant isLoading is still false
      // and the list is empty, so a screen keying its skeleton off
      // `isLoading && isEmpty` alone would flash a "no applications" state
      // at a user who in fact has some.
      final apiClient = ApiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/users/landlord/applications/') {
            return _json([
              {
                'id': 'application-a',
                'unit': 'unit-a',
                'unit_number': 'A1',
                'status': 'PENDING',
                'created_at': '2026-08-17T09:00:00Z',
              },
            ]);
          }
          if (request.url.path == '/api/users/notifications/') {
            return _json([]);
          }
          fail('Unexpected request: ${request.method} ${request.url}');
        }),
      );

      final marketplace = MarketplaceController(
        service: MarketplaceService(apiClient: apiClient),
      );
      final notifications = NotificationController(
        notificationService: NotificationService(apiClient: apiClient),
      );
      SessionScope.register([marketplace, notifications]);

      // Before any load: not loaded, and not merely "empty".
      expect(marketplace.hasLoadedLandlordApplications, isFalse);
      expect(notifications.hasLoaded, isFalse);

      await marketplace.loadLandlordApplications();
      await notifications.loadNotifications();
      expect(marketplace.hasLoadedLandlordApplications, isTrue);
      expect(
        notifications.hasLoaded,
        isTrue,
        reason: 'set even though the list came back genuinely empty',
      );

      SessionScope.resetAll();

      expect(
        marketplace.hasLoadedLandlordApplications,
        isFalse,
        reason: 'next screen must show a skeleton, not an empty state',
      );
      expect(marketplace.isLoading, isFalse);
      expect(notifications.hasLoaded, isFalse);
    },
  );

  test('resetAll is safe when nothing is registered', () {
    SessionScope.clearRegistrations();
    expect(SessionScope.resetAll, returnsNormally);
  });
}

http.Response _json(List<dynamic> body, [int statusCode = 200]) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: const {'content-type': 'application/json'},
    );

class _FakeAuthService implements IAuthService {
  @override
  Future<UserModel> login({
    required String email,
    required String password,
  }) async => UserModel(
    id: 'user-b',
    email: email,
    phone: '+2348012345678',
    role: UserRole.tenant,
    verificationStatus: VerificationStatus.verified,
  );

  @override
  Future<void> logout() async {}

  @override
  Future<UserModel> getProfile() => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> getVerificationStatus() =>
      throw UnimplementedError();

  @override
  Future<UserModel> register({
    required String email,
    required String password,
    required String phone,
    required UserRole role,
    String? category,
    String? location,
    String? bio,
    int? yearsOfExperience,
  }) => throw UnimplementedError();

  @override
  Future<void> requestPasswordReset({required String email}) async {}

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {}

  @override
  Future<ConsentModel> acceptConsent({
    required String consentType,
    required String version,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> verifyIdentity({
    required File selfie,
    required String nin,
    String? givenNames,
    String? lastName,
    String? email,
  }) => throw UnimplementedError();
}
