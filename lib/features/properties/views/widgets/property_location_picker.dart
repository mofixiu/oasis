import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/landa_pressable.dart';
import '../../../../core/widgets/landa_sheet.dart';

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
        LandaFieldLabel(
          'Property pin',
          trailing: LandaPressable(
            onTap: _isLocating ? null : _useLiveLocation,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLocating)
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.actionColor,
                    ),
                  )
                else
                  const Icon(
                    Icons.my_location_rounded,
                    size: 15,
                    color: AppTheme.actionColor,
                  ),
                const SizedBox(width: 6),
                Text(
                  'Use live location',
                  style: AppTheme.labelText(
                    context,
                    color: AppTheme.actionColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(
          'Tap the map to drop or move the pin to the property entrance.',
          style: AppTheme.bodyText(context),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: AppTheme.cornerMd,
          child: Container(
            height: 220,
            foregroundDecoration: BoxDecoration(
              borderRadius: AppTheme.cornerMd,
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _pin,
                    initialZoom: 13,
                    onTap: (_, point) => _setPin(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
                            color: AppTheme.actionColor,
                            size: 40,
                            shadows: [
                              Shadow(color: Colors.black26, blurRadius: 8),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Coordinates float on the map rather than sitting under it,
                // so the pin and its read-out are one object.
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor(
                        context,
                      ).withValues(alpha: 0.92),
                      borderRadius: AppTheme.cornerSm,
                    ),
                    child: Text(
                      '${_pin.latitude.toStringAsFixed(5)}, ${_pin.longitude.toStringAsFixed(5)}',
                      style: AppTheme.labelText(
                        context,
                        color: AppTheme.secondaryTextColor(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
