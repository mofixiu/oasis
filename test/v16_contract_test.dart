import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/features/shortlets/models/shortlet_models.dart';
import 'package:oasis_app/features/support/services/support_service.dart';

/// The parts of API guide 20 (spec v16) the app has to read a particular way.
void main() {
  group('POST /host/listings/ response', () {
    HostListingResult parse(Map<String, dynamic> json) =>
        HostListingResult.fromJson(
          json,
          fallbackUnitNumber: '1',
          fallbackBedrooms: 2,
          fallbackBathrooms: 1,
        );

    test('reads the listing with its property and unit nested in it', () {
      // The shape the backend confirmed: the normal short-let listing.
      final result = parse({
        'id': 'l-1',
        'property': {'id': 'p-1', 'name': 'The Lekki Loft'},
        'unit': {
          'id': 'u-1',
          'unit_number': '3B',
          'bedrooms': 3,
          'bathrooms': 2,
        },
        'nightly_price': '85000.00',
        'is_active': true,
        'photo_urls': <String>[],
        'cover_photo_url': null,
      });

      expect(result.propertyId, 'p-1');
      expect(result.unitId, 'u-1');
      expect(result.unitNumber, '3B');
      expect(result.bedrooms, 3);
      expect(result.bathrooms, 2);
      expect(result.listing.id, 'l-1');
      expect(result.listing.nightlyPrice, '85000.00');
      expect(result.listing.photoUrls, isEmpty);
    });

    test('finds the property inside the unit when it is not alongside', () {
      final result = parse({
        'id': 'l-2',
        'unit': {
          'id': 'u-2',
          'unit_number': 'A1',
          'property': {'id': 'p-2'},
        },
        'property_name': 'Palm Court',
        'nightly_price': '60000.00',
      });

      expect(result.listing.id, 'l-2');
      expect(result.unitId, 'u-2');
      expect(result.propertyId, 'p-2');
      expect(result.unitNumber, 'A1');
      // Not in the response, so what the host typed stands in.
      expect(result.bedrooms, 2);
    });

    test('takes ids sent as plain strings', () {
      final result = parse({
        'id': 'l-3',
        'unit': 'u-3',
        'property_id': 'p-3',
        'nightly_price': '40000.00',
      });

      expect(result.unitId, 'u-3');
      expect(result.propertyId, 'p-3');
      expect(result.unitNumber, '1');
    });
  });

  test('a blank app-config value stays blank', () {
    final config = AppConfig.fromJson({
      'support_email': '',
      'support_phone': ' ',
      'support_whatsapp': '+234 800 000 0000',
      'support_hours': '',
      'terms_url': '',
      'privacy_url': '',
    });

    expect(config.supportEmail, isEmpty);
    expect(config.supportPhone, isEmpty);
    expect(config.supportWhatsApp, '+234 800 000 0000');
    expect(config.termsUrl, isEmpty);
    expect(config.hasDirectContact, isTrue);
  });

  test('host payout release time falls back to escrow_release_at', () {
    final booking = ShortLetBooking.fromJson({
      'id': 'b-1',
      'status': 'PAID',
      'escrow_release_at': '2026-11-02T11:00:00Z',
    });

    expect(booking.hostPayoutReleaseAt, '2026-11-02T11:00:00Z');
  });
}
