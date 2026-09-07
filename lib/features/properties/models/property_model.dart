/// What a landlord is putting a property on Landa for.
///
/// Asked first, because almost everything after it differs. A yearly let is
/// a tenancy: it needs proof of ownership, a rent, and an agreement somebody
/// signs. A short let is a listing: it needs a nightly price, house rules and
/// a calendar, and the guest never signs anything. Collecting one form for
/// both meant every short-let host was asked for a deed they do not need and
/// every landlord was asked nothing about how they take rent.
///
/// Client-side only. The backend stores one kind of property and works out
/// the rest from whether the unit carries a short-let listing, so this never
/// goes over the wire: it only decides which questions get asked.
enum PropertyPurpose {
  yearlyRent,
  shortLet;

  bool get isShortLet => this == PropertyPurpose.shortLet;

  String get label => switch (this) {
    PropertyPurpose.yearlyRent => 'Yearly rent',
    PropertyPurpose.shortLet => 'Short lets',
  };

  String get blurb => switch (this) {
    PropertyPurpose.yearlyRent =>
      'Tenants apply, sign a tenancy agreement and pay rent into escrow.',
    PropertyPurpose.shortLet =>
      'Guests book by the night. You approve every stay before anyone pays.',
  };
}

/// The period a landlord is quoting a rent for.
///
/// The API stores one number (`rent_amount`, always the annual figure) but
/// Nigerian landlords do not all think in one. A serviced flat is quoted
/// monthly, a family house yearly, and a short let by the night. Making
/// everybody convert in their head before typing is how a ₦250,000 monthly
/// flat ends up listed at ₦250,000 a year.
enum RentInterval {
  perYear,
  perMonth,
  perNight;

  /// What one of these multiplies by to reach a year's rent.
  int get periodsPerYear => switch (this) {
    RentInterval.perYear => 1,
    RentInterval.perMonth => 12,
    RentInterval.perNight => 365,
  };

  /// The suffix shown beside the amount as it is typed.
  String get suffix => switch (this) {
    RentInterval.perYear => '/year',
    RentInterval.perMonth => '/month',
    RentInterval.perNight => '/night',
  };

  String get shortLabel => switch (this) {
    RentInterval.perYear => 'Year',
    RentInterval.perMonth => 'Month',
    RentInterval.perNight => 'Night',
  };

  /// The intervals offered for a property of this [purpose]. A yearly let is
  /// never quoted by the night, and offering it would only invite a rent
  /// three hundred times too large.
  static List<RentInterval> forPurpose(PropertyPurpose purpose) =>
      purpose.isShortLet
      ? const [
          RentInterval.perNight,
          RentInterval.perMonth,
          RentInterval.perYear,
        ]
      : const [RentInterval.perYear, RentInterval.perMonth];
}

class PropertyModel {
  final String id;
  final String name;
  final String address;
  final String city;
  final String state;
  final String createdAt;
  final double? latitude;
  final double? longitude;
  final List<String> photoUrls;

  /// Backend-chosen cover image (the first uploaded photo). Tenants see this
  /// while browsing the marketplace.
  final String? coverPhotoUrl;

  /// Optional property-tour video. One per property.
  final String? videoUrl;
  final String verificationStatus;

  /// How many listing photos the property has, as counted by the backend.
  /// Null on payloads that predate the field: [photoCount] falls back to the
  /// length of [photoUrls], which the list endpoints already return.
  final int? serverPhotoCount;

  /// The backend's own verdict on whether this listing is missing photos.
  /// Null before the field ships; [needsPhotos] then works it out locally.
  final bool? serverNeedsPhotos;

  PropertyModel({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.state,
    required this.createdAt,
    this.latitude,
    this.longitude,
    this.photoUrls = const [],
    this.coverPhotoUrl,
    this.videoUrl,
    this.verificationStatus = 'PENDING',
    this.serverPhotoCount,
    this.serverNeedsPhotos,
  });

  /// Image to lead with: the backend's cover choice, falling back to the
  /// first photo for payloads that predate `cover_photo_url`.
  String? get displayImageUrl {
    if (coverPhotoUrl != null && coverPhotoUrl!.isNotEmpty) {
      return coverPhotoUrl;
    }
    return photoUrls.isNotEmpty ? photoUrls.first : null;
  }

  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;

  int get photoCount => serverPhotoCount ?? photoUrls.length;

  /// True when the listing has no photos, which keeps it out of the tenant
  /// marketplace. Surfaced on the landlord's own property card so they can
  /// fix it: a listing hidden with no explanation is worse than no rule.
  bool get needsPhotos => serverNeedsPhotos ?? photoCount == 0;

  /// This property, with any media it is missing taken from [previous].
  ///
  /// Landa's endpoints do not all describe a property equally. `POST
  /// /properties/` answers with `photo_urls`, `cover_photo_url`,
  /// `photo_count`, `needs_photos` and `video_url`; `GET /properties/`, the
  /// list the landlord's portfolio is rebuilt from on every refresh, is
  /// documented with `photo_urls` and none of the rest (API guide 18 §5.11).
  ///
  /// So a landlord could add a property with four photos, see them, and then
  /// watch the card go blank the next time the list was re-read — which is
  /// what testers reported as "they can see the property but they cant see
  /// any picture in it". The thinner payload was overwriting the richer one.
  ///
  /// The rule here is one line: **a refresh may add media, and may never
  /// remove it.** A photo set that has genuinely been deleted comes back
  /// from `GET /properties/{id}/photos/`, which the media manager reads
  /// directly, so nothing here can keep a deleted photo on screen for long.
  ///
  /// `backend docs/backend_change_spec_v14.md` §5 asks for the list payload
  /// to carry what the create payload carries, which retires this.
  PropertyModel withMediaFrom(PropertyModel? previous) {
    if (previous == null) return this;
    final keptPhotos = photoUrls.isEmpty ? previous.photoUrls : photoUrls;
    return PropertyModel(
      id: id,
      name: name,
      address: address,
      city: city,
      state: state,
      createdAt: createdAt,
      latitude: latitude ?? previous.latitude,
      longitude: longitude ?? previous.longitude,
      photoUrls: keptPhotos,
      coverPhotoUrl: coverPhotoUrl ?? previous.coverPhotoUrl,
      videoUrl: videoUrl ?? previous.videoUrl,
      verificationStatus: verificationStatus,
      // The counts follow the photos they describe: keeping a server count of
      // 4 beside a kept set of 4 is consistent, and keeping a count of null
      // would make `needsPhotos` guess from a length it no longer owns.
      serverPhotoCount: serverPhotoCount ?? previous.serverPhotoCount,
      serverNeedsPhotos: serverNeedsPhotos ?? previous.serverNeedsPhotos,
    );
  }

  factory PropertyModel.fromJson(Map<String, dynamic> json) {
    return PropertyModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      city: json['city'] ?? '',
      state: json['state'] ?? '',
      createdAt: json['created_at'] ?? '',
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      photoUrls: _asStringList(json['photo_urls'] ?? json['images']),
      coverPhotoUrl: _asNonEmptyString(json['cover_photo_url']),
      videoUrl: _asNonEmptyString(json['video_url']),
      verificationStatus: json['verification_status']?.toString() ?? 'PENDING',
      serverPhotoCount: int.tryParse(json['photo_count']?.toString() ?? ''),
      serverNeedsPhotos: json['needs_photos'] is bool
          ? json['needs_photos'] as bool
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'city': city,
    'state': state,
    'created_at': createdAt,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    'photo_urls': photoUrls,
    if (coverPhotoUrl != null) 'cover_photo_url': coverPhotoUrl,
    if (videoUrl != null) 'video_url': videoUrl,
    'verification_status': verificationStatus,
    if (serverPhotoCount != null) 'photo_count': serverPhotoCount,
    if (serverNeedsPhotos != null) 'needs_photos': serverNeedsPhotos,
  };

  static String? _asNonEmptyString(dynamic value) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static double? _asDouble(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static List<String> _asStringList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) {
          if (item is Map) {
            return (item['url'] ?? item['image_url'] ?? '').toString();
          }
          return item.toString();
        })
        .where((url) => url.isNotEmpty)
        .toList();
  }
}

/// One uploaded listing photo, as returned by
/// `GET|POST /properties/{id}/photos/`.
class PropertyPhoto {
  final String id;
  final String imageUrl;
  final String createdAt;

  const PropertyPhoto({
    required this.id,
    required this.imageUrl,
    required this.createdAt,
  });

  factory PropertyPhoto.fromJson(Map<String, dynamic> json) => PropertyPhoto(
    id: json['id']?.toString() ?? '',
    imageUrl: (json['image_url'] ?? json['url'] ?? '').toString(),
    createdAt: json['created_at']?.toString() ?? '',
  );
}

/// Backend limits for listing media, mirrored client-side so the app can
/// reject oversized files before spending an upload round-trip.
class PropertyMediaLimits {
  /// Photos required before a property can be created.
  ///
  /// Two rather than one: a single image tells a tenant almost nothing, and a
  /// listing without photos is hidden from the marketplace entirely, so the
  /// floor may as well be a number that produces a usable listing.
  static const int minPhotos = 2;

  static const int maxPhotos = 10;
  static const int maxPhotoBytes = 5 * 1024 * 1024; // 5MB
  static const int maxVideoBytes = 50 * 1024 * 1024; // 50MB
  static const List<String> photoExtensions = ['jpg', 'jpeg', 'png', 'webp'];
  static const List<String> videoExtensions = ['mp4', 'mov'];

  /// Photos required on a *unit* before it can be let.
  ///
  /// Lower than [minPhotos] on the building, and for a different reason: the
  /// building shots establish the address, while these show the flat someone
  /// would actually live in. Two is the floor at which a tenant can tell a
  /// studio from a two-bedroom.
  static const int minUnitPhotos = 2;

  static const int maxUnitPhotos = 12;
}

class UnitModel {
  final String id;
  final String unitNumber;
  final int bedrooms;
  final int bathrooms;
  final String rentAmount;
  final bool isOccupied;
  final String? tenant;
  final String? tenantEmail;
  final String? tenantPhone;
  final String createdAt;
  final PropertyModel? property;

  /// Photos of this flat, as opposed to the building it is in.
  ///
  /// The pair used to be one set on the property, which meant every flat in a
  /// block advertised itself with the same picture of the gate. A tenant
  /// rents a unit, so the unit is what has to be photographed.
  final List<String> photoUrls;

  /// Backend-chosen cover for the unit, falling back to the first photo.
  final String? coverPhotoUrl;

  /// Walkthrough of this unit. Required when the unit is created: see
  /// [needsTourVideo] for why the app treats its absence as a fault to fix
  /// rather than a feature nobody used.
  final String? videoUrl;

  UnitModel({
    required this.id,
    required this.unitNumber,
    required this.bedrooms,
    required this.bathrooms,
    required this.rentAmount,
    required this.isOccupied,
    this.tenant,
    this.tenantEmail,
    this.tenantPhone,
    required this.createdAt,
    this.property,
    this.photoUrls = const [],
    this.coverPhotoUrl,
    this.videoUrl,
  });

  factory UnitModel.fromJson(Map<String, dynamic> json) {
    return UnitModel(
      id: json['id'] ?? '',
      unitNumber: json['unit_number'] ?? '',
      bedrooms: json['bedrooms'] is int
          ? json['bedrooms']
          : int.tryParse(json['bedrooms']?.toString() ?? '0') ?? 0,
      bathrooms: json['bathrooms'] is int
          ? json['bathrooms']
          : int.tryParse(json['bathrooms']?.toString() ?? '0') ?? 0,
      rentAmount: json['rent_amount']?.toString() ?? '0.00',
      isOccupied: json['is_occupied'] ?? false,
      tenant: _tenantName(json),
      tenantEmail: _tenantValue(json, 'email'),
      tenantPhone:
          _tenantValue(json, 'phone_number') ?? _tenantValue(json, 'phone'),
      createdAt: json['created_at'] ?? '',
      property:
          json['property'] != null && json['property'] is Map<String, dynamic>
          ? PropertyModel.fromJson(json['property'])
          : null,
      photoUrls: PropertyModel._asStringList(json['photo_urls']),
      coverPhotoUrl: PropertyModel._asNonEmptyString(json['cover_photo_url']),
      videoUrl: PropertyModel._asNonEmptyString(json['video_url']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'unit_number': unitNumber,
    'bedrooms': bedrooms,
    'bathrooms': bathrooms,
    'rent_amount': rentAmount,
    'is_occupied': isOccupied,
    'tenant': tenant,
    'created_at': createdAt,
    if (property != null) 'property': property!.toJson(),
    'photo_urls': photoUrls,
    if (coverPhotoUrl != null) 'cover_photo_url': coverPhotoUrl,
    if (videoUrl != null) 'video_url': videoUrl,
  };

  /// Image to lead with for this unit, falling back through the photo set.
  String? get displayImageUrl {
    if (coverPhotoUrl != null && coverPhotoUrl!.isNotEmpty) {
      return coverPhotoUrl;
    }
    return photoUrls.isNotEmpty ? photoUrls.first : null;
  }

  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;

  /// True when this unit has no walkthrough.
  ///
  /// Surfaced to the landlord rather than silently tolerated. Units created
  /// before the tour video was required still exist and are still let, so the
  /// app cannot pretend they are invalid, but it can tell the landlord which
  /// of their flats a tenant cannot see inside.
  bool get needsTourVideo => !hasVideo;

  bool get needsPhotos => photoUrls.length < PropertyMediaLimits.minUnitPhotos;

  /// The same rule as [PropertyModel.withMediaFrom], for a flat.
  ///
  /// Unit payloads vary more than property ones: the short-let listing
  /// carries `photo_urls`, `cover_photo_url` and `video_url` on its nested
  /// unit, while the marketplace's `available_units` carries only
  /// `photo_count` and `needs_photos`, and the batch-create response carries
  /// none of it. A refresh through any of those must not blank a flat whose
  /// walkthrough the landlord uploaded a minute ago.
  UnitModel withMediaFrom(UnitModel? previous) {
    if (previous == null) return this;
    return UnitModel(
      id: id,
      unitNumber: unitNumber,
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      rentAmount: rentAmount,
      isOccupied: isOccupied,
      tenant: tenant ?? previous.tenant,
      tenantEmail: tenantEmail ?? previous.tenantEmail,
      tenantPhone: tenantPhone ?? previous.tenantPhone,
      createdAt: createdAt,
      property: property ?? previous.property,
      photoUrls: photoUrls.isEmpty ? previous.photoUrls : photoUrls,
      coverPhotoUrl: coverPhotoUrl ?? previous.coverPhotoUrl,
      videoUrl: videoUrl ?? previous.videoUrl,
    );
  }

  static String? _tenantName(Map<String, dynamic> json) {
    final tenant = json['tenant'];
    if (tenant is Map) {
      final name =
          tenant['full_name'] ??
          tenant['name'] ??
          [
            tenant['first_name'],
            tenant['last_name'],
          ].whereType<String>().join(' ');
      return name?.toString().isNotEmpty == true ? name.toString() : null;
    }
    final explicitName = json['tenant_name'] ?? json['tenant_full_name'];
    if (explicitName != null && explicitName.toString().trim().isNotEmpty) {
      return explicitName.toString();
    }
    final value = tenant?.toString();
    // Older API responses return the tenant UUID in `tenant`. Never display
    // that identifier as a person's name while the backend is being updated.
    return _isUuid(value) ? null : value;
  }

  static String? _tenantValue(Map<String, dynamic> json, String key) {
    final tenant = json['tenant'];
    if (tenant is Map) return tenant[key]?.toString();
    return json['tenant_$key']?.toString();
  }

  static bool _isUuid(String? value) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value ?? '');
}
