import 'dart:math' as math;

/// Great-circle distance between two coordinates, in kilometres.
///
/// This exists because the backend answers geographically for Stays and not
/// for the rental marketplace: `GET /tenant/short-lets/` takes coordinates and
/// returns `distance_km`, while `GET /tenant/marketplace/` takes only a typed
/// area name. Marketplace payloads *do* carry each property's `latitude` and
/// `longitude`, so the app can order listings by distance itself until the
/// endpoint learns to: see §2 of `backend_change_spec_v6.md`.
///
/// A server-sent `distance_km` always wins where one arrives. This is a
/// stand-in, and the two must never disagree on screen.
class GeoDistance {
  const GeoDistance._();

  /// Mean Earth radius. Haversine on a sphere is accurate to a few parts in a
  /// thousand over city distances: far tighter than the "is this walkable?"
  /// question a listing card is answering.
  static const double _earthRadiusKm = 6371.0088;

  /// Kilometres between two points, or null when either is incomplete.
  ///
  /// Null rather than a sentinel distance: a property the landlord never
  /// pinned has an unknown position, and sorting it as if it were on the
  /// equator would push it to the bottom of a nearby search with a confident
  /// number beside it.
  static double? betweenOrNull({
    required double? fromLatitude,
    required double? fromLongitude,
    required double? toLatitude,
    required double? toLongitude,
  }) {
    if (fromLatitude == null ||
        fromLongitude == null ||
        toLatitude == null ||
        toLongitude == null) {
      return null;
    }
    // (0, 0) is in the Gulf of Guinea and is what an un-geocoded record looks
    // like far more often than it is a real address: roughly 700km from
    // Lagos, which would read as a plausible distance rather than as missing
    // data. Treated as absent.
    if (toLatitude == 0 && toLongitude == 0) return null;

    final dLat = _radians(toLatitude - fromLatitude);
    final dLon = _radians(toLongitude - fromLongitude);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(_radians(fromLatitude)) *
            math.cos(_radians(toLatitude)) *
            math.pow(math.sin(dLon / 2), 2);
    return _earthRadiusKm * 2 * math.asin(math.min(1, math.sqrt(a)));
  }

  /// "1.2 km away": the wording Stays already uses, so a tenant reads the
  /// same phrase for the same fact on both screens.
  ///
  /// Rounded to whole kilometres past 10, where a decimal is noise.
  static String? label(double? km) {
    if (km == null || km < 0) return null;
    if (km < 1) return '${(km * 1000).round()} m away';
    if (km < 10) return '${km.toStringAsFixed(1)} km away';
    return '${km.round()} km away';
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
