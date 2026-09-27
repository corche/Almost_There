import 'dart:math' as math;

/// Requested intervals, not a guarantee of Android GPS delivery timing.
class LocationSamplingPolicy {
  /// Proximity estimate is for sampling only, never for an arrival trigger.
  static bool approachingDuringSilence({
    required double distanceToBoundary,
    required double speed,
    required Duration silence,
  }) {
    if (!distanceToBoundary.isFinite || !speed.isFinite || speed <= 0) {
      return false;
    }
    return distanceToBoundary - speed * silence.inMilliseconds / 1000 <= 3000;
  }

  static bool needsReconnect({
    required int requestedSeconds,
    required Duration silence,
  }) =>
      silence >= Duration(seconds: (requestedSeconds * 2 + 15).clamp(30, 135));

  static int intervalSeconds({
    required double distanceToBoundary,
    required double speed,
    required double accuracy,
    required Duration fixAge,
  }) {
    if (!distanceToBoundary.isFinite ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > 200 ||
        fixAge.abs() > const Duration(minutes: 2)) {
      return 5;
    }
    final remaining = math.max(0.0, distanceToBoundary - accuracy);
    final distanceInterval = remaining >= 10000
        ? 60
        : remaining >= 3000
        ? 30
        : 5;
    // Assume at least 30 km/h even while stopped, allowing for departure.
    final travelSpeed = speed.isFinite && speed >= 0
        ? math.max(speed, 8.34)
        : 33.34; // Unknown speed: conservatively assume 120 km/h.
    final budget = math.min(
      distanceInterval.toDouble(),
      remaining / travelSpeed / 3,
    );
    for (final interval in const [60, 30, 20, 10, 5]) {
      if (interval <= budget) return interval;
    }
    return 5;
  }
}
