import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../core/network/load_failure.dart';
import '../../../core/session/session_scope.dart';
import '../models/property_model.dart';
import '../services/property_service.dart';

class LandlordController extends ChangeNotifier
    with LoadFailureState
    implements SessionScopedController {
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

  /// Separate from [isLoading] so a media upload doesn't blank the whole
  /// property screen behind a spinner.
  bool _isMediaBusy = false;
  bool get isMediaBusy => _isMediaBusy;

  /// Load properties for landlord
  Future<void> loadLandlordProperties() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      _properties = await _propertyService.getProperties();
      for (var prop in _properties) {
        final units = await _propertyService.getUnits(prop.id);
        _propertyUnits[prop.id] = units;
      }
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void resetSessionState() {
    _properties = [];
    _propertyUnits.clear();
    _propertyPhotos.clear();
    _propertyVideos.clear();
    _tenantAssignedUnit = null;
    clearFailure();
    _isLoading = false;
    _isMediaBusy = false;
    notifyListeners();
  }

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
      if (index != -1) {
        _properties[index] = detail.property;
      }
      _propertyUnits[propertyId] = detail.units;
      notifyListeners();
    } catch (e) {
      captureFailure(e);
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
    required File deedFile,
    List<File> photos = const [],
    File? listingVideo,
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
        listingVideo: listingVideo,
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
