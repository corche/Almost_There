import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../domain/entities/destination.dart';
import '../../domain/repositories/destination_repository.dart';

/// Hive is only opened by the UI isolate. The monitor maintains its own snapshot.
class HiveDestinationRepository implements DestinationRepository {
  HiveDestinationRepository(this.box);
  final Box<String> box;

  static Future<HiveDestinationRepository> open() async {
    await Hive.initFlutter();
    return HiveDestinationRepository(
      await Hive.openBox<String>('destinations_v1'),
    );
  }

  @override
  Future<List<Destination>> load() async {
    final source = box.get('items');
    if (source == null) return [];
    final values = jsonDecode(source) as List;
    return values
        .map(
          (value) =>
              Destination.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
  }

  @override
  Future<void> saveAll(List<Destination> destinations) => box.put(
    'items',
    jsonEncode(destinations.map((d) => d.toJson()).toList()),
  );
}
