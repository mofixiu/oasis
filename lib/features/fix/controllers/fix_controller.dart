import 'package:flutter/foundation.dart';

import '../../../core/network/load_failure.dart';
import '../../../core/session/session_scope.dart';
import '../models/fix_models.dart';
import '../services/fix_service.dart';

/// Holds Fix state for whichever role is signed in.
///
/// Fix was a marketplace and is now a directory (API guide 18 §7B), so most
/// of what this controller used to hold (a tenant's jobs, an artisan's
/// queue, quotes, payments, escrow) is gone with the endpoints behind it.
///
/// Three roles still read it, and they read different things:
///
/// * a **tenant** browses artisans in a trade, with their landlord's
///   recommendation first;
/// * a **landlord** browses the same directory from their own route, to name
///   who they trust on a unit;
/// * an **artisan** reads and edits their own profile, which is now the whole
///   of their app.
///
/// Still caches per-user data, so it must be wiped between sessions: an
/// artisan's phone number and a landlord's recommendations both belong to
/// whoever was signed in.
class FixController extends ChangeNotifier
    with LoadFailureState, LoadedOnceState
    implements SessionScopedController {
  /// Keys for [LoadedOnceState]: the directory a tenant or landlord browses,
  /// and the signed-in artisan's own profile.
  static const String kArtisansKey = 'artisans';
  static const String kMyProfileKey = 'my-artisan-profile';

  final FixService _service;

  FixController({FixService? service}) : _service = service ?? FixService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// True while a profile edit or a recommendation is in flight, so a second
  /// tap cannot start a second one.
  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  List<ArtisanCategory> _categories = ArtisanCategory.defaults;

  /// The trades on offer. Seeded with the four the API ships with so the
  /// category picker is never empty while the live list is in flight, and
  /// replaced the moment the backend answers.
  List<ArtisanCategory> get categories => _categories;

  String? _selectedCategory;

  /// Which trade the tenant is browsing. Null until the first category
  /// resolves: no category means no artisan list to fetch.
  String? get selectedCategory => _selectedCategory;

  List<ArtisanProfile> _artisans = [];

  /// Artisans in [selectedCategory], recommended one first.
  List<ArtisanProfile> get artisans => _artisans;

  String _artisanSearch = '';

  /// The typed area name narrowing the artisan list. Empty means no search.
  String get artisanSearch => _artisanSearch;
  bool get hasArtisanSearch => _artisanSearch.isNotEmpty;

  /// The artisan the landlord named for this unit and category, when the
  /// browse was scoped to a unit the tenant holds.
  ArtisanProfile? get recommendedArtisan {
    for (final artisan in _artisans) {
      if (artisan.isRecommended) return artisan;
    }
    return null;
  }

  ArtisanProfile? _myProfile;

  /// The signed-in artisan's own profile. Null for every other role.
  ArtisanProfile? get myProfile => _myProfile;

  @override
  void resetSessionState() {
    _categories = ArtisanCategory.defaults;
    _selectedCategory = null;
    _artisans = [];
    _artisanSearch = '';
    _myProfile = null;
    _isLoading = false;
    _isSubmitting = false;
    resetLoadedState();
    clearFailure();
    notifyListeners();
  }

  // ------------------------------------------------------------------ shared

  /// Loads the live category list, keeping the seeded defaults if the call
  /// fails: an empty picker would make Fix look broken over one failed GET.
  Future<void> loadCategories() async {
    try {
      final categories = await _service.getCategories();
      if (categories.isNotEmpty) _categories = categories;
    } catch (e) {
      debugPrint('[FIX] Category load failed, keeping defaults: $e');
    }
    _selectedCategory ??= _categories.isEmpty ? null : _categories.first.value;
    notifyListeners();
  }

  // ------------------------------------------------------------------ tenant

  /// Switches the trade being browsed and refetches, when it actually
  /// changed.
  Future<void> selectCategory(String category, {String? unitId}) async {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    _artisans = [];
    notifyListeners();
    await loadArtisans(unitId: unitId);
  }

  /// Artisans in the selected category.
  ///
  /// [unitId] is what surfaces the landlord's recommendation, so the caller
  /// passes the tenant's own unit whenever they have one. The recommended
  /// artisan is sorted to the front here rather than in the widget: it is a
  /// property of the data, and every screen showing this list wants it.
  Future<void> loadArtisans({String? unitId}) async {
    final category = _selectedCategory;
    if (category == null || category.isEmpty) return;

    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      final artisans = await _service.browseArtisans(
        category: category,
        unitId: unitId,
        location: _artisanSearch,
      );
      _artisans = _sorted(artisans);
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      markLoaded(kArtisansKey);
      notifyListeners();
    }
  }

  /// Narrows the artisan list to a typed area. [query] arrives already
  /// debounced from the search field.
  Future<void> searchArtisans(String query, {String? unitId}) async {
    final trimmed = query.trim();
    if (trimmed == _artisanSearch) return;
    _artisanSearch = trimmed;
    await loadArtisans(unitId: unitId);
  }

  /// Drops the area search and reloads the full list for the trade.
  Future<void> clearArtisanSearch({String? unitId}) async {
    if (_artisanSearch.isEmpty) return;
    _artisanSearch = '';
    await loadArtisans(unitId: unitId);
  }

  /// The signed-in artisan's own profile.
  ///
  /// Failure is reported here, unlike most quiet loads, because this *is* the
  /// artisan's screen now: there is nothing else on it to fall back to, and
  /// an empty page with no explanation reads as the account being gone.
  Future<void> loadMyArtisanProfile() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();
    try {
      _myProfile = await _service.getMyArtisanProfile();
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      markLoaded(kMyProfileKey);
      notifyListeners();
    }
  }

  /// Edits the signed-in artisan's profile. Returns true when it saved.
  Future<bool> updateMyArtisanProfile({
    String? category,
    String? location,
    String? bio,
    int? yearsOfExperience,
  }) async {
    _isSubmitting = true;
    clearFailure();
    notifyListeners();

    try {
      _myProfile = await _service.updateMyArtisanProfile(
        category: category,
        location: location,
        bio: bio,
        yearsOfExperience: yearsOfExperience,
      );
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- landlord

  /// Recommendations already set on a unit. Returned rather than cached: a
  /// landlord edits these one unit at a time from a sheet, and a controller
  /// field would outlive the sheet and be shown against the next unit opened.
  Future<List<ArtisanRecommendation>?> loadUnitRecommendations(
    String unitId,
  ) async {
    clearFailure();
    try {
      return await _service.getUnitRecommendations(unitId);
    } catch (e) {
      captureFailure(e);
      notifyListeners();
      return null;
    }
  }

  /// The artisans a landlord can choose between for [category].
  ///
  /// [unitId] marks whoever is already recommended on that unit, so the
  /// picker can show the landlord their current choice rather than making
  /// them remember it.
  Future<List<ArtisanProfile>?> loadArtisanDirectory(
    String category, {
    String? unitId,
  }) async {
    clearFailure();
    try {
      return _sorted(
        await _service.browseArtisansForLandlord(
          category: category,
          unitId: unitId,
        ),
      );
    } catch (e) {
      captureFailure(e);
      notifyListeners();
      return null;
    }
  }

  /// Names an artisan for one category on a unit, replacing whoever was there.
  Future<bool> recommendArtisan({
    required String unitId,
    required String category,
    required String artisanId,
  }) async {
    _isSubmitting = true;
    clearFailure();
    notifyListeners();

    try {
      await _service.recommendArtisan(
        unitId: unitId,
        category: category,
        artisanId: artisanId,
      );
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Drops the recommendation for one category on a unit.
  Future<bool> removeRecommendation({
    required String unitId,
    required String category,
  }) async {
    _isSubmitting = true;
    clearFailure();
    notifyListeners();

    try {
      await _service.removeRecommendation(unitId: unitId, category: category);
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Recommended first, then whoever is online now, then everyone else.
  ///
  /// A landlord's recommendation is the strongest signal a tenant has about
  /// who to trust, and "used the app in the last hour" is the strongest signal
  /// about who will actually answer today.
  List<ArtisanProfile> _sorted(List<ArtisanProfile> artisans) {
    final sorted = [...artisans];
    sorted.sort((a, b) {
      if (a.isRecommended != b.isRecommended) return a.isRecommended ? -1 : 1;
      if (a.recentlyOnline != b.recentlyOnline) {
        return a.recentlyOnline ? -1 : 1;
      }
      return b.yearsOfExperience.compareTo(a.yearsOfExperience);
    });
    return sorted;
  }
}
