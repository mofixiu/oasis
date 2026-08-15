import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class PropertyLocationPicker extends StatefulWidget {
  final ValueChanged<LatLng> onChanged;

  const PropertyLocationPicker({super.key, required this.onChanged});

  @override
  State<PropertyLocationPicker> createState() => _PropertyLocationPickerState();
}

class _PropertyLocationPickerState extends State<PropertyLocationPicker> {
  static const _lagos = LatLng(6.5244, 3.3792);
  final _mapController = MapController();
  LatLng _pin = _lagos;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    widget.onChanged(_pin);
  }

  Future<void> _useLiveLocation() async {
    setState(() => _isLocating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception(
          'Turn on Location Services to use your current position.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permission was not granted. You can still drop a pin manually.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _pin = point);
      _mapController.move(point, 16);
      widget.onChanged(point);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _setPin(LatLng point) {
    setState(() => _pin = point);
    widget.onChanged(point);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'PROPERTY PIN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _isLocating ? null : _useLiveLocation,
              icon: _isLocating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, size: 16),
              label: const Text('Use live location'),
            ),
          ],
        ),
        const Text(
          'Tap the map to drop or move the pin to the property entrance.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 220,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _pin,
                initialZoom: 13,
                onTap: (_, point) => _setPin(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.landa.landa_app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _pin,
                      width: 48,
                      height: 48,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 42,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_pin.latitude.toStringAsFixed(6)}, ${_pin.longitude.toStringAsFixed(6)}',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}
