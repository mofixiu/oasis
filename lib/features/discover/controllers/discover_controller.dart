import 'package:flutter/material.dart';
import '../models/property.dart';
import '../services/mock_discover_service.dart';

/// Controller for the Discover feature.
/// Manages the state of property listings.
class DiscoverController extends ChangeNotifier {
  final IDiscoverService _discoverService;

  DiscoverController({required IDiscoverService discoverService})
      : _discoverService = discoverService;

  List<Property> _properties = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Property> get properties => _properties;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Fetches the property listings from the service.
  Future<void> fetchProperties() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _properties = await _discoverService.getProperties();
    } catch (e) {
      _errorMessage = 'Failed to load properties. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
