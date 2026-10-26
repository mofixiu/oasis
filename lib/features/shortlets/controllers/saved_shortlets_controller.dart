import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/session/session_scope.dart';
import '../models/shortlet_models.dart';
import '../services/saved_shortlets_service.dart';

/// The shortlets a guest has hearted.
///
/// The server is the source of truth (spec v16 §1, live in API guide 20). A
/// copy is kept on this phone, per account, so hearts show before the list
/// arrives and survive being offline. If a server ever answers the list with
/// 404, saving carries on locally instead of failing.
class SavedShortLetsController extends ChangeNotifier
    implements SessionScopedController {
  final SavedShortLetsService _service;

  SavedShortLetsController({SavedShortLetsService? service})
    : _service = service ?? SavedShortLetsService();

  static const _prefsPrefix = 'v2_saved_shortlets_';

  /// Saved ids, most recent first.
  final List<String> _ids = [];

  /// Listings the server returned, or that were saved from a card, so the
  /// Saved screen can show them even when they are not in the browse list.
  final Map<String, ShortLetListing> _known = {};

  String? _userId;
  bool _serverSupportsSaving = true;
  bool _hasLoaded = false;

  bool get hasLoaded => _hasLoaded;
  int get count => _ids.length;
  bool isSaved(String listingId) => _ids.contains(listingId);

  /// False only against a server without the saved-shortlets endpoints.
  bool get isSyncedToServer => _serverSupportsSaving;

  /// The saved shortlets, resolved against [browse] for anything the server
  /// did not send. Ids that cannot be resolved are skipped rather than shown
  /// as empty cards.
  List<ShortLetListing> savedListings(List<ShortLetListing> browse) {
    final byId = {for (final listing in browse) listing.id: listing};
    return [
      for (final id in _ids)
        if (_known[id] ?? byId[id] case final listing?) listing,
    ];
  }

  Future<void> load(String userId) async {
    if (_userId != userId) {
      _userId = userId;
      _ids.clear();
      _known.clear();
    }
    await _readLocal();
    try {
      final saved = await _service.getSaved();
      _serverSupportsSaving = true;
      _ids
        ..clear()
        ..addAll(saved.map((listing) => listing.id));
      _known
        ..clear()
        ..addEntries(saved.map((listing) => MapEntry(listing.id, listing)));
      await _writeLocal();
    } on ApiException catch (e) {
      if (e.statusCode == 404) _serverSupportsSaving = false;
    } catch (_) {
      // Offline: the local copy stands in.
    }
    _hasLoaded = true;
    notifyListeners();
  }

  /// Saves or unsaves [listing]. Returns false when the server refused, in
  /// which case the heart has already flipped back.
  Future<bool> toggle(ShortLetListing listing) async {
    final wasSaved = isSaved(listing.id);
    _apply(listing, save: !wasSaved);
    await _writeLocal();
    if (!_serverSupportsSaving) return true;

    try {
      if (wasSaved) {
        await _service.unsave(listing.id);
      } else {
        await _service.save(listing.id);
      }
      return true;
    } on ApiException catch (e) {
      // Unsaving something already gone is the outcome that was wanted.
      if (wasSaved && e.statusCode == 404) return true;
      _apply(listing, save: wasSaved);
      await _writeLocal();
      return false;
    } catch (_) {
      _apply(listing, save: wasSaved);
      await _writeLocal();
      return false;
    }
  }

  void _apply(ShortLetListing listing, {required bool save}) {
    _ids.remove(listing.id);
    if (save) {
      _ids.insert(0, listing.id);
      _known[listing.id] = listing;
    }
    notifyListeners();
  }

  Future<void> _readLocal() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('$_prefsPrefix$userId') ?? const [];
      for (final id in stored) {
        if (!_ids.contains(id)) _ids.add(id);
      }
    } catch (_) {}
  }

  Future<void> _writeLocal() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('$_prefsPrefix$userId', List.of(_ids));
    } catch (_) {}
  }

  @override
  void resetSessionState() {
    _ids.clear();
    _known.clear();
    _userId = null;
    _hasLoaded = false;
    _serverSupportsSaving = true;
    notifyListeners();
  }
}
