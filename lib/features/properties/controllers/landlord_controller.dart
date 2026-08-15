import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../models/property_model.dart';
import '../services/property_service.dart';

class LandlordController extends ChangeNotifier {
  final PropertyService _propertyService;

  LandlordController({PropertyService? propertyService})
    : _propertyService = propertyService ?? PropertyService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<PropertyModel> _properties = [];
  List<PropertyModel> get properties => _properties;

  final Map<String, List<UnitModel>> _propertyUnits = {};
  Map<String, List<UnitModel>> get propertyUnits => _propertyUnits;

  UnitModel? _tenantAssignedUnit;
  UnitModel? get tenantAssignedUnit => _tenantAssignedUnit;

  /// Load properties for landlord
  Future<void> loadLandlordProperties() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _properties = await _propertyService.getProperties();
      for (var prop in _properties) {
        final units = await _propertyService.getUnits(prop.id);
        _propertyUnits[prop.id] = units;
      }
    } catch (e) {
      _errorMessage = friendlyErrorMessage(e);
    } finally {
      _isLoading = false;
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
      _errorMessage = friendlyErrorMessage(e);
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
  }) async {
    _isLoading = true;
    _errorMessage = null;
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
      _errorMessage = friendlyErrorMessage(e);
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
    _errorMessage = null;
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
      _errorMessage = friendlyErrorMessage(e);
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
    _errorMessage = null;
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
      _errorMessage = friendlyErrorMessage(e);
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
    _errorMessage = null;
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
      _errorMessage = friendlyErrorMessage(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch tenant's assigned unit
  Future<void> loadTenantAssignedUnit() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _tenantAssignedUnit = await _propertyService.getTenantAssignedUnit();
    } catch (e) {
      _errorMessage = friendlyErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
