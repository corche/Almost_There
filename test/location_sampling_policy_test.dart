import 'package:almost_there/domain/services/location_sampling_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'tunnel travel estimate speeds up requests without declaring arrival',
    () {
      expect(
        LocationSamplingPolicy.approachingDuringSilence(
          distanceToBoundary: 6000,
          speed: 80,
          silence: const Duration(seconds: 45),
        ),
        true,
      );
      expect(
        LocationSamplingPolicy.approachingDuringSilence(
          distanceToBoundary: 6000,
          speed: 10,
          silence: const Duration(seconds: 45),
        ),
        false,
      );
      expect(
        LocationSamplingPolicy.approachingDuringSilence(
          distanceToBoundary: 6000,
          speed: double.nan,
          silence: const Duration(seconds: 45),
        ),
        false,
      );
    },
  );
  test('nearby GPS silence is recovered after 30 seconds', () {
    expect(
      LocationSamplingPolicy.needsReconnect(
        requestedSeconds: 5,
        silence: const Duration(seconds: 29),
      ),
      false,
    );
    expect(
      LocationSamplingPolicy.needsReconnect(
        requestedSeconds: 5,
        silence: const Duration(seconds: 30),
      ),
      true,
    );
  });
  test('slow sampling has a grace period before provider recovery', () {
    expect(
      LocationSamplingPolicy.needsReconnect(
        requestedSeconds: 60,
        silence: const Duration(seconds: 120),
      ),
      false,
    );
    expect(
      LocationSamplingPolicy.needsReconnect(
        requestedSeconds: 60,
        silence: const Duration(seconds: 135),
      ),
      true,
    );
  });
  int sample(
    double distance, {
    double speed = 10,
    double accuracy = 10,
    Duration age = Duration.zero,
  }) => LocationSamplingPolicy.intervalSeconds(
    distanceToBoundary: distance,
    speed: speed,
    accuracy: accuracy,
    fixAge: age,
  );

  test(
    'far, intermediate and nearby travel use progressively shorter intervals',
    () {
      expect(sample(12000), 60);
      expect(sample(5000), 30);
      expect(sample(2000), 5);
      expect(sample(-100), 5);
    },
  );
  test('fast trains reduce intervals before reaching the near zone', () {
    expect(sample(11000, speed: 100), 30);
    expect(sample(4000, speed: 100), 10);
  });
  test('uncertainty is subtracted from remaining distance at a boundary', () {
    expect(sample(3010, accuracy: 30), 5);
    expect(sample(10010, accuracy: 30), 30);
  });
  test('stale or unreliable fixes cannot enable slow sampling', () {
    expect(sample(20000, age: const Duration(minutes: 3)), 5);
    expect(sample(20000, accuracy: 500), 5);
    expect(sample(double.nan), 5);
    expect(sample(20000, accuracy: double.nan), 5);
  });
  test(
    'stopped and unknown-speed trips still have a bounded request interval',
    () {
      expect(sample(20000, speed: 0), 60);
      expect(sample(3500, speed: -1), 30);
      expect(sample(20000, speed: double.nan), 60);
    },
  );
}
