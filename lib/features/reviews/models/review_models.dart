/// Models for ratings and written reviews.
///
/// One shape for every reviewable thing on Landa rather than a separate
/// feature per surface. A guest rating a stay, a tenant rating the artisan who
/// fixed their tap and a tenant rating the landlord they rented from are the
/// same act: a star count, a sentence, and proof that the person writing it
/// actually transacted. Splitting that into three modules would have produced
/// three star widgets that disagreed about half a star.
///
/// The proof is the important part and it is the backend's job: every review
/// carries the booking, job or agreement it came out of, and the backend
/// refuses one that names a transaction the author was not party to or that
/// has not finished. Nothing here can be written by someone who merely
/// browsed.
library;

/// What is being reviewed.
///
/// The value strings are the backend's `subject_type`, so they are sent as
/// written rather than being re-cased at the call site.
enum ReviewSubject {
  /// A short-let listing, reviewed by the guest who stayed in it.
  shortLet('SHORT_LET'),

  /// An artisan, reviewed by the tenant whose job they completed.
  artisan('ARTISAN'),

  /// A landlord, reviewed by a tenant with a tenancy under them.
  landlord('LANDLORD'),

  /// A tenant, reviewed by their landlord or a short-let host. Guests who
  /// leave a place as they found it are worth knowing about too.
  tenant('TENANT'),

  unknown('');

  final String value;
  const ReviewSubject(this.value);

  static ReviewSubject fromString(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'SHORT_LET':
      case 'SHORTLET':
      case 'LISTING':
        return ReviewSubject.shortLet;
      case 'ARTISAN':
        return ReviewSubject.artisan;
      case 'LANDLORD':
      case 'OWNER':
        return ReviewSubject.landlord;
      case 'TENANT':
        return ReviewSubject.tenant;
      default:
        return ReviewSubject.unknown;
    }
  }

  /// What to call the thing in a heading, e.g. "Reviews of this stay".
  String get noun {
    switch (this) {
      case ReviewSubject.shortLet:
        return 'this stay';
      case ReviewSubject.artisan:
        return 'this artisan';
      case ReviewSubject.landlord:
        return 'this landlord';
      case ReviewSubject.tenant:
        return 'this tenant';
      case ReviewSubject.unknown:
        return 'this';
    }
  }
}

/// One review, as returned by the review endpoints.
class Review {
  final String id;
  final ReviewSubject subject;
  final String subjectId;

  /// Whole stars, 1–5. Clamped on read: a rating outside that range is a
  /// backend bug, and rendering six stars would be a worse way to find out.
  final int rating;

  final String comment;

  /// Who wrote it, as the backend chose to show them. Never an email: a
  /// review is public, and the author did not agree to publish their address.
  final String authorName;
  final String authorRole;

  /// The host's or artisan's answer, when they have written one.
  final String response;
  final String? respondedAt;

  final String createdAt;

  const Review({
    required this.id,
    this.subject = ReviewSubject.unknown,
    this.subjectId = '',
    this.rating = 0,
    this.comment = '',
    this.authorName = '',
    this.authorRole = '',
    this.response = '',
    this.respondedAt,
    this.createdAt = '',
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    final raw = _readInt(json['rating']) ?? 0;
    return Review(
      id: json['id']?.toString() ?? '',
      subject: ReviewSubject.fromString(json['subject_type']?.toString()),
      subjectId: json['subject_id']?.toString() ?? '',
      rating: raw.clamp(0, 5),
      comment: json['comment']?.toString() ?? '',
      authorName: (json['author_name'] ?? json['reviewer_name'] ?? '')
          .toString(),
      authorRole: (json['author_role'] ?? json['reviewer_role'] ?? '')
          .toString(),
      response: json['response']?.toString() ?? '',
      respondedAt: json['responded_at']?.toString(),
      createdAt: json['created_at']?.toString() ?? '',
    );
  }

  /// Falls back to something addressable rather than an empty byline.
  String get displayAuthor =>
      authorName.trim().isEmpty ? 'A Landa user' : authorName.trim();

  String get initial => displayAuthor[0].toUpperCase();

  bool get hasResponse => response.trim().isNotEmpty;
}

/// The aggregate for one subject: the number under the stars.
///
/// Separate from the list because it is what most screens actually need: a
/// listing card wants "4.8 (12)" and nothing else, and fetching a page of
/// reviews to compute it would be a request per card.
class RatingSummary {
  /// Mean rating, or null when nobody has reviewed yet.
  ///
  /// Null rather than 0.0 throughout: a new listing is unrated, not badly
  /// rated, and the difference is the whole point of the field.
  final double? average;

  final int count;

  /// How many reviews gave each star count, keyed 1–5. Empty when the backend
  /// did not break it down; the bars are then simply not drawn.
  final Map<int, int> distribution;

  const RatingSummary({
    this.average,
    this.count = 0,
    this.distribution = const {},
  });

  static const RatingSummary empty = RatingSummary();

  factory RatingSummary.fromJson(Map<String, dynamic> json) {
    final rawDistribution = json['distribution'];
    final distribution = <int, int>{};
    if (rawDistribution is Map) {
      for (final entry in rawDistribution.entries) {
        final star = _readInt(entry.key);
        final tally = _readInt(entry.value);
        if (star != null && tally != null && star >= 1 && star <= 5) {
          distribution[star] = tally;
        }
      }
    }
    return RatingSummary(
      average: _readDouble(json['average_rating'] ?? json['average']),
      count: _readInt(json['review_count'] ?? json['count']) ?? 0,
      distribution: distribution,
    );
  }

  bool get hasRating => average != null && count > 0;

  /// "4.8": one decimal, which is all the precision a star rating earns.
  String get label => hasRating ? average!.toStringAsFixed(1) : '-';

  /// "4.8 · 12 reviews", or an invitation when there are none.
  String get summaryLine => hasRating
      ? '$label · $count ${count == 1 ? 'review' : 'reviews'}'
      : 'No reviews yet';
}

int? _readInt(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _readDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
