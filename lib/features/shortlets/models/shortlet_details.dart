import 'package:flutter/material.dart';

/// What kind of place a shortlet is. Asked first on the space step because
/// it is how guests describe what they want ("a studio in Lekki"), and it
/// frames every question after it.
enum ShortLetPlaceType {
  apartment('APARTMENT', 'Apartment', Icons.apartment_outlined),
  studio('STUDIO', 'Studio', Icons.single_bed_outlined),
  servicedApartment(
    'SERVICED_APARTMENT',
    'Serviced apartment',
    Icons.room_service_outlined,
  ),
  penthouse('PENTHOUSE', 'Penthouse', Icons.location_city_outlined),
  duplex('DUPLEX', 'Duplex', Icons.holiday_village_outlined),
  terrace('TERRACE', 'Terrace', Icons.house_siding_outlined),
  house('HOUSE', 'Detached house', Icons.house_outlined),
  room('ROOM', 'Private room', Icons.bed_outlined);

  final String wireValue;
  final String label;
  final IconData icon;

  const ShortLetPlaceType(this.wireValue, this.label, this.icon);

  static ShortLetPlaceType? fromString(String? value) {
    final wire = value?.trim().toUpperCase();
    for (final type in values) {
      if (type.wireValue == wire) return type;
    }
    return null;
  }
}

/// What the place has. Picked from a list rather than typed so guests can
/// compare listings like for like, and so search can filter on them later.
enum ShortLetAmenity {
  wifi('WIFI', 'Wi-Fi', Icons.wifi_rounded),
  power('POWER_24H', '24-hour power', Icons.bolt_rounded),
  airConditioning('AIR_CONDITIONING', 'Air conditioning', Icons.ac_unit),
  kitchen('KITCHEN', 'Kitchen', Icons.kitchen_outlined),
  parking('PARKING', 'Parking', Icons.local_parking_rounded),
  security('SECURITY', '24-hour security', Icons.security_outlined),
  hotWater('HOT_WATER', 'Hot water', Icons.hot_tub_outlined),
  smartTv('SMART_TV', 'Smart TV / Netflix', Icons.tv_rounded),
  workspace('WORKSPACE', 'Workspace', Icons.desk_outlined),
  washer('WASHING_MACHINE', 'Washing machine', Icons.local_laundry_service),
  pool('POOL', 'Pool', Icons.pool_rounded),
  gym('GYM', 'Gym', Icons.fitness_center_rounded),
  balcony('BALCONY', 'Balcony', Icons.balcony_outlined),
  gaming('GAMING', 'Games console', Icons.sports_esports_outlined),
  speaker('SOUND_SYSTEM', 'Sound system', Icons.speaker_outlined);

  final String wireValue;
  final String label;
  final IconData icon;

  const ShortLetAmenity(this.wireValue, this.label, this.icon);
}

/// What a stay is for. The host says what their place suits; guests browse
/// by the same list, so a "Birthdays" tile leads to places that welcome one.
enum ShortLetOccasion {
  staycation('STAYCATION', 'Staycation', Icons.holiday_village_outlined),
  birthday('BIRTHDAY', 'Birthdays', Icons.cake_outlined),
  baecation('BAECATION', 'Baecation', Icons.favorite_border_rounded),
  party('PARTY', 'Parties', Icons.celebration_outlined),
  weekend('WEEKEND_GETAWAY', 'Weekend getaway', Icons.weekend_outlined),
  workTrip('WORK_TRIP', 'Work trip', Icons.work_outline_rounded),
  family('FAMILY', 'Family time', Icons.family_restroom_rounded),
  friends('FRIENDS_TRIP', 'Friends’ trip', Icons.groups_outlined),
  photoshoot('PHOTOSHOOT', 'Photoshoots', Icons.photo_camera_outlined),
  wedding('WEDDING', 'Weddings & owambe', Icons.diversity_1_outlined),
  holiday('HOLIDAY', 'Holidays', Icons.beach_access_outlined),
  longStay('LONG_STAY', 'Long stays', Icons.calendar_month_outlined),
  stopover('STOPOVER', 'Airport stopover', Icons.flight_outlined);

  final String wireValue;
  final String label;
  final IconData icon;

  const ShortLetOccasion(this.wireValue, this.label, this.icon);
}

/// The listing questions the backend does not store yet (backend change
/// spec v18). Sent on every create and edit, and read back when present, so
/// they start working the moment the backend keeps them; until then a
/// server that ignores unknown keys loses them without failing the save.
@immutable
class ShortLetDetails {
  final ShortLetPlaceType? placeType;
  final Set<ShortLetAmenity> amenities;
  final Set<ShortLetOccasion> bestFor;

  /// 24-hour "HH:mm", local to the listing.
  final String checkInTime;
  final String checkOutTime;

  final bool smokingAllowed;
  final bool petsAllowed;
  final bool partiesAllowed;

  const ShortLetDetails({
    this.placeType,
    this.amenities = const {},
    this.bestFor = const {},
    this.checkInTime = '14:00',
    this.checkOutTime = '12:00',
    this.smokingAllowed = false,
    this.petsAllowed = false,
    this.partiesAllowed = false,
  });

  Map<String, dynamic> toJson() => {
    'property_type': ?placeType?.wireValue,
    'amenities': [for (final amenity in amenities) amenity.wireValue],
    'best_for': [for (final occasion in bestFor) occasion.wireValue],
    'check_in_time': checkInTime,
    'check_out_time': checkOutTime,
    'smoking_allowed': smokingAllowed,
    'pets_allowed': petsAllowed,
    'parties_allowed': partiesAllowed,
  };

  factory ShortLetDetails.fromJson(Map<String, dynamic> json) {
    Set<T> readSet<T extends Enum>(
      Object? raw,
      List<T> values,
      String Function(T) wire,
    ) {
      if (raw is! List) return const {};
      final wanted = raw.map((e) => e.toString().toUpperCase()).toSet();
      return {
        for (final value in values)
          if (wanted.contains(wire(value))) value,
      };
    }

    String readTime(Object? raw, String fallback) {
      final text = raw?.toString() ?? '';
      // The backend may send "14:00:00"; the app only shows hours and minutes.
      final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(text);
      if (match == null) return fallback;
      return '${match.group(1)!.padLeft(2, '0')}:${match.group(2)}';
    }

    return ShortLetDetails(
      placeType: ShortLetPlaceType.fromString(
        json['property_type']?.toString(),
      ),
      amenities: readSet(
        json['amenities'],
        ShortLetAmenity.values,
        (a) => a.wireValue,
      ),
      bestFor: readSet(
        json['best_for'],
        ShortLetOccasion.values,
        (o) => o.wireValue,
      ),
      checkInTime: readTime(json['check_in_time'], '14:00'),
      checkOutTime: readTime(json['check_out_time'], '12:00'),
      smokingAllowed: json['smoking_allowed'] == true,
      petsAllowed: json['pets_allowed'] == true,
      partiesAllowed: json['parties_allowed'] == true,
    );
  }

  ShortLetDetails copyWith({
    ShortLetPlaceType? placeType,
    Set<ShortLetAmenity>? amenities,
    Set<ShortLetOccasion>? bestFor,
    String? checkInTime,
    String? checkOutTime,
    bool? smokingAllowed,
    bool? petsAllowed,
    bool? partiesAllowed,
  }) => ShortLetDetails(
    placeType: placeType ?? this.placeType,
    amenities: amenities ?? this.amenities,
    bestFor: bestFor ?? this.bestFor,
    checkInTime: checkInTime ?? this.checkInTime,
    checkOutTime: checkOutTime ?? this.checkOutTime,
    smokingAllowed: smokingAllowed ?? this.smokingAllowed,
    petsAllowed: petsAllowed ?? this.petsAllowed,
    partiesAllowed: partiesAllowed ?? this.partiesAllowed,
  );
}
