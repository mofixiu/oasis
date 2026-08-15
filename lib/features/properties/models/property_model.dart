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
  final String verificationStatus;

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
    this.verificationStatus = 'PENDING',
  });

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
      verificationStatus: json['verification_status']?.toString() ?? 'PENDING',
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
    'verification_status': verificationStatus,
  };

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
  };

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
