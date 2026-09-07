import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:landa_app/core/network/api_client.dart';
import 'package:landa_app/core/network/api_constants.dart';
import 'package:landa_app/core/network/auth_token_storage.dart';
import 'package:landa_app/features/agreements/models/agreement_model.dart';
import 'package:landa_app/features/agreements/services/agreement_service.dart';
import 'package:landa_app/features/auth/controllers/auth_controller.dart';
import 'package:landa_app/features/auth/models/user_model.dart';
import 'package:landa_app/features/auth/services/api_auth_service.dart';
import 'package:landa_app/features/marketplace/models/marketplace_models.dart';
import 'package:landa_app/features/marketplace/services/marketplace_service.dart';
import 'package:landa_app/features/notifications/models/notification_model.dart';
import 'package:landa_app/features/notifications/services/notification_service.dart';
import 'package:landa_app/features/payments/controllers/payment_controller.dart';
import 'package:landa_app/features/payments/models/payment_model.dart';
import 'package:landa_app/features/payments/services/payment_service.dart';
import 'package:landa_app/features/properties/services/property_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test(
    'agreement creation, tenant signing, landlord execution, and payment follow the PRD contract',
    () async {
      var signCalls = 0;
      final apiClient = ApiClient(
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer test-access-token');

          switch (request.url.path) {
            case '/api/users/agreements/':
              expect(request.method, 'POST');
              expect(jsonDecode(request.body), {
                'unit': 'unit-id',
                'tenant': 'tenant@example.com',
                'rent_amount': '450000.00',
                'start_date': '2026-09-01',
                'end_date': '2027-08-31',
                'rules': 'Keep shared areas clean.',
              });
              return _jsonResponse(_agreementPayload(), 201);
            case '/api/users/agreements/agreement-id/sign/':
              expect(request.method, 'POST');
              expect(jsonDecode(request.body), isEmpty);
              signCalls++;
              return _jsonResponse(
                _agreementPayload(
                  tenantSigned: true,
                  executed: signCalls == 2,
                  landlordSigned: signCalls == 2,
                  payRentUnlocked: signCalls == 2,
                ),
              );
            case '/api/users/payments/':
              expect(request.method, 'POST');
              expect(signCalls, 2);
              expect(jsonDecode(request.body), {'agreement': 'agreement-id'});
              return _jsonResponse(_paymentPayload(status: 'PENDING'), 201);
            case '/api/users/payments/payment-id/verify/':
              expect(request.method, 'POST');
              expect(jsonDecode(request.body), {
                'reference': 'LR-1A2B3C4D5E6F',
              });
              return _jsonResponse(_paymentPayload(status: 'ESCROW'));
            default:
              fail('Unexpected API request: ${request.method} ${request.url}');
          }
        }),
      );
      final agreementService = AgreementService(apiClient: apiClient);
      final paymentService = PaymentService(apiClient: apiClient);

      final pending = await agreementService.createAgreement(
        unitId: 'unit-id',
        tenantId: 'tenant@example.com',
        rentAmount: '450000.00',
        startDate: '2026-09-01',
        endDate: '2027-08-31',
        rules: 'Keep shared areas clean.',
      );
      expect(pending.status, AgreementStatus.pending);
      expect(pending.canTenantSign, isTrue);
      expect(pending.canLandlordSign, isFalse);
      expect(pending.canPayRent, isFalse);

      final tenantSigned = await agreementService.signAgreement(pending.id);
      expect(tenantSigned.status, AgreementStatus.pending);
      expect(tenantSigned.hasTenantSigned, isTrue);
      expect(tenantSigned.canLandlordSign, isTrue);
      expect(tenantSigned.canPayRent, isFalse);

      final executed = await agreementService.signAgreement(tenantSigned.id);
      expect(executed.status, AgreementStatus.executed);
      expect(executed.hasLandlordSigned, isTrue);
      expect(executed.canPayRent, isTrue);

      final initializedPayment = await paymentService.initializePayment(
        executed.id,
      );
      expect(initializedPayment.agreementStatus, 'EXECUTED');
      expect(initializedPayment.status, PaymentStatus.pending);
      expect(
        initializedPayment.authorizationUrl,
        'https://checkout.paystack.com/example',
      );

      final escrowPayment = await paymentService.verifyPayment(
        initializedPayment,
      );
      expect(escrowPayment.status, PaymentStatus.escrow);
    },
  );

  test(
    'the payment controller never calls the backend before rent is unlocked',
    () async {
      var paymentRequests = 0;
      final paymentService = PaymentService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            paymentRequests++;
            expect(request.url.path, '/api/users/payments/');
            return _jsonResponse(_paymentPayload(), 201);
          }),
        ),
      );
      final controller = PaymentController(paymentService: paymentService);
      final lockedAgreement = TenancyAgreementModel.fromJson(
        _agreementPayload(),
      );

      final lockedPayment = await controller.initializePayment(lockedAgreement);
      expect(lockedPayment, isNull);
      expect(paymentRequests, 0);
      expect(controller.errorMessage, contains('locked'));

      final executedAgreement = TenancyAgreementModel.fromJson(
        _agreementPayload(
          tenantSigned: true,
          landlordSigned: true,
          executed: true,
          payRentUnlocked: true,
        ),
      );
      final createdPayment = await controller.initializePayment(
        executedAgreement,
      );
      expect(createdPayment, isNotNull);
      expect(paymentRequests, 1);
    },
  );

  test(
    'escrow status exposes the backend countdown and dispute window',
    () async {
      final paymentService = PaymentService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.url.path, '/api/users/payments/payment-id/escrow/');
            return _jsonResponse(
              _paymentPayload(escrowSecondsRemaining: 172800, canDispute: true),
            );
          }),
        ),
      );

      final escrow = await paymentService.getEscrowStatus('payment-id');
      expect(escrow.status, PaymentStatus.escrow);
      expect(escrow.escrowSecondsRemaining, 172800);
      expect(escrow.canDispute, isTrue);
      expect(escrow.disputedAt, isNull);
    },
  );

  test('disputing a payment sends the reason and closes the window', () async {
    final paymentService = PaymentService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/users/payments/payment-id/dispute/');
          expect(jsonDecode(request.body), {
            'reason': 'The unit was not handed over as agreed.',
          });
          return _jsonResponse(
            _paymentPayload(
              status: 'DISPUTED',
              canDispute: false,
              disputedAt: '2026-08-15T11:00:00Z',
              disputeReason: 'The unit was not handed over as agreed.',
            ),
          );
        }),
      ),
    );

    final disputed = await paymentService.disputePayment(
      'payment-id',
      reason: 'The unit was not handed over as agreed.',
    );
    expect(disputed.status, PaymentStatus.disputed);
    expect(disputed.canDispute, isFalse);
    expect(disputed.disputedAt, isNotNull);
    expect(disputed.disputeReason, 'The unit was not handed over as agreed.');
  });

  test(
    'verifyIdentity retries automatically after accepting required consent',
    () async {
      // MultipartFile.fromPath reads the file from disk, so this needs to
      // actually exist: content is irrelevant since the backend is mocked.
      final selfieFile = File(
        '${Directory.systemTemp.path}/landa_consent_test_selfie.jpg',
      )..writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xE0]);
      addTearDown(() {
        if (selfieFile.existsSync()) selfieFile.deleteSync();
      });

      var verifyCalls = 0;
      var consentCalls = 0;

      final apiClient = ApiClient(
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer test-access-token');

          if (request.method == 'POST' &&
              request.url.path == '/api/users/consents/') {
            consentCalls++;
            // Consent must only ever be requested after the backend has
            // actually rejected a verification attempt for missing it.
            expect(verifyCalls, 1);
            expect(jsonDecode(request.body), {
              'consent_type': 'VERIFICATION_PRIVACY',
              'version': '2026-08-15',
            });
            return _jsonResponse({
              'id': 'consent-id',
              'consent_type': 'VERIFICATION_PRIVACY',
              'version': '2026-08-15',
              'accepted_at': '2026-08-15T10:30:00Z',
            }, 201);
          }

          if (request.method == 'POST' &&
              request.url.path == '/api/users/verify/') {
            verifyCalls++;
            if (verifyCalls == 1) {
              expect(consentCalls, 0);
              return _jsonResponse({
                'code': 'CONSENT_REQUIRED',
                'detail':
                    'Accept verification and privacy consent before starting verification.',
              }, 403);
            }
            // The retry must not fire until consent actually succeeded.
            expect(consentCalls, 1);
            return _jsonResponse({
              'status': 'PENDING',
              'badge': 'PENDING',
              'user': {
                'id': 'tenant-id',
                'email': 'tenant@example.com',
                'phone': '+2348012345678',
                'role': 'TENANT',
                'verification_status': 'PENDING',
              },
            }, 202);
          }

          fail('Unexpected API request: ${request.method} ${request.url}');
        }),
      );

      final controller = AuthController(
        authService: ApiAuthService(apiClient: apiClient),
      );

      final rejected = await controller.verifyIdentity(
        selfie: selfieFile,
        nin: '12345678901',
      );
      expect(rejected, isNull);
      expect(controller.consentRequired, isTrue);
      expect(verifyCalls, 1);
      expect(consentCalls, 0);

      final consentAccepted = await controller.acceptVerificationConsent();
      expect(consentAccepted, isTrue);
      expect(controller.consentRequired, isFalse);
      expect(consentCalls, 1);

      final retried = await controller.verifyIdentity(
        selfie: selfieFile,
        nin: '12345678901',
      );
      expect(retried, VerificationStatus.pending);
      expect(verifyCalls, 2);
    },
  );

  test('creating an agreement sends the chosen rent plan', () async {
    Map<String, dynamic>? sentBody;
    final service = AgreementService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonResponse({
            'id': 'agreement-1',
            'status': 'PENDING',
            'rent_amount': '450000.00',
            'rent_plan': 'MONTHLY',
            'rent_schedule': null,
          }, 201);
        }),
      ),
    );

    final agreement = await service.createAgreement(
      unitId: 'unit-1',
      tenantId: 'tenant@example.com',
      rentAmount: '450000.00',
      startDate: '2026-09-01',
      endDate: '2027-08-31',
      rules: 'Standard tenancy rules apply.',
      rentPlan: RentPlan.monthly,
    );

    // The canonical value, never an alias, and rent_amount stays the annual
    // figure, which the backend splits into instalments itself.
    expect(sentBody?['rent_plan'], 'MONTHLY');
    expect(sentBody?['rent_amount'], '450000.00');
    expect(agreement.rentPlan, RentPlan.monthly);
    // Null until the agreement is payable, exactly as documented.
    expect(agreement.rentSchedule, isNull);
    expect(agreement.plan, RentPlan.monthly);
  });

  test(
    'an agreement created without a plan lets the backend default',
    () async {
      Map<String, dynamic>? sentBody;
      final service = AgreementService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _jsonResponse({
              'id': 'agreement-1',
              'status': 'PENDING',
              'rent_plan': 'ANNUAL',
            }, 201);
          }),
        ),
      );

      await service.createAgreement(
        unitId: 'unit-1',
        tenantId: 'tenant@example.com',
        rentAmount: '450000.00',
        startDate: '2026-09-01',
        endDate: '2027-08-31',
        rules: '',
      );

      // Sending nothing is not the same as sending a guess: the backend owns
      // the default, and this keeps it that way.
      expect(sentBody?.containsKey('rent_plan'), isFalse);
    },
  );

  test('the documented rent schedule parses field for field', () async {
    // Verbatim from the guide's rent_schedule example.
    final agreement = TenancyAgreementModel.fromJson({
      'id': 'agreement-1',
      'status': 'EXECUTED',
      'rent_amount': '1260000.00',
      'rent_plan': 'MONTHLY',
      'pay_rent_unlocked': true,
      'rent_schedule': {
        'plan': 'MONTHLY',
        'next_due_date': '2026-09-01',
        'next_amount_due': '105000.00',
        'days_until_due': 2,
        'is_overdue': false,
        'instalments_paid': 0,
        'instalments_total': 12,
      },
    });

    final schedule = agreement.upcomingRent!;
    expect(schedule.plan, RentPlan.monthly);
    expect(schedule.nextDueDate, '2026-09-01');
    // Already fee-inclusive per the guide, so nothing is added to it here.
    expect(schedule.nextAmountDue, '105000.00');
    expect(schedule.daysUntilDue, 2);
    expect(schedule.isOverdue, isFalse);
    expect(schedule.isDueNow, isFalse);
    expect(schedule.isDueSoon, isTrue);
    expect(schedule.instalmentsPaid, 0);
    expect(schedule.instalmentsTotal, 12);
  });

  test('marketplace filters map to backend query parameters', () async {
    final captured = <String, String>{};
    final service = MarketplaceService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/users/tenant/marketplace/');
          captured
            ..clear()
            ..addAll(request.url.queryParameters);
          return _jsonResponse2([
            {
              'id': 'property-id',
              'name': 'Sunset House',
              'address': '123 Main Street',
              'city': 'Lagos',
              'state': 'Lagos',
              'verification_status': 'VERIFIED',
              'created_at': '2026-08-06T09:30:00Z',
              'available_units': [
                {
                  'id': 'unit-id',
                  'unit_number': 'A1',
                  'bedrooms': 2,
                  'bathrooms': 2,
                  'rent_amount': '450000.00',
                  'is_occupied': false,
                  'tenant': null,
                  'created_at': '2026-08-06T09:30:00Z',
                },
              ],
            },
          ]);
        }),
      ),
    );

    final listings = await service.getMarketplace(
      filters: const MarketplaceFilters(
        city: 'Lagos',
        maxRent: '300000',
        bedrooms: 2,
      ),
    );
    // max_price, not max_rent: the 2026-09-03 search update's shared param
    // name across rentals and short lets.
    expect(captured, {'city': 'Lagos', 'max_price': '300000', 'bedrooms': '2'});
    expect(listings.single.property.name, 'Sunset House');
    expect(listings.single.availableUnits.single.unitNumber, 'A1');
    expect(listings.single.lowestRent, 450000.00);

    // Blank filter fields must be omitted, not sent as empty strings.
    await service.getMarketplace(
      filters: const MarketplaceFilters(city: '', minRent: ''),
    );
    expect(captured, isEmpty);
  });

  test('applying for a unit posts the unit id', () async {
    final service = MarketplaceService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/users/tenant/applications/');
          expect(jsonDecode(request.body), {'unit': 'unit-id'});
          return _jsonResponse({
            'id': 'application-id',
            'unit': 'unit-id',
            'unit_number': 'A1',
            'status': 'PENDING',
            'created_at': '2026-08-17T09:00:00Z',
          }, 201);
        }),
      ),
    );

    final application = await service.applyForUnit('unit-id');
    expect(application.id, 'application-id');
    expect(application.status, ApplicationStatus.pending);
    expect(application.unitId, 'unit-id');
  });

  test('approving an application sends the agreement terms', () async {
    final service = MarketplaceService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.path,
            '/api/users/landlord/applications/application-id/approve/',
          );
          expect(jsonDecode(request.body), {
            'start_date': '2026-09-01',
            'end_date': '2027-08-31',
            'rules': 'Standard tenancy rules apply.',
          });
          return _jsonResponse({
            'id': 'application-id',
            'unit': 'unit-id',
            'unit_number': 'A1',
            'status': 'APPROVED',
            'created_at': '2026-08-17T09:00:00Z',
          });
        }),
      ),
    );

    final approved = await service.approveApplication(
      applicationId: 'application-id',
      startDate: '2026-09-01',
      endDate: '2027-08-31',
      rules: 'Standard tenancy rules apply.',
    );
    expect(approved.status, ApplicationStatus.approved);
  });

  test('marketplace parses the documented response shape', () async {
    // Verbatim from the guide's "Tenant Marketplace And Applications" example.
    final service = MarketplaceService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          return _jsonResponse2([
            {
              'id': 'PROPERTY_UUID',
              'name': 'Sunset House',
              'address': '12 Listing Road',
              'city': 'Lagos',
              'state': 'Lagos',
              'photo_urls': ['https://example.test/front.jpg'],
              'cover_photo_url': 'https://example.test/front.jpg',
              'video_url': 'https://example.test/tour.mp4',
              'available_units': [
                {
                  'id': 'UNIT_UUID',
                  'unit_number': 'A1',
                  'bedrooms': 2,
                  'bathrooms': 2,
                  'rent_amount': '300000.00',
                  'created_at': '2026-08-18T09:00:00Z',
                },
              ],
            },
          ]);
        }),
      ),
    );

    final listing = (await service.getMarketplace()).single;
    expect(listing.property.name, 'Sunset House');
    expect(listing.property.coverPhotoUrl, 'https://example.test/front.jpg');
    expect(listing.property.videoUrl, 'https://example.test/tour.mp4');
    expect(listing.property.hasVideo, isTrue);
    expect(listing.property.displayImageUrl, 'https://example.test/front.jpg');
    expect(listing.availableUnits.single.unitNumber, 'A1');
  });

  test(
    'landlord applications parse the documented applicant payload',
    () async {
      final service = MarketplaceService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            return _jsonResponse2([
              {
                'id': 'APPLICATION_UUID',
                'property': {
                  'id': 'PROPERTY_UUID',
                  'name': 'Sunset House',
                  'address': '12 Listing Road',
                  'city': 'Lagos',
                  'state': 'Lagos',
                },
                'unit': {
                  'id': 'UNIT_UUID',
                  'unit_number': 'A1',
                  'bedrooms': 2,
                  'bathrooms': 2,
                  'rent_amount': '300000.00',
                },
                'tenant': {
                  'id': 'TENANT_UUID',
                  'full_name': 'Ada Okafor',
                  'email': 'ada@example.com',
                  'phone_number': '+2348012345678',
                },
                'tenant_name': 'Ada Okafor',
                'tenant_email': 'ada@example.com',
                'tenant_phone': '+2348012345678',
                'tenant_verification_status': 'VERIFIED',
                'unit_number': 'A1',
                'rent_amount': '300000.00',
                'message': 'I am interested in this unit and can move in soon.',
                'status': 'PENDING',
                'agreement_id': null,
                'applied_at': '2026-08-18T09:00:00Z',
                'created_at': '2026-08-18T09:00:00Z',
                'decided_at': null,
              },
            ]);
          }),
        ),
      );

      final application = (await service.getLandlordApplications()).single;
      expect(application.tenantName, 'Ada Okafor');
      expect(application.tenantEmail, 'ada@example.com');
      expect(application.tenantPhone, '+2348012345678');
      expect(application.tenantVerificationStatus, 'VERIFIED');
      expect(application.hasApplicantDetails, isTrue);
      expect(application.unitId, 'UNIT_UUID');
      expect(application.rentAmount, '300000.00');
      expect(application.hasMessage, isTrue);
      expect(application.property?.name, 'Sunset House');
      expect(application.agreementId, isNull);
      expect(application.decidedAt, isNull);
    },
  );

  test('applying sends an optional message and omits it when blank', () async {
    Map<String, dynamic>? captured;
    final service = MarketplaceService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonResponse({
            'id': 'application-id',
            'unit': 'unit-id',
            'unit_number': 'A1',
            'status': 'PENDING',
            'message': captured?['message'] ?? '',
            'created_at': '2026-08-18T09:00:00Z',
          }, 201);
        }),
      ),
    );

    await service.applyForUnit('unit-id', message: '  Keen to move in.  ');
    expect(captured, {'unit': 'unit-id', 'message': 'Keen to move in.'});

    // A blank note must not be sent as an empty string.
    await service.applyForUnit('unit-id', message: '   ');
    expect(captured, {'unit': 'unit-id'});

    await service.applyForUnit('unit-id');
    expect(captured, {'unit': 'unit-id'});
  });

  test('property listing photo and video endpoints round-trip', () async {
    var deletedPhoto = false;
    var deletedVideo = false;
    final service = PropertyService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/users/properties/prop-1/photos/' &&
              request.method == 'GET') {
            return _jsonResponse2([
              {
                'id': 'PHOTO_UUID',
                'image_url': 'https://example.test/front.jpg',
                'created_at': '2026-08-18T09:30:00Z',
              },
            ]);
          }
          if (path == '/api/users/properties/prop-1/photos/PHOTO_UUID/' &&
              request.method == 'DELETE') {
            deletedPhoto = true;
            // Deletion answers 204 with no body.
            return http.Response('', 204);
          }
          if (path == '/api/users/properties/prop-1/video/') {
            if (request.method == 'GET') {
              return _jsonResponse({
                'video_url': 'https://example.test/tour.mp4',
              });
            }
            if (request.method == 'DELETE') {
              deletedVideo = true;
              return http.Response('', 204);
            }
          }
          fail('Unexpected request: ${request.method} ${request.url}');
        }),
      ),
    );

    final photos = await service.getPropertyPhotos('prop-1');
    expect(photos.single.id, 'PHOTO_UUID');
    expect(photos.single.imageUrl, 'https://example.test/front.jpg');

    expect(
      await service.getPropertyVideo('prop-1'),
      'https://example.test/tour.mp4',
    );

    await service.deletePropertyPhoto(
      propertyId: 'prop-1',
      photoId: 'PHOTO_UUID',
    );
    await service.deletePropertyVideo('prop-1');
    expect(deletedPhoto, isTrue);
    expect(
      deletedVideo,
      isTrue,
      reason: '204 No Content must be treated as success, not a parse failure',
    );
  });

  test('a property with no video reports none', () async {
    final service = PropertyService(
      apiClient: ApiClient(
        client: MockClient(
          (request) async => _jsonResponse({'video_url': null}),
        ),
      ),
    );
    expect(await service.getPropertyVideo('prop-1'), isNull);
  });

  test('applicant details parse from flattened or nested payloads', () {
    final flattened = RentalApplication.fromJson({
      'id': 'a1',
      'unit': 'unit-id',
      'unit_number': 'B22',
      'status': 'PENDING',
      'tenant_name': 'Ada Okafor',
      'tenant_email': 'ada@example.com',
      'tenant_phone': '+2348012345678',
    });
    expect(flattened.tenantName, 'Ada Okafor');
    expect(flattened.tenantEmail, 'ada@example.com');
    expect(flattened.tenantPhone, '+2348012345678');
    expect(flattened.hasApplicantDetails, isTrue);

    final nested = RentalApplication.fromJson({
      'id': 'a2',
      'unit': {'id': 'unit-id', 'unit_number': 'B22'},
      'status': 'PENDING',
      'tenant': {
        'full_name': 'Ada Okafor',
        'email': 'ada@example.com',
        'phone_number': '+2348012345678',
      },
    });
    expect(nested.tenantName, 'Ada Okafor');
    expect(nested.tenantEmail, 'ada@example.com');
    expect(nested.unitId, 'unit-id');

    // A bare tenant UUID identifies the row but is not contact information,
    // and must never be surfaced as if it were the applicant's name/email.
    final uuidOnly = RentalApplication.fromJson({
      'id': 'a3',
      'unit': 'unit-id',
      'status': 'PENDING',
      'tenant': 'f8c88b5d-3d87-4f86-b402-39d8e68bff88',
    });
    expect(uuidOnly.tenantEmail, isNull);
    expect(uuidOnly.tenantName, isNull);
    expect(uuidOnly.hasApplicantDetails, isFalse);
  });

  test('an unrecognised application status is never treated as pending', () {
    expect(
      ApplicationStatus.fromString('APPROVED'),
      ApplicationStatus.approved,
    );
    expect(
      ApplicationStatus.fromString('REJECTED'),
      ApplicationStatus.rejected,
    );
    expect(
      ApplicationStatus.fromString('ESCALATED'),
      ApplicationStatus.unknown,
    );
    expect(ApplicationStatus.unknown.isPending, isFalse);
  });

  test('notification filters are sent as backend query parameters', () async {
    final captured = <String, String>{};
    final service = NotificationService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          expect(request.url.path, '/api/users/notifications/');
          captured.addAll(request.url.queryParameters);
          return http.Response(
            jsonEncode([
              {
                'id': 'notification-id',
                'notification_type': 'PAYMENT_RECORDED',
                'message': 'Rent payment recorded.',
                'is_read': false,
                'created_at': '2026-08-15T10:00:00Z',
              },
            ]),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final filtered = await service.getNotifications(
      type: NotificationType.paymentRecorded,
      isRead: false,
    );
    expect(captured, {'type': 'PAYMENT_RECORDED', 'is_read': 'false'});
    expect(filtered.single.type, NotificationType.paymentRecorded);

    // Unset filters must not be sent at all, rather than as empty strings.
    captured.clear();
    await service.getNotifications();
    expect(captured, isEmpty);
  });

  test('unknown notification types degrade gracefully', () {
    expect(
      NotificationType.fromString('AGREEMENT_EXECUTED'),
      NotificationType.agreementExecuted,
    );
    expect(
      NotificationType.fromString('PAYMENT_INITIATED'),
      NotificationType.paymentInitiated,
    );
    expect(
      NotificationType.fromString('SOMETHING_NEW'),
      NotificationType.unknown,
    );
    expect(NotificationType.unknown.queryValue, isNull);
  });

  test('an unrecognised payment status never masquerades as ESCROW', () {
    // Regression guard: the old fromString() fell through to `escrow`, which
    // would have shown a DISPUTED/REFUNDED payment as safely held funds.
    expect(PaymentStatus.fromString('DISPUTED'), PaymentStatus.disputed);
    expect(PaymentStatus.fromString('REFUNDED'), PaymentStatus.refunded);
    expect(PaymentStatus.fromString('SOMETHING_NEW'), PaymentStatus.unknown);
    expect(PaymentStatus.fromString(null), PaymentStatus.unknown);
  });
}

http.Response _jsonResponse(Map<String, dynamic> body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: const {'content-type': 'application/json'},
  );
}

/// List-shaped variant, for endpoints that return a raw array.
http.Response _jsonResponse2(List<dynamic> body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: const {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _agreementPayload({
  bool tenantSigned = false,
  bool landlordSigned = false,
  bool executed = false,
  bool payRentUnlocked = false,
}) {
  return {
    'id': 'agreement-id',
    'unit': 'unit-id',
    'unit_number': 'A1',
    'landlord': 'landlord-id',
    'landlord_email': 'owner@example.com',
    'tenant': 'tenant-id',
    'tenant_email': 'tenant@example.com',
    'rent_amount': '450000.00',
    'start_date': '2026-09-01',
    'end_date': '2027-08-31',
    'rules': 'Keep shared areas clean.',
    'agreement_text': 'Tenancy agreement text.',
    'status': executed ? 'EXECUTED' : 'PENDING',
    'agreement_content_hash': 'agreement-content-hash',
    'tenant_signature_hash': tenantSigned ? 'tenant-signature' : '',
    'landlord_signature_hash': landlordSigned ? 'landlord-signature' : '',
    'tenant_signed_at': tenantSigned ? '2026-08-13T10:05:00Z' : null,
    'landlord_signed_at': landlordSigned ? '2026-08-13T10:10:00Z' : null,
    'executed_at': executed ? '2026-08-13T10:10:00Z' : null,
    'pay_rent_unlocked': payRentUnlocked,
    'created_at': '2026-08-13T10:00:00Z',
  };
}

Map<String, dynamic> _paymentPayload({
  String status = 'ESCROW',
  int? escrowSecondsRemaining,
  bool canDispute = false,
  String? disputedAt,
  String disputeReason = '',
}) {
  final isHeld = status == 'ESCROW' || status == 'DISPUTED';
  return {
    'id': 'payment-id',
    'agreement': 'agreement-id',
    'agreement_status': 'EXECUTED',
    'tenant': 'tenant-id',
    'tenant_email': 'tenant@example.com',
    'amount': '450000.00',
    'platform_fee': '22500.00',
    'total_amount': '472500.00',
    'reference': 'LR-1A2B3C4D5E6F',
    'provider': 'paystack',
    'provider_reference': 'LR-1A2B3C4D5E6F',
    'authorization_url': 'https://checkout.paystack.com/example',
    'access_code': 'access-code',
    'status': status,
    'paid_at': isHeld ? '2026-08-13T10:15:00Z' : null,
    'escrow_release_at': isHeld ? '2026-08-15T10:15:00Z' : null,
    'escrow_seconds_remaining': escrowSecondsRemaining,
    'can_dispute': canDispute,
    'disputed_at': disputedAt,
    'dispute_reason': disputeReason,
    'is_ready_for_release': false,
    'released_at': null,
  };
}
