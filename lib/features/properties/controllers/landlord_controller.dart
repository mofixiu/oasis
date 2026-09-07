import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/load_failure.dart';
import '../../../core/session/session_scope.dart';
import '../models/property_model.dart';
import '../services/property_service.dart';

class LandlordController extends ChangeNotifier
    with LoadFailureState, LoadedOnceState
    implements SessionScopedController {
  /// Key for [LoadedOnceState].
  static const String kPropertiesKey = 'properties';

  /// Key for one property's listing media, per property.
  ///
  /// Keyed rather than shared because the media manager on a property's own
  /// page has to distinguish "this property's photos have not been fetched"
  /// from "some other property's have", and rendering "no listing photos
  /// yet" over a property with four of them, for the second it takes the
  /// fetch to come back, is exactly the bug this exists to prevent.
  static String propertyMediaKey(String propertyId) => 'media:$propertyId';

  final PropertyService _propertyService;

  LandlordController({PropertyService? propertyService})
    : _propertyService = propertyService ?? PropertyService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<PropertyModel> _properties = [];
  List<PropertyModel> get properties => _properties;

  final Map<String, List<UnitModel>> _propertyUnits = {};
  Map<String, List<UnitModel>> get propertyUnits => _propertyUnits;

  UnitModel? _tenantAssignedUnit;
  UnitModel? get tenantAssignedUnit => _tenantAssignedUnit;

  // Listing media, keyed by property id.
  final Map<String, List<PropertyPhoto>> _propertyPhotos = {};
  Map<String, List<PropertyPhoto>> get propertyPhotos => _propertyPhotos;

  final Map<String, String?> _propertyVideos = {};
  String? videoUrlFor(String propertyId) => _propertyVideos[propertyId];

  // Unit media, keyed by unit id. Separate maps from the property ones
  // because they answer a different question: what the flat looks like, not
  // what the building does, and a unit id and a property id are never
  // interchangeable even though both are UUIDs.
  final Map<String, List<PropertyPhoto>> _unitPhotos = {};
  Map<String, List<PropertyPhoto>> get unitPhotos => _unitPhotos;

  final Map<String, String?> _unitVideos = {};
  String? unitVideoUrlFor(String unitId) => _unitVideos[unitId];

  /// Separate from [isLoading] so a media upload doesn't blank the whole
  /// property screen behind a spinner.
  bool _isMediaBusy = false;
  bool get isMediaBusy => _isMediaBusy;

  /// True while a unit's rent is being saved. Its own flag, and not
  /// [isMediaBusy]: a rent change is a one-field save that should leave the
  /// media controls on the same screen usable, and putting the two on one
  /// flag would grey out half a page for the other's sake.
  bool _isSavingUnit = false;
  bool get isSavingUnit => _isSavingUnit;

  /// Load properties for landlord
  Future<void> loadLandlordProperties() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      final fetched = await _propertyService.getProperties();
      // Merged, not replaced. `GET /properties/` describes a property more
      // thinly than `POST /properties/` does — no `cover_photo_url`, no
      // counts — so a refresh landing over a freshly created property used
      // to blank its photos on the card. See [PropertyModel.withMediaFrom].
      _properties = [
        for (final prop in fetched) prop.withMediaFrom(_propertyById(prop.id)),
      ];
      for (var prop in _properties) {
        final units = await _propertyService.getUnits(prop.id);
        _propertyUnits[prop.id] = _mergeUnits(prop.id, units);
      }
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      markLoaded(kPropertiesKey);
      notifyListeners();
    }
  }

  /// The copy already held for [propertyId], or null when this is the first
  /// time we have seen it.
  PropertyModel? _propertyById(String propertyId) {
    for (final prop in _properties) {
      if (prop.id == propertyId) return prop;
    }
    return null;
  }

  /// Fresh units for a property, each keeping any media the new payload does
  /// not carry. Same reasoning as [PropertyModel.withMediaFrom].
  List<UnitModel> _mergeUnits(String propertyId, List<UnitModel> fetched) {
    final known = _propertyUnits[propertyId];
    if (known == null || known.isEmpty) return fetched;
    final byId = {for (final unit in known) unit.id: unit};
    return [for (final unit in fetched) unit.withMediaFrom(byId[unit.id])];
  }

  @override
  void resetSessionState() {
    _removalBlockers = const [];
    _isRemoving = false;
    _properties = [];
    _propertyUnits.clear();
    _propertyPhotos.clear();
    _propertyVideos.clear();
    _unitPhotos.clear();
    _unitVideos.clear();
    _tenantAssignedUnit = null;
    resetLoadedState();
    clearFailure();
    _isLoading = false;
    _isMediaBusy = false;
    _isSavingUnit = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------- pricing

  /// Changes what a unit costs, and returns whether it saved.
  ///
  /// [rentAmount] is a year's rent as a decimal string. The caller converts
  /// a monthly quote before calling, because the backend stores one number.
  ///
  /// The unit is patched in place *and* the property is refetched. Patching
  /// alone would leave the property row's own derived figures, what the
  /// marketplace card shows, what the portfolio totals say: quoting the old
  /// price, which is the version a landlord is most likely to go and check.
  Future<bool> updateUnitRent({
    required String propertyId,
    required String unitId,
    required String rentAmount,
  }) async {
    _isSavingUnit = true;
    clearFailure();
    notifyListeners();

    try {
      final updated = await _propertyService.updateUnitRent(
        unitId: unitId,
        rentAmount: rentAmount,
      );
      final units = _propertyUnits[propertyId];
      if (units != null) {
        final index = units.indexWhere((unit) => unit.id == unitId);
        // Only when the response actually came back as a unit. A backend that
        // answers a PATCH with an empty body or a bare `{"detail": "ok"}`
        // would otherwise blank the row it just saved.
        if (index != -1 && updated.id.isNotEmpty) units[index] = updated;
      }
      await refreshPropertyDetail(propertyId);
      return true;
    } catch (e) {
      if (_rejectedAsUnsupported(e)) {
        setFailureMessage(_rentEditingUnavailable);
      } else {
        captureFailure(e);
      }
      return false;
    } finally {
      _isSavingUnit = false;
      notifyListeners();
    }
  }

  /// Whether the backend has no `PATCH /units/{id}/` route at all.
  ///
  /// Django answers a missing route with `404 {"detail": "Not found."}` and a
  /// route that exists but refuses the verb with
  /// `405 {"detail": "Method \"PATCH\" not allowed."}`. Shown as written,
  /// both read to a landlord as their flat having vanished, so they are
  /// caught here and replaced with what is actually true.
  ///
  /// Deliberately narrow: any other rejection is the backend having an
  /// opinion about the rent, and that opinion is worth showing as sent. This
  /// path deletes itself the day the endpoint ships: see
  /// `backend_change_spec_v12.md` §1.
  bool _rejectedAsUnsupported(Object error) =>
      error is ApiException &&
      (error.statusCode == 404 || error.statusCode == 405);

  static const String _rentEditingUnavailable =
      'This server cannot change a rent yet. Your unit is unchanged, nothing '
      'was lost. Try again once the update has shipped.';

  // -------------------------------------------------------- listing media

  /// Loads photos and video for one property.
  Future<void> loadPropertyMedia(String propertyId) async {
    _isMediaBusy = true;
    clearFailure();
    notifyListeners();
    try {
      final results = await Future.wait([
        _propertyService.getPropertyPhotos(propertyId),
        _propertyService.getPropertyVideo(propertyId),
      ]);
      _propertyPhotos[propertyId] = results[0] as List<PropertyPhoto>;
      _propertyVideos[propertyId] = results[1] as String?;
    } catch (e) {
      captureFailure(e);
    } finally {
      _isMediaBusy = false;
      // In the `finally`, so a failed fetch also counts as answered: the
      // manager then shows the empty state it can act on rather than a
      // skeleton that shimmers for ever.
      markLoaded(propertyMediaKey(propertyId));
      notifyListeners();
    }
  }

  /// Uploads listing photos. Returns false with [errorMessage] set on failure.
  Future<bool> uploadPropertyPhotos({
    required String propertyId,
    required List<File> photos,
  }) async {
    if (photos.isEmpty) return false;
    _isMediaBusy = true;
    clearFailure();
    notifyListeners();
    try {
      final created = await _propertyService.uploadPropertyPhotos(
        propertyId: propertyId,
        photos: photos,
      );
      _propertyPhotos[propertyId] = [
        ...(_propertyPhotos[propertyId] ?? const []),
        ...created,
      ];
      // The cover is derived from the photo set, so the property row is stale.
      await refreshPropertyDetail(propertyId);
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isMediaBusy = false;
      notifyListeners();
    }
  }

  Future<bool> deletePropertyPhoto({
    required String propertyId,
    required String photoId,
  }) async {
    _isMediaBusy = true;
    clearFailure();
    notifyListeners();
    try {
      await _propertyService.deletePropertyPhoto(
        propertyId: propertyId,
        photoId: photoId,
      );
      _propertyPhotos[propertyId] = (_propertyPhotos[propertyId] ?? const [])
          .where((photo) => photo.id != photoId)
          .toList();
      // Deleting the first photo promotes a new cover server-side.
      await refreshPropertyDetail(propertyId);
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isMediaBusy = false;
      notifyListeners();
    }
  }

  Future<bool> uploadPropertyVideo({
    required String propertyId,
    required File video,
  }) async {
    _isMediaBusy = true;
    clearFailure();
    notifyListeners();
    try {
      _propertyVideos[propertyId] = await _propertyService.uploadPropertyVideo(
        propertyId: propertyId,
        video: video,
      );
      await refreshPropertyDetail(propertyId);
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isMediaBusy = false;
      notifyListeners();
    }
  }

  Future<bool> deletePropertyVideo(String propertyId) async {
    _isMediaBusy = true;
    clearFailure();
    notifyListeners();
    try {
      await _propertyService.deletePropertyVideo(propertyId);
      _propertyVideos[propertyId] = null;
      await refreshPropertyDetail(propertyId);
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isMediaBusy = false;
      notifyListeners();
    }
  }

  /// Refresh a single property's detail (fields + units) from the backend.
  Future<void> refreshPropertyDetail(String propertyId) async {
    try {
      final detail = await _propertyService.getPropertyDetail(propertyId);
      final index = _properties.indexWhere((p) => p.id == propertyId);
      final merged = detail.property.withMediaFrom(_propertyById(propertyId));
      if (index != -1) {
        _properties[index] = merged;
      } else {
        _properties.insert(0, merged);
      }
      _propertyUnits[propertyId] = _mergeUnits(propertyId, detail.units);
      notifyListeners();
    } catch (e) {
      captureFailure(e);
      notifyListeners();
    }
  }

  // ---------------------------------------------------- removing a property

  /// Why the last removal attempt was refused, per unit. Empty when the last
  /// attempt was not refused for that reason.
  List<PropertyRemovalBlocker> _removalBlockers = const [];
  List<PropertyRemovalBlocker> get removalBlockers => _removalBlockers;

  bool _isRemoving = false;
  bool get isRemoving => _isRemoving;

  /// Asks to remove a property. Returns the request when the backend
  /// accepted it, and null otherwise — with either [removalBlockers] filled
  /// in (something on the property is still live) or [errorMessage] set.
  Future<PropertyRemovalRequest?> requestPropertyRemoval({
    required String propertyId,
    required String reason,
  }) => _removalCall(
    () => _propertyService.requestRemoval(
      propertyId: propertyId,
      reason: reason,
    ),
  );

  /// Confirms a removal with the account password, starting the cooling-off
  /// window. The property is refetched afterwards so the countdown banner
  /// has an `archive_at` to render.
  Future<PropertyRemovalRequest?> confirmPropertyRemoval({
    required String propertyId,
    required String requestId,
    required String password,
  }) async {
    final request = await _removalCall(
      () => _propertyService.confirmRemoval(
        propertyId: propertyId,
        requestId: requestId,
        password: password,
      ),
    );
    if (request != null) await loadLandlordProperties();
    return request;
  }

  /// Calls off a removal. Returns whether it went through.
  Future<bool> cancelPropertyRemoval({
    required String propertyId,
    required String requestId,
  }) async {
    _isRemoving = true;
    _removalBlockers = const [];
    clearFailure();
    notifyListeners();
    try {
      await _propertyService.cancelRemoval(
        propertyId: propertyId,
        requestId: requestId,
      );
      await _propertyService
          .getPropertyDetail(propertyId)
          .then((detail) {
            final index = _properties.indexWhere((p) => p.id == propertyId);
            if (index != -1) _properties[index] = detail.property;
          })
          // The cancel itself succeeded; a failed refresh after it is not a
          // failed cancel. Same rule as the short-let save.
          .catchError((Object e) {
            debugPrint('[LANDLORD] Cancelled, but the refresh failed: $e');
          });
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isRemoving = false;
      notifyListeners();
    }
  }

  /// Shared plumbing for the two calls that can come back blocked.
  Future<PropertyRemovalRequest?> _removalCall(
    Future<PropertyRemovalRequest> Function() action,
  ) async {
    _isRemoving = true;
    _removalBlockers = const [];
    clearFailure();
    notifyListeners();
    try {
      return await action();
    } on PropertyRemovalBlocked catch (blocked) {
      // Not an error message: the sheet renders these per unit, and
      // flattening them into one sentence would lose which flat to deal with.
      _removalBlockers = blocked.blockers;
      return null;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isRemoving = false;
      notifyListeners();
    }
  }

  /// Create property
  Future<PropertyModel?> createProperty({
    required String name,
    required String address,
    required String city,
    required String state,
    required double latitude,
    required double longitude,
    required File verificationVideo,

    // Proof of ownership. Sent for a yearly let, and deliberately absent for
    // a short let: a guest books by the night and signs nothing, so there is
    // no tenancy for a deed to underwrite. See PropertyPurpose.
    File? deedFile,
    List<File> photos = const [],
  }) async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      final newProp = await _propertyService.createProperty(
        name: name,
        address: address,
        city: city,
        state: state,
        latitude: latitude,
        longitude: longitude,
        verificationVideo: verificationVideo,
        deedFile: deedFile,
        photos: photos,
      );
      _properties.insert(0, newProp);
      _propertyUnits[newProp.id] = [];
      return newProp;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create several units in one request and refresh the local property list.
  Future<List<UnitModel>?> createUnitsBatch({
    required String propertyId,
    required List<Map<String, dynamic>> units,
  }) async {
    _isLoading = true;
    clearFailure();
    notifyListeners();
    try {
      final created = await _propertyService.createUnitsBatch(
        propertyId: propertyId,
        units: units,
      );
      _propertyUnits[propertyId] = [
        ...created,
        ...(_propertyUnits[propertyId] ?? []),
      ];
      return created;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create unit under property
  Future<UnitModel?> createUnit({
    required String propertyId,
    required String unitNumber,
    required int bedrooms,
    required int bathrooms,
    required String rentAmount,
  }) async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      final newUnit = await _propertyService.createUnit(
        propertyId: propertyId,
        unitNumber: unitNumber,
        bedrooms: bedrooms,
        bathrooms: bathrooms,
        rentAmount: rentAmount,
      );
      final currentList = _propertyUnits[propertyId] ?? [];
      currentList.insert(0, newUnit);
      _propertyUnits[propertyId] = List.from(currentList);
      return newUnit;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ unit media

  /// Loads one unit's photos and tour video.
  Future<void> loadUnitMedia(String unitId) async {
    _isMediaBusy = true;
    clearFailure();
    notifyListeners();
    try {
      _unitPhotos[unitId] = await _propertyService.getUnitPhotos(unitId);
    } catch (e) {
      captureFailure(e);
    } finally {
      _isMediaBusy = false;
      notifyListeners();
    }
  }

  /// Uploads photos of one unit. Returns false with [errorMessage] set on
  /// failure.
  Future<bool> uploadUnitPhotos({
    required String unitId,
    required List<File> photos,
    String? propertyId,
  }) async {
    if (photos.isEmpty) return false;
    _isMediaBusy = true;
    clearFailure();
    notifyListeners();
    try {
      final created = await _propertyService.uploadUnitPhotos(
        unitId: unitId,
        photos: photos,
      );
      _unitPhotos[unitId] = [...(_unitPhotos[unitId] ?? const []), ...created];
      // The unit row carries its own cover, so the property detail is stale.
      if (propertyId != null) await refreshPropertyDetail(propertyId);
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isMediaBusy = false;
      notifyListeners();
    }
  }

  Future<bool> deleteUnitPhoto({
    required String unitId,
    required String photoId,
    String? propertyId,
  }) async {
    _isMediaBusy = true;
    clearFailure();
    notifyListeners();
    try {
      await _propertyService.deleteUnitPhoto(unitId: unitId, photoId: photoId);
      _unitPhotos[unitId] = (_unitPhotos[unitId] ?? const [])
          .where((photo) => photo.id != photoId)
          .toList();
      if (propertyId != null) await refreshPropertyDetail(propertyId);
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isMediaBusy = false;
      notifyListeners();
    }
  }

  /// Uploads or replaces a unit's tour video.
  Future<bool> uploadUnitVideo({
    required String unitId,
    required File video,
    String? propertyId,
  }) async {
    _isMediaBusy = true;
    clearFailure();
    notifyListeners();
    try {
      _unitVideos[unitId] = await _propertyService.uploadUnitVideo(
        unitId: unitId,
        video: video,
      );
      if (propertyId != null) await refreshPropertyDetail(propertyId);
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isMediaBusy = false;
      notifyListeners();
    }
  }

  Future<bool> deleteUnitVideo(String unitId, {String? propertyId}) async {
    _isMediaBusy = true;
    clearFailure();
    notifyListeners();
    try {
      await _propertyService.deleteUnitVideo(unitId);
      _unitVideos[unitId] = null;
      if (propertyId != null) await refreshPropertyDetail(propertyId);
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isMediaBusy = false;
      notifyListeners();
    }
  }

  /// Assign tenant to unit
  Future<bool> assignTenant({
    required String unitId,
    required String tenantId,
    required String propertyId,
  }) async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      final updatedUnit = await _propertyService.assignTenant(
        unitId: unitId,
        tenantId: tenantId,
      );
      final list = _propertyUnits[propertyId] ?? [];
      final index = list.indexWhere((u) => u.id == unitId);
      if (index != -1) {
        list[index] = updatedUnit;
        _propertyUnits[propertyId] = List.from(list);
      }
      return true;
    } catch (e) {
      captureFailure(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch tenant's assigned unit
  Future<void> loadTenantAssignedUnit() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      _tenantAssignedUnit = await _propertyService.getTenantAssignedUnit();
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
