import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/nigeria_locations.dart';
import '../../../../core/utils/landa_haptics.dart';
import '../../../../core/widgets/landa_pressable.dart';
import '../../../../core/widgets/landa_sheet.dart';
import '../../../../core/widgets/landa_toast.dart';
import '../../services/geocoding_service.dart';
import '../../../../core/widgets/landa_busy.dart';

/// Where a pin came from. The source decides what we can say about accuracy:
/// a GPS fix carries a radius worth drawing, a tap is exact by definition.
enum _PinSource { tap, device, address }

class PropertyLocationPicker extends StatefulWidget {
  /// Null until the landlord actually places a pin, so the form can insist on
  /// one instead of silently submitting a fallback city centre.
  final ValueChanged<LatLng?> onChanged;

  /// Supplies the address typed elsewhere in the form, for "find address".
  final String Function()? addressResolver;

  /// Fired whenever the pin resolves to a street, city and state.
  ///
  /// This is the point of the map for most landlords. They drop a pin on
  /// their own gate and the form knows the address, the town and the state
  /// from it: testers were dropping the pin and then typing all three again
  /// underneath, which is the app knowing something and not saying it. The
  /// callback carries whatever resolved, and the form decides what to do with
  /// it — it never overwrites something already typed.
  final ValueChanged<GeocodeAddress>? onAddressResolved;

  final LatLng? initialPin;

  /// The town and state chosen elsewhere in the form.
  ///
  /// Watched rather than merely read: picking a state is the landlord telling
  /// the app where in Nigeria this property is, and a map that keeps showing
  /// Lagos after they said Oyo is ignoring the clearest signal it will ever
  /// get. When these change the viewport follows — it does *not* place a pin.
  final String city;
  final String state;

  /// Whether this is the full-screen picker rather than the one embedded in
  /// the property form. Decides gesture handling and the map's height: see
  /// [_PropertyLocationPickerState._gestureFlags].
  final bool isFullScreen;

  const PropertyLocationPicker({
    super.key,
    required this.onChanged,
    this.addressResolver,
    this.onAddressResolved,
    this.initialPin,
    this.city = '',
    this.state = '',
    this.isFullScreen = false,
  });

  @override
  State<PropertyLocationPicker> createState() => _PropertyLocationPickerState();
}

class _PropertyLocationPickerState extends State<PropertyLocationPicker> {
  /// Only ever the *view* the map opens on, never a value we report upwards.
  static const _fallbackCenter = LatLng(6.5244, 3.3792);
  static const _pinZoom = 17.0;

  /// Wide enough to show a whole state, for the bundled-centre step.
  static const _stateZoom = 9.0;

  final _mapController = MapController();
  final _geocoder = GeocodingService();

  /// Which gestures the map answers.
  ///
  /// **`InteractiveFlag.drag` is deliberately absent when inlined**, which is
  /// why this is a getter rather than the const it used to be.
  ///
  /// Inline, this map lives inside the add-property sheet's
  /// `SingleChildScrollView`: 280px of map in a viewport of roughly 580,
  /// sitting directly above the photo, walkthrough and deed sections. With
  /// single-finger drag enabled the map won every vertical swipe that started
  /// on it, so a landlord scrolling down to add photos panned the map and the
  /// sheet did not move. The form's own blocker line then sat there reading
  /// "Add at least 2 photos of the property", pointing at buttons they could
  /// not reach. Testers reported the sheet as stuck; it was a gesture
  /// conflict, and it made the form unfinishable one-handed.
  ///
  /// So inline: two fingers move the map, one finger scrolls the sheet, and a
  /// tap still drops the pin — a tap is not a drag. Full-screen there is
  /// nothing to scroll past, so drag comes back and the map behaves the way a
  /// map should. That is where the pin actually gets placed accurately, which
  /// matters: it is an anti-fraud control, not decoration.
  int get _gestureFlags {
    if (widget.isFullScreen) {
      // Rotation is only ever accidental on a form like this.
      return InteractiveFlag.all & ~InteractiveFlag.rotate;
    }
    return InteractiveFlag.pinchZoom |
        InteractiveFlag.pinchMove |
        InteractiveFlag.doubleTapZoom;
  }

  LatLng? _pin;
  _PinSource? _source;

  /// Reported GPS radius in metres, drawn as a circle so an obviously bad fix
  /// looks obviously bad.
  double? _accuracy;

  String? _placeName;
  bool _isLocating = false;
  bool _isSearching = false;
  bool _isNaming = false;

  Timer? _nameDebounce;

  /// Guards against a slow reverse-geocode landing after the pin has moved on.
  int _nameToken = 0;

  /// Same guard for the region recentre, which races the same way when
  /// somebody changes state twice quickly.
  int _regionToken = 0;

  @override
  void initState() {
    super.initState();
    _pin = widget.initialPin;
    if (_pin != null) {
      _source = _PinSource.tap;
      _scheduleReverseGeocode(_pin!);
    } else {
      _centreOnDeviceIfAlreadyAllowed();
    }
  }

  @override
  void didUpdateWidget(PropertyLocationPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when it actually changed, and never over a pin the landlord has
    // already placed: moving the camera off somebody's own gate because they
    // corrected the town underneath would lose the one thing they came here
    // to do.
    final regionChanged =
        widget.city != oldWidget.city || widget.state != oldWidget.state;
    if (regionChanged && _pin == null) _centreOnRegion();
  }

  /// Moves the viewport to the chosen town or state. Never places a pin.
  ///
  /// This is what stops a landlord in Ibadan being shown Lagos. The default
  /// centre is Lagos because it has to be something, but the moment the form
  /// knows better, so should the map.
  ///
  /// Two steps, and the first one cannot fail. The bundled
  /// [NigeriaLocations.centreOf] moves the map to the state's capital
  /// immediately — no request, no wait, works offline. Only then does it ask
  /// the network to refine that to the actual town.
  ///
  /// That order is the point. Nominatim rate-limits sporadically: two
  /// identically shaped queries seconds apart returned `429` and `200` while
  /// this was being written, and [GeocodingService] treats any non-200 as
  /// "not found". A network-first design therefore left a throttled landlord
  /// looking at Lagos with no way to tell that anything had gone wrong —
  /// which is almost certainly what the tester in Ibadan actually hit, rather
  /// than the unmapped estate it looked like. Now the worst a throttled
  /// lookup can do is leave them at their state capital instead of their
  /// town.
  Future<void> _centreOnRegion() async {
    final city = widget.city.trim();
    final state = widget.state.trim();
    if (city.isEmpty && state.isEmpty) return;

    final token = ++_regionToken;

    // Step one: instant, offline, cannot fail.
    final centre = NigeriaLocations.centreOf(state);
    if (centre != null && _pin == null) {
      _mapController.move(LatLng(centre.$1, centre.$2), _stateZoom);
    }

    // Step two: refine to the town, if the network is willing.
    if (city.isEmpty) return;
    final hit = await _geocoder.searchProgressive(city: city, state: state);
    // Guards against a slow lookup landing after the landlord has moved on,
    // or has placed a pin in the meantime.
    if (!mounted || token != _regionToken || hit == null || _pin != null) {
      return;
    }
    _mapController.move(hit.result.point, hit.zoom);
  }

  @override
  void dispose() {
    _nameDebounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Opening the map on Lagos when the landlord is in Abuja is the whole
  /// complaint. If location permission is already granted we can quietly move
  /// the viewport to the last known fix: no prompt, and no pin is placed, so
  /// the landlord still has to confirm the exact spot.
  Future<void> _centreOnDeviceIfAlreadyAllowed() async {
    try {
      final permission = await Geolocator.checkPermission();
      final granted =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!granted || !await Geolocator.isLocationServiceEnabled()) return;
      final last = await Geolocator.getLastKnownPosition();
      final position =
          last ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 8),
            ),
          );
      if (!mounted || _pin != null) return;
      _mapController.move(LatLng(position.latitude, position.longitude), 15);
    } catch (_) {
      // A silent convenience: if it fails we simply keep the default view.
    }
  }

  Future<void> _useLiveLocation() async {
    setState(() => _isLocating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _fail(
          'Location Services are off. Turn them on in Settings, then try again.',
          onOpenSettings: Geolocator.openLocationSettings,
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _fail(
          'Location is blocked for Landa. Enable it in Settings, or drop the pin by hand.',
          onOpenSettings: Geolocator.openAppSettings,
        );
        return;
      }
      if (permission == LocationPermission.denied) {
        _fail('Location permission was declined. Tap the map to drop the pin.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      _applyPin(
        LatLng(position.latitude, position.longitude),
        source: _PinSource.device,
        accuracy: position.accuracy,
      );
      if (position.accuracy > 60) {
        LandaToast.info(
          context,
          'Rough fix (±${position.accuracy.round()}m). Drag the map and tap the exact entrance.',
        );
      }
    } catch (error) {
      debugPrint('[LOCATION PICKER] live location failed: $error');
      _fail('Could not read your location. Tap the map to drop the pin.');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// Places the pin from the address already typed into the form, which is the
  /// normal case: landlords add properties from home, not from the doorstep.
  Future<void> _findFromAddress() async {
    final query = widget.addressResolver?.call().trim() ?? '';
    if (query.length < 4) {
      LandaToast.info(context, 'Type the street address above first.');
      return;
    }
    setState(() => _isSearching = true);
    final hit = await _geocoder.searchProgressive(
      street: widget.addressResolver?.call() ?? '',
      city: widget.city,
      state: widget.state,
    );
    if (!mounted) return;
    setState(() => _isSearching = false);

    if (hit == null) {
      // Every level missed — an unmapped address, or the lookup service
      // throttling us. Either way the state is still known locally, so the
      // landlord is taken there rather than left wherever the map happened
      // to be.
      final centre = NigeriaLocations.centreOf(widget.state);
      if (centre != null) {
        _mapController.move(LatLng(centre.$1, centre.$2), _stateZoom);
      }
      LandaToast.error(
        context,
        'Could not find that address. Tap the map to drop the pin instead.',
      );
      return;
    }

    // Only a street-level hit earns a pin. A town or state match is somewhere
    // to *look*: pinning it would put the property at the centroid of Ibadan
    // and call it verified. Nigerian estates are thinly mapped, so this is
    // the common path, not the edge case — the landlord is taken to the right
    // town and asked for the one thing only they know.
    if (!hit.isPinnable) {
      _mapController.move(hit.result.point, hit.zoom);
      LandaToast.info(
        context,
        'Could not find that exact address. Showing ${hit.result.label} — '
        'tap the map on your entrance.',
      );
      return;
    }
    final result = hit.result;
    _applyPin(
      result.point,
      source: _PinSource.address,
      placeName: result.label,
    );
    // The search already carries the parts, so the city and state boxes fill
    // in without a second round trip to the reverse geocoder.
    if (!result.address.isEmpty) widget.onAddressResolved?.call(result.address);
    LandaToast.info(context, 'Found ${result.label}. Nudge the pin if needed.');
  }

  void _applyPin(
    LatLng point, {
    required _PinSource source,
    double? accuracy,
    String? placeName,
    bool recentre = true,
  }) {
    LandaHaptics.select();
    setState(() {
      _pin = point;
      _source = source;
      _accuracy = accuracy;
      _placeName = placeName;
      _isNaming = placeName == null;
    });
    widget.onChanged(point);
    if (recentre) {
      final zoom = _mapController.camera.zoom;
      _mapController.move(point, zoom < _pinZoom ? _pinZoom : zoom);
    }
    if (placeName == null) _scheduleReverseGeocode(point);
  }

  /// Names the pin, and tells the form what it resolved to.
  ///
  /// Debounced, because a landlord fine-tuning the entrance taps the map
  /// several times in a row and Nominatim's usage policy is one request a
  /// second. The token guards the other half of that: a lookup for a pin the
  /// landlord has already moved off must not land and overwrite the newer
  /// one's answer.
  void _scheduleReverseGeocode(LatLng point) {
    _nameDebounce?.cancel();
    final token = ++_nameToken;
    _nameDebounce = Timer(const Duration(milliseconds: 700), () async {
      final resolved = await _geocoder.describe(point);
      if (!mounted || token != _nameToken) return;
      setState(() {
        _placeName = resolved?.label.isNotEmpty == true
            ? resolved!.label
            : null;
        _isNaming = false;
      });
      final address = resolved?.address;
      if (address != null && !address.isEmpty) {
        widget.onAddressResolved?.call(address);
      }
    });
  }

  void _clearPin() {
    _nameDebounce?.cancel();
    _nameToken++;
    LandaHaptics.tap();
    setState(() {
      _pin = null;
      _source = null;
      _accuracy = null;
      _placeName = null;
      _isNaming = false;
    });
    widget.onChanged(null);
  }

  /// Opens the same picker on its own page, handing back whatever pin comes
  /// out of it.
  ///
  /// The full-screen map starts wherever this one is looking, so opening it
  /// is a continuation rather than a restart — a landlord who has already
  /// panned to their street does not arrive back at the country view.
  Future<void> _openFullScreen() async {
    LandaHaptics.tap();
    final navigator = Navigator.of(context);
    final camera = _mapController.camera;
    final result = await navigator.push<_FullScreenPinResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenPinPage(
          initialPin: _pin,
          initialCentre: camera.center,
          initialZoom: camera.zoom,
          addressResolver: widget.addressResolver,
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result.pin == null) {
      _clearPin();
      return;
    }
    _applyPin(result.pin!, source: _PinSource.tap);
  }

  void _zoomBy(double delta) {
    LandaHaptics.tap();
    final camera = _mapController.camera;
    _mapController.move(camera.center, (camera.zoom + delta).clamp(3.0, 19.0));
  }

  void _fail(String message, {VoidCallback? onOpenSettings}) {
    if (!mounted) return;
    LandaToast.error(context, message);
    onOpenSettings?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LandaFieldLabel(
          'Property pin',
          trailing: _LabelAction(
            icon: Icons.travel_explore_rounded,
            label: 'Find from address',
            isBusy: _isSearching,
            onTap: _isSearching ? null : _findFromAddress,
          ),
        ),
        Text(
          _pin == null
              ? 'Tap the map to drop the pin on the property entrance, or use '
                    'one of the shortcuts.'
              : 'Tap again to fine-tune the entrance.',
          style: AppTheme.bodyText(context),
        ),
        // Says the gesture out loud, because a map that ignores a one-finger
        // drag is otherwise indistinguishable from a broken one. Only inline:
        // full-screen the map drags normally and there is nothing to explain.
        if (!widget.isFullScreen) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.pinch_outlined,
                size: 14,
                color: AppTheme.secondaryTextColor(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Use two fingers to move the map, or open it full screen.',
                  style: AppTheme.labelText(
                    context,
                    color: AppTheme.secondaryTextColor(context),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        // Flexible full-screen, fixed inline. It must not be a `Container`
        // with `height: double.infinity`: this sits in a `Column`, which
        // gives an unbounded child exactly what it asks for and then throws a
        // RenderFlex overflow. `Expanded` is how a Column child fills.
        _flexMap(
          ClipRRect(
            borderRadius: AppTheme.cornerMd,
            child: Container(
              height: widget.isFullScreen ? null : 280,
              foregroundDecoration: BoxDecoration(
                borderRadius: AppTheme.cornerMd,
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _pin ?? _fallbackCenter,
                      initialZoom: _pin == null ? 12 : _pinZoom,
                      minZoom: 3,
                      maxZoom: 19,
                      interactionOptions: InteractionOptions(
                        flags: _gestureFlags,
                      ),
                      onTap: (_, point) => _applyPin(
                        point,
                        source: _PinSource.tap,
                        recentre: false,
                      ),
                      onLongPress: (_, point) =>
                          _applyPin(point, source: _PinSource.tap),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.landa.landa_app',
                        maxNativeZoom: 19,
                      ),
                      if (_pin != null && _accuracy != null && _accuracy! > 15)
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: _pin!,
                              radius: _accuracy!,
                              useRadiusInMeter: true,
                              color: AppTheme.actionColor.withValues(
                                alpha: 0.12,
                              ),
                              borderColor: AppTheme.actionColor.withValues(
                                alpha: 0.45,
                              ),
                              borderStrokeWidth: 1,
                            ),
                          ],
                        ),
                      if (_pin != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _pin!,
                              width: 40,
                              height: 52,
                              // Puts the pin's tip, not its middle, on the
                              // coordinate, so what you see is what you save.
                              alignment: Alignment.topCenter,
                              child: const _MapPin(),
                            ),
                          ],
                        ),
                    ],
                  ),
                  Positioned(left: 8, top: 8, child: const _Attribution()),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: Column(
                      children: [
                        _MapButton(
                          icon: Icons.add_rounded,
                          tooltip: 'Zoom in',
                          onTap: () => _zoomBy(1),
                        ),
                        const SizedBox(height: 8),
                        _MapButton(
                          icon: Icons.remove_rounded,
                          tooltip: 'Zoom out',
                          onTap: () => _zoomBy(-1),
                        ),
                        // The way out of the cramped inline map. Placing a pin
                        // on your own gate wants the whole screen, and there
                        // one finger drags normally.
                        if (!widget.isFullScreen) ...[
                          const SizedBox(height: 8),
                          _MapButton(
                            icon: Icons.open_in_full_rounded,
                            tooltip: 'Open full screen',
                            onTap: _openFullScreen,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 78,
                    child: Column(
                      children: [
                        if (_pin != null) ...[
                          _MapButton(
                            icon: Icons.close_rounded,
                            tooltip: 'Clear pin',
                            onTap: _clearPin,
                          ),
                          const SizedBox(height: 8),
                        ],
                        _MapButton(
                          icon: Icons.my_location_rounded,
                          tooltip: 'Use my location',
                          isBusy: _isLocating,
                          highlighted: _source == _PinSource.device,
                          onTap: _isLocating ? null : _useLiveLocation,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: _Readout(
                      pin: _pin,
                      placeName: _placeName,
                      isNaming: _isNaming,
                      accuracy: _accuracy,
                      source: _source,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Fills the page full-screen, holds 280px inline.
  ///
  /// [Expanded] only works as a direct child of the [Column] in `build`, and
  /// only when that Column has a bounded height — which it does full-screen,
  /// where the page wraps this picker in one. Inline the Column is inside a
  /// scroll view and therefore unbounded, so `Expanded` there would be the
  /// same crash from the other direction.
  Widget _flexMap(Widget map) =>
      widget.isFullScreen ? Expanded(child: map) : map;
}

/// What the full-screen picker hands back.
///
/// A class rather than a bare `LatLng?`, because null has to mean two
/// different things at this boundary: backing out (change nothing) and
/// clearing the pin (change it to none). Popping null is the former; popping
/// a result whose [pin] is null is the latter.
class _FullScreenPinResult {
  final LatLng? pin;

  const _FullScreenPinResult(this.pin);
}

/// The pin map with the whole screen to itself.
///
/// Exists because the inline map cannot have single-finger drag — it would
/// swallow the sheet's scroll — and placing a pin on your own gate with two
/// fingers in a 280px window is a worse job than the anti-fraud control
/// deserves. Here there is nothing to scroll past, so the map drags, flings
/// and pinches like any other.
class _FullScreenPinPage extends StatefulWidget {
  final LatLng? initialPin;
  final LatLng initialCentre;
  final double initialZoom;
  final String Function()? addressResolver;

  const _FullScreenPinPage({
    required this.initialPin,
    required this.initialCentre,
    required this.initialZoom,
    this.addressResolver,
  });

  @override
  State<_FullScreenPinPage> createState() => _FullScreenPinPageState();
}

class _FullScreenPinPageState extends State<_FullScreenPinPage> {
  late LatLng? _pin = widget.initialPin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor(context),
        surfaceTintColor: Colors.transparent,
        title: Text('Place the pin', style: AppTheme.sectionTitle(context)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          // Backing out changes nothing, which is why this pops null rather
          // than the pin currently on screen.
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              Expanded(
                child: PropertyLocationPicker(
                  isFullScreen: true,
                  initialPin: widget.initialPin,
                  addressResolver: widget.addressResolver,
                  onChanged: (pin) => setState(() => _pin = pin),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: LandaSheetButton(
                  label: _pin == null ? 'Done without a pin' : 'Use this pin',
                  icon: _pin == null
                      ? Icons.close_rounded
                      : Icons.check_rounded,
                  onPressed: () =>
                      Navigator.pop(context, _FullScreenPinResult(_pin)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A teardrop whose point sits exactly on the coordinate.
class _MapPin extends StatelessWidget {
  const _MapPin();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppTheme.actionColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.home_rounded, size: 15, color: Colors.white),
        ),
        Container(width: 2.5, height: 10, color: AppTheme.actionColor),
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: AppTheme.actionColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
        ),
      ],
    );
  }
}

/// Address line plus coordinates, floating on the map so the pin and its
/// read-out stay one object.
class _Readout extends StatelessWidget {
  final LatLng? pin;
  final String? placeName;
  final bool isNaming;
  final double? accuracy;
  final _PinSource? source;

  const _Readout({
    required this.pin,
    required this.placeName,
    required this.isNaming,
    required this.accuracy,
    required this.source,
  });

  @override
  Widget build(BuildContext context) {
    final hasPin = pin != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context).withValues(alpha: 0.94),
        borderRadius: AppTheme.cornerSm,
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            hasPin ? Icons.place_rounded : Icons.touch_app_outlined,
            size: 18,
            color: hasPin
                ? AppTheme.actionColor
                : AppTheme.secondaryTextColor(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: !hasPin
                ? Text(
                    'No pin yet. Tap the map',
                    style: AppTheme.labelText(context),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isNaming
                            ? 'Looking up address…'
                            : (placeName ?? 'Pin dropped'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.labelText(
                          context,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _coordinateLine(),
                        style: AppTheme.labelText(
                          context,
                          color: AppTheme.secondaryTextColor(context),
                        ).copyWith(fontSize: AppTheme.textXs),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _coordinateLine() {
    final coords =
        '${pin!.latitude.toStringAsFixed(5)}, ${pin!.longitude.toStringAsFixed(5)}';
    if (source == _PinSource.device && accuracy != null) {
      return '$coords · ±${accuracy!.round()}m';
    }
    return coords;
  }
}

/// Small round control that reads clearly over map tiles.
class _MapButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isBusy;
  final bool highlighted;

  const _MapButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.isBusy = false,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = highlighted
        ? Colors.white
        : AppTheme.primaryTextColor(context);
    return Tooltip(
      message: tooltip,
      child: LandaPressable(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: highlighted
                ? AppTheme.actionColor
                : AppTheme.surfaceColor(context).withValues(alpha: 0.94),
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: isBusy
              ? const Center(child: LandaBusyDots(color: AppTheme.actionColor))
              : Icon(icon, size: 19, color: foreground),
        ),
      ),
    );
  }
}

class _LabelAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isBusy;
  final VoidCallback? onTap;

  const _LabelAction({
    required this.icon,
    required this.label,
    required this.isBusy,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LandaPressable(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isBusy)
            const LandaBusyDots(color: AppTheme.actionColor, size: 4)
          else
            Icon(icon, size: 15, color: AppTheme.actionColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTheme.labelText(context, color: AppTheme.actionColor),
          ),
        ],
      ),
    );
  }
}

/// OpenStreetMap's tile terms require visible credit.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '© OpenStreetMap',
        style: AppTheme.labelText(
          context,
          color: AppTheme.secondaryTextColor(context),
        ).copyWith(fontSize: 9),
      ),
    );
  }
}
