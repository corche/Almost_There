import 'package:almost_there/domain/entities/destination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('destination serializes its complete alarm configuration', () {
    const destination = Destination(
      id: 'home',
      name: '우리 집',
      address: '서울특별시',
      latitude: 37.5,
      longitude: 127.0,
      radius: 1500,
      enabled: true,
      alarmType: AlarmType.earphones,
      fadeInSeconds: 30,
      background: AlarmBackground.gradient,
    );
    final restored = Destination.fromJson(destination.toJson());
    expect(restored.name, '우리 집');
    expect(restored.radiusLabel, '1.5km');
    expect(restored.alarmType, AlarmType.earphones);
    expect(restored.fadeInSeconds, 30);
  });
}
