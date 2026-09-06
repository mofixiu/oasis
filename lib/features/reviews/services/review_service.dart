import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/review_models.dart';

/// Talks to the review endpoints.
///
/// One set of paths for every reviewable thing, with `subject_type` naming
/// which. A per-feature route (`/short-lets/{id}/reviews/`,
/// `/artisans/{id}/reviews/`) would have meant the same three methods written
/// three times and, in practice, three subtly different pagination shapes.
///
/// Reads degrade to "nothing yet" when the backend has not shipped reviews:
/// a 404 on a listing's reviews means an app running against an older
/// deployment shows an unrated listing rather than an error banner on a screen
/// whose actual job, booking a place, still works perfectly. Writes never
/// degrade: a review the user typed and believes they posted must not be
/// silently swallowed.
class ReviewService {
  final ApiClient _apiClient;

  ReviewService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// Reviews for one subject, newest first.
  Future<List<Review>> getReviews({
    required ReviewSubject subject,
    required String subjectId,
    int limit = 20,
  }) async {
    debugPrint(
      '[REVIEW SERVICE] Fetching reviews GET ${ApiConstants.reviewsEndpoint} '
      '(${subject.value} $subjectId)',
    );
    try {
      final response = await _apiClient.get(
        ApiConstants.reviewsEndpoint,
        queryParameters: {
          'subject_type': subject.value,
          'subject_id': subjectId,
          'limit': '$limit',
        },
      );
      final rows = response is Map<String, dynamic>
          ? response['results']
          : response;
      if (rows is List) {
        return rows
            .whereType<Map<String, dynamic>>()
            .map(Review.fromJson)
            .toList();
      }
      return const [];
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        debugPrint('ℹ [REVIEW SERVICE] Reviews not available on this backend');
        return const [];
      }
      rethrow;
    }
  }

  /// The aggregate for one subject.
  ///
  /// A separate call from [getReviews] because most screens want only this:
  /// a card shows "4.8 (12)" and never the sentences behind it.
  Future<RatingSummary> getSummary({
    required ReviewSubject subject,
    required String subjectId,
  }) async {
    try {
      final response = await _apiClient.get(
        ApiConstants.reviewSummaryEndpoint,
        queryParameters: {
          'subject_type': subject.value,
          'subject_id': subjectId,
        },
      );
      return response is Map<String, dynamic>
          ? RatingSummary.fromJson(response)
          : RatingSummary.empty;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return RatingSummary.empty;
      rethrow;
    }
  }

  /// Writes a review.
  ///
  /// [transactionId] is the booking, job or agreement it comes out of, and is
  /// what makes the review trustworthy: the backend checks that the author was
  /// party to it, that it has finished, and that they have not already
  /// reviewed it. Without it there is no difference between a guest who stayed
  /// and a rival down the road.
  Future<Review> submitReview({
    required ReviewSubject subject,
    required String subjectId,
    required String transactionId,
    required int rating,
    String comment = '',
  }) async {
    debugPrint(
      '[REVIEW SERVICE] Posting review POST ${ApiConstants.reviewsEndpoint} '
      '(${subject.value} $subjectId, $rating)',
    );
    final response = await _apiClient.post(
      ApiConstants.reviewsEndpoint,
      body: {
        'subject_type': subject.value,
        'subject_id': subjectId,
        'transaction_id': transactionId,
        'rating': rating,
        if (comment.trim().isNotEmpty) 'comment': comment.trim(),
      },
    );
    return Review.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }

  /// The reviewed party's public answer to one review.
  Future<Review> respondToReview({
    required String reviewId,
    required String response,
  }) async {
    final endpoint = ApiConstants.reviewResponseEndpoint(reviewId);
    debugPrint('[REVIEW SERVICE] Responding to $reviewId POST $endpoint');
    final result = await _apiClient.post(
      endpoint,
      body: {'response': response.trim()},
    );
    return Review.fromJson(result is Map<String, dynamic> ? result : const {});
  }
}
