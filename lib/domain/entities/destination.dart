enum AlarmType { sound, vibration, earphones }

enum AlarmBackground { gradient, image, video }

/// Immutable, platform-independent arrival alarm configuration.
class Destination {
  const Destination({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address = '',
    this.radius = 500,
    this.enabled = false,
    this.alarmType = AlarmType.sound,
    this.soundId = 'gentle',
    this.volume = 0.7,
    this.vibrationIntensity = 0.7,
    this.vibrateWithSound = false,
    this.fadeInSeconds = 10,
    this.background = AlarmBackground.gradient,
    this.gradientColors = const [0xFF384838, 0xFF94744B, 0xFFE68A4D],
    this.mediaPath,
    this.customSoundPath,
    this.category = 'place',
  });

  final String id, name, address, soundId, category;
  final double latitude, longitude, radius, volume, vibrationIntensity;
  final bool enabled, vibrateWithSound;
  final AlarmType alarmType;
  final int fadeInSeconds;
  final AlarmBackground background;
  final List<int> gradientColors;
  final String? mediaPath, customSoundPath;

  String get radiusLabel => radius >= 1000
      ? '${(radius / 1000).toStringAsFixed(radius % 1000 == 0 ? 0 : 1)}km'
      : '${radius.round()}m';

  String get alarmLabel => switch (alarmType) {
    AlarmType.sound => '소리',
    AlarmType.vibration => '진동',
    AlarmType.earphones => '이어폰',
  };

  Destination copyWith({
    String? name,
    String? address,
    double? latitude,
    double? longitude,
    double? radius,
    bool? enabled,
    AlarmType? alarmType,
    String? soundId,
    double? volume,
    double? vibrationIntensity,
    bool? vibrateWithSound,
    int? fadeInSeconds,
    AlarmBackground? background,
    List<int>? gradientColors,
    String? mediaPath,
    String? customSoundPath,
    String? category,
    bool clearMedia = false,
    bool clearCustomSound = false,
  }) => Destination(
    id: id,
    name: name ?? this.name,
    address: address ?? this.address,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    radius: radius ?? this.radius,
    enabled: enabled ?? this.enabled,
    alarmType: alarmType ?? this.alarmType,
    soundId: soundId ?? this.soundId,
    volume: volume ?? this.volume,
    vibrationIntensity: vibrationIntensity ?? this.vibrationIntensity,
    vibrateWithSound: vibrateWithSound ?? this.vibrateWithSound,
    fadeInSeconds: fadeInSeconds ?? this.fadeInSeconds,
    background: background ?? this.background,
    gradientColors: gradientColors ?? this.gradientColors,
    mediaPath: clearMedia ? null : mediaPath ?? this.mediaPath,
    customSoundPath: clearCustomSound
        ? null
        : customSoundPath ?? this.customSoundPath,
    category: category ?? this.category,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'radius': radius,
    'enabled': enabled,
    'alarmType': alarmType.name,
    'soundId': soundId,
    'volume': volume,
    'vibrationIntensity': vibrationIntensity,
    'vibrateWithSound': vibrateWithSound,
    'fadeInSeconds': fadeInSeconds,
    'background': background.name,
    'gradientColors': gradientColors,
    'mediaPath': mediaPath,
    'customSoundPath': customSoundPath,
    'category': category,
  };

  factory Destination.fromJson(Map<String, dynamic> json) => Destination(
    id: json['id'] as String,
    name: json['name'] as String,
    address: json['address'] as String? ?? '',
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    radius: ((json['radius'] as num?) ?? 500).toDouble().clamp(100, 2000),
    enabled: json['enabled'] as bool? ?? false,
    alarmType: AlarmType.values.firstWhere(
      (v) => v.name == json['alarmType'],
      orElse: () => AlarmType.sound,
    ),
    soundId: json['soundId'] as String? ?? 'gentle',
    volume: ((json['volume'] as num?) ?? .7).toDouble().clamp(0, 1),
    vibrationIntensity: ((json['vibrationIntensity'] as num?) ?? .7)
        .toDouble()
        .clamp(0, 1),
    vibrateWithSound: json['vibrateWithSound'] as bool? ?? false,
    fadeInSeconds: ((json['fadeInSeconds'] as num?) ?? 10).toInt().clamp(
      3,
      120,
    ),
    background: AlarmBackground.values.firstWhere(
      (v) => v.name == json['background'],
      orElse: () => AlarmBackground.gradient,
    ),
    gradientColors:
        (json['gradientColors'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        const [0xFF384838, 0xFF94744B, 0xFFE68A4D],
    mediaPath: json['mediaPath'] as String?,
    customSoundPath: json['customSoundPath'] as String?,
    category: json['category'] as String? ?? 'place',
  );
}
