/// Models for Fix: the artisan directory.
///
/// Fix used to be a marketplace: a tenant raised a request, an artisan
/// accepted and quoted it, the tenant paid into escrow, and confirming the
/// work released the money. API guide 18 removed every endpoint behind that
/// (§7B), and the models that described it (`FixJob`, `FixJobStatus`,
/// `FixUrgency`) went with them. Landa does not broker repairs any more.
///
/// What is left describes people rather than work: a trade, an artisan, and
/// the artisan a landlord vouches for on a unit. The repair itself is
/// arranged on the phone.
///
/// Everything here is read defensively. The guide documents these responses
/// loosely, and a field the app cannot parse should cost it a blank line,
/// not a screen.
library;

/// A trade an artisan works in.
///
/// Carried as a value/label pair rather than an enum because the backend owns
/// the list and serves it from `GET /artisans/categories/`. [defaults] mirrors
/// the four categories the API ships with today, for the one place that needs
/// them before there is a token to fetch with: the sign-up form.
class ArtisanCategory {
  final String value;
  final String label;

  const ArtisanCategory({required this.value, required this.label});

  factory ArtisanCategory.fromJson(Map<String, dynamic> json) {
    final value = (json['value'] ?? json['id'] ?? '').toString();
    final label = (json['label'] ?? json['name'] ?? '').toString();
    return ArtisanCategory(
      value: value,
      // A category with no label still has to render as something a person
      // can read, so fall back to prettifying the wire value.
      label: label.isNotEmpty ? label : prettify(value),
    );
  }

  /// The categories the API currently serves. Used only where the live list
  /// cannot be fetched: registration happens before sign-in, and the
  /// categories endpoint needs a verified token.
  static const List<ArtisanCategory> defaults = [
    ArtisanCategory(value: 'PLUMBING', label: 'Plumbing'),
    ArtisanCategory(value: 'ELECTRICIAN', label: 'Electrician'),
    ArtisanCategory(value: 'GENERATOR_REPAIR', label: 'Generator Repair'),
    ArtisanCategory(value: 'CLEANER', label: 'Cleaner'),
  ];

  /// `GENERATOR_REPAIR` -> `Generator Repair`. For a category the backend
  /// added after this build shipped.
  static String prettify(String value) {
    if (value.isEmpty) return 'Other';
    return value
        .split(RegExp(r'[_\s]+'))
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  /// A readable label for [value] using [known] where possible, prettified
  /// where not.
  static String labelFor(String value, List<ArtisanCategory> known) {
    for (final category in known) {
      if (category.value == value) return category.label;
    }
    return prettify(value);
  }

  @override
  bool operator ==(Object other) =>
      other is ArtisanCategory && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// An artisan, as a tenant or landlord sees them.
///
/// [phone] is the whole point of the directory. It used to be withheld until
/// an artisan accepted a job: most of the vanished Fix workflow existed to
/// gate it, and API guide 18 makes it always present. It is still read
/// defensively, because a profile with no number is a profile nobody can
/// ring, and rendering an empty string as something to call is worse than
/// showing nothing.
class ArtisanProfile {
  /// The artisan *profile* id: what the request and recommendation endpoints
  /// are keyed on, not the user id.
  final String id;

  final String fullName;
  final String email;

  /// Released by the backend only once this artisan has accepted the tenant's
  /// job. Null every other time.
  final String? phone;

  final String category;
  final String categoryLabel;
  final String location;
  final String bio;
  final int yearsOfExperience;

  /// `VERIFIED` and friends. Only verified, active artisans are meant to
  /// reach a tenant at all, so this is shown as reassurance rather than used
  /// as a filter the app enforces itself.
  final String verificationStatus;
  final bool isActive;

  /// Used the app within the last hour.
  final bool recentlyOnline;

  /// True when this artisan is the one the landlord named for the tenant's
  /// unit in this category. Only present when the list was filtered by a unit
  /// the tenant actually holds.
  final bool isRecommended;

  /// Mean rating out of 5 from tenants whose jobs this artisan completed, and
  /// how many rated them.
  ///
  /// Null rather than 0.0 when nobody has: an artisan new to Landa is
  /// unrated, and a zero-star badge would end their week before it started.
  final double? averageRating;
  final int reviewCount;

  const ArtisanProfile({
    required this.id,
    this.fullName = '',
    this.email = '',
    this.phone,
    this.category = '',
    this.categoryLabel = '',
    this.location = '',
    this.bio = '',
    this.yearsOfExperience = 0,
    this.verificationStatus = '',
    this.isActive = true,
    this.recentlyOnline = false,
    this.isRecommended = false,
    this.averageRating,
    this.reviewCount = 0,
  });

  factory ArtisanProfile.fromJson(Map<String, dynamic> json) {
    final category = (json['category'] ?? '').toString();
    final label = (json['category_label'] ?? '').toString();

    return ArtisanProfile(
      id: (json['id'] ?? json['artisan_id'] ?? '').toString(),
      fullName:
          (json['full_name'] ?? json['name'] ?? json['artisan_name'] ?? '')
              .toString(),
      email: (json['email'] ?? '').toString(),
      // Empty-string phone is the same as no phone. It should never happen
      // now that the number is always served, but a card whose only action is
      // "call" must not offer to dial "".
      phone: _nonEmpty(json['phone'] ?? json['phone_number']),
      category: category,
      categoryLabel: label.isNotEmpty
          ? label
          : ArtisanCategory.prettify(category),
      location: (json['location'] ?? '').toString(),
      bio: (json['bio'] ?? '').toString(),
      yearsOfExperience: _readInt(json['years_of_experience']) ?? 0,
      verificationStatus: (json['verification_status'] ?? '').toString(),
      // Absent means active: an artisan the backend served without the flag
      // is one it is serving.
      isActive: json['is_active'] is bool ? json['is_active'] as bool : true,
      recentlyOnline: json['recently_online'] == true,
      isRecommended: json['is_recommended'] == true,
      averageRating: _readDouble(json['average_rating']),
      reviewCount: _readInt(json['review_count']) ?? 0,
    );
  }

  /// What to call this artisan. Falls back through what is present rather
  /// than rendering a blank name.
  String get displayName {
    if (fullName.trim().isNotEmpty) return fullName.trim();
    if (email.contains('@')) return email.split('@').first;
    return 'Artisan';
  }

  bool get isVerified => verificationStatus.toUpperCase() == 'VERIFIED';

  /// Whether there is a rating worth showing.
  ///
  /// Nothing populates this today: API guide 18 states reviews are
  /// implemented for `SHORT_LET` only, and artisan ratings went with the job
  /// workflow they were earned through. Parsed anyway, so the day the
  /// backend serves them the cards show them without an app change.
  bool get hasRating => averageRating != null && reviewCount > 0;

  /// "4.8": one decimal, the same precision stays use.
  String? get ratingLabel =>
      hasRating ? averageRating!.toStringAsFixed(1) : null;

  /// Whether this artisan should be shown as reachable.
  ///
  /// The backend only serves verified, active artisans, so this is belt and
  /// braces rather than a filter the app depends on. It used to gate the
  /// "Request" button; there is no request any more, so what it gates now is
  /// whether the card offers a call.
  bool get canBeContacted => isVerified && isActive;

  /// "5 years · Lekki Phase 1", skipping whichever half is missing.
  String get credentials {
    final parts = <String>[
      if (yearsOfExperience > 0)
        '$yearsOfExperience ${yearsOfExperience == 1 ? 'year' : 'years'}',
      if (location.trim().isNotEmpty) location.trim(),
    ];
    return parts.join(' · ');
  }
}

/// One landlord-set recommendation on a unit: the artisan they trust for a
/// given category.
class ArtisanRecommendation {
  final String category;
  final String categoryLabel;

  /// The recommended artisan. Null when the backend returned only an id and
  /// no profile with it: the row is still meaningful (the category has a
  /// recommendation) even if there is no name to render yet.
  final ArtisanProfile? artisan;

  /// The artisan profile id, whether or not the profile itself came with it.
  final String artisanId;

  const ArtisanRecommendation({
    required this.category,
    required this.categoryLabel,
    required this.artisanId,
    this.artisan,
  });

  factory ArtisanRecommendation.fromJson(Map<String, dynamic> json) {
    // The artisan may arrive nested or as a bare id, depending on whether
    // this came back from the list or from the create call.
    final raw = json['artisan'] ?? json['artisan_profile'];
    final profile = raw is Map<String, dynamic>
        ? ArtisanProfile.fromJson(raw)
        : null;
    final category = (json['category'] ?? profile?.category ?? '').toString();
    final label = (json['category_label'] ?? '').toString();

    return ArtisanRecommendation(
      category: category,
      categoryLabel: label.isNotEmpty
          ? label
          : (profile?.categoryLabel ?? ArtisanCategory.prettify(category)),
      artisanId:
          profile?.id ??
          (json['artisan_id'] ?? (raw is Map ? null : raw) ?? '').toString(),
      artisan: profile,
    );
  }
}

/// The number in [value], or null when there is not one.
///
/// Tolerates the two shapes the backend uses interchangeably for counts: a
/// JSON number and a string holding one.
int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _readDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

/// [value] as a trimmed string, or null when it is absent or blank.
String? _nonEmpty(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
