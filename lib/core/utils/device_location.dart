import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Why a location request ended the way it did.
///
/// The distinction that matters is [denied] versus [blocked]: a plain denial
/// can be asked about again next time, but "never ask again" can only be
/// undone in Settings, so the two need different copy and different buttons.
enum LocationOutcome {
  granted,

  /// The user said no this time.
  denied,

  /// Permanently refused, or restricted by device policy. Only Settings can
  /// change it.
  blocked,

  /// Location Services are switched off for the whole device.
  servicesOff,

  /// Permitted, but no fix came back in time.
  unavailable,
}

/// A resolved location request: the outcome, and coordinates when there are
/// any.
class DeviceLocation {
  final LocationOutcome outcome;
  final double? latitude;
  final double? longitude;

  const DeviceLocation(this.outcome, {this.latitude, this.longitude});

  bool get hasCoordinates => latitude != null && longitude != null;

  /// Whether asking again could plausibly succeed. False for [blocked] and
  /// [servicesOff], which need the user to leave the app first.
  bool get isRetryable =>
      outcome == LocationOutcome.denied ||
      outcome == LocationOutcome.unavailable;

  /// One line to show the user. Null when there is nothing to say: a
  /// successful fix, or a denial the user made deliberately a moment ago and
  /// does not need narrated back at them.
  String? get message {
    switch (outcome) {
      case LocationOutcome.granted:
      case LocationOutcome.denied:
        return null;
      case LocationOutcome.blocked:
        return 'Location is blocked for Landa. Turn it on in Settings, or '
            'search by area name instead.';
      case LocationOutcome.servicesOff:
        return 'Location Services are off. Turn them on in Settings, or '
            'search by area name instead.';
      case LocationOutcome.unavailable:
        return 'Could not read your location. Search by area name instead.';
    }
  }
}

/// Reads the device's coordinates for search-by-distance.
///
/// Deliberately soft-failing throughout: everywhere this is used, typing an
/// area name does the same job, so a refusal is a fallback rather than an
/// error. Nothing here throws.
class DeviceLocationService {
  const DeviceLocationService._();

  /// Bound on the calls that ask the platform a question it already knows the
  /// answer to. None of them should take any time at all, so one that has not
  /// answered by now is wedged, and a caller left waiting on it shows a
  /// spinner that never stops.
  static const Duration _probeTimeout = Duration(seconds: 5);

  /// Bound on actually reading a position. Longer than the fix's own
  /// `timeLimit` below, so a slow GPS gets to fail on its own terms first and
  /// this only catches a call that never comes back at all.
  static const Duration _fixTimeout = Duration(seconds: 15);

  /// Asks for permission if needed, then reads a position.
  ///
  /// [prompt] false turns this into a read that never shows a system dialog:
  /// it returns [LocationOutcome.denied] rather than asking. Use it when the
  /// screen wants coordinates only if the user has already agreed.
  static Future<DeviceLocation> current({bool prompt = true}) async {
    try {
      final servicesEnabled = await Geolocator.isLocationServiceEnabled()
          .timeout(_probeTimeout);
      if (!servicesEnabled) {
        return const DeviceLocation(LocationOutcome.servicesOff);
      }

      var permission = await Geolocator.checkPermission().timeout(
        _probeTimeout,
      );
      if (permission == LocationPermission.denied) {
        if (!prompt) return const DeviceLocation(LocationOutcome.denied);
        // Deliberately unbounded: a person is reading a dialog, and taking a
        // moment over it is not a failure.
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const DeviceLocation(LocationOutcome.blocked);
      }
      if (permission == LocationPermission.denied) {
        return const DeviceLocation(LocationOutcome.denied);
      }

      // The last known fix is good enough to sort listings by distance and
      // arrives instantly; a fresh read is only worth waiting for when there
      // is nothing cached.
      final position =
          await Geolocator.getLastKnownPosition().timeout(_probeTimeout) ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 12),
            ),
          ).timeout(_fixTimeout);

      return DeviceLocation(
        LocationOutcome.granted,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (error) {
      // Covers a refusal by the platform, a plugin that is not there, and a
      // timeout above. All of them mean the same thing to the caller: no
      // coordinates, carry on with typed search.
      debugPrint('[LOCATION] request failed: $error');
      return const DeviceLocation(LocationOutcome.unavailable);
    }
  }

  /// Opens the page that can undo a [LocationOutcome.blocked] or
  /// [LocationOutcome.servicesOff] result.
  static Future<void> openSettingsFor(LocationOutcome outcome) async {
    try {
      if (outcome == LocationOutcome.servicesOff) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (error) {
      debugPrint('[LOCATION] could not open settings: $error');
    }
  }
}
