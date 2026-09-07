import 'package:flutter/foundation.dart';

import '../../../core/network/load_failure.dart';
import '../../../core/session/session_scope.dart';
import '../models/review_models.dart';
import '../services/review_service.dart';

/// Holds reviews and rating aggregates, keyed by subject.
///
/// Keyed rather than "the reviews currently on screen", because several
/// subjects are visible at once on a browse list and each card wants its own
/// number. A single current-subject field would have every card render
/// whichever one was fetched last.
///
/// Caches per-user data: what *this* user has written is part of what it
/// holds, so it is session-scoped and wiped on sign-out.
class ReviewController extends ChangeNotifier
    with LoadFailureState, LoadedOnceState
    implements SessionScopedController {
  final ReviewService _service;

  ReviewController({ReviewService? service})
    : _service = service ?? ReviewService();

  final Map<String, List<Review>> _reviews = {};
  final Map<String, RatingSummary> _summaries = {};

  /// Subjects with a fetch in flight, so a card can shimmer its own rating
  /// without the whole list going busy.
  final Set<String> _loading = {};

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  /// Reviews held for one subject, empty until they have been fetched.
  List<Review> reviewsFor(ReviewSubject subject, String subjectId) =>
      _reviews[_key(subject, subjectId)] ?? const [];

  /// The aggregate for one subject. Falls back to [RatingSummary.empty],
  /// which renders as "no reviews yet" rather than as a zero-star rating.
  RatingSummary summaryFor(ReviewSubject subject, String subjectId) =>
      _summaries[_key(subject, subjectId)] ?? RatingSummary.empty;

  bool isLoadingFor(ReviewSubject subject, String subjectId) =>
      _loading.contains(_key(subject, subjectId));

  @override
  void resetSessionState() {
    _reviews.clear();
    _summaries.clear();
    _loading.clear();
    _isSubmitting = false;
    resetLoadedState();
    clearFailure();
    notifyListeners();
  }

  /// Loads the reviews and the aggregate for one subject together.
  ///
  /// Both in one call because a review screen shows both, and issuing them
  /// separately made the stars and the sentences arrive a frame apart.
  Future<void> loadReviews(ReviewSubject subject, String subjectId) async {
    if (subjectId.isEmpty) return;
    final key = _key(subject, subjectId);
    _loading.add(key);
    clearFailure();
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.getReviews(subject: subject, subjectId: subjectId),
        _service.getSummary(subject: subject, subjectId: subjectId),
      ]);
      _reviews[key] = results[0] as List<Review>;
      _summaries[key] = results[1] as RatingSummary;
    } catch (e) {
      captureFailure(e);
    } finally {
      _loading.remove(key);
      markLoaded(key);
      notifyListeners();
    }
  }

  /// Writes a review. Returns true when the backend accepted it.
  ///
  /// The list and aggregate are refetched rather than patched: the average is
  /// the backend's to compute, and a locally recomputed one would disagree
  /// with the next screen that loads it.
  Future<bool> submitReview({
    required ReviewSubject subject,
    required String subjectId,
    required String transactionId,
    required int rating,
    String comment = '',
  }) async {
    _isSubmitting = true;
    clearFailure();
    notifyListeners();

    try {
      await _service.submitReview(
        subject: subject,
        subjectId: subjectId,
        transactionId: transactionId,
        rating: rating,
        comment: comment,
      );
      await loadReviews(subject, subjectId);
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Posts the reviewed party's public answer to a review.
  Future<bool> respondToReview({
    required String reviewId,
    required String response,
    required ReviewSubject subject,
    required String subjectId,
  }) async {
    _isSubmitting = true;
    clearFailure();
    notifyListeners();

    try {
      await _service.respondToReview(reviewId: reviewId, response: response);
      await loadReviews(subject, subjectId);
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  static String _key(ReviewSubject subject, String subjectId) =>
      '${subject.value}:$subjectId';
}
