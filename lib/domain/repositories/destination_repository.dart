import '../entities/destination.dart';

abstract interface class DestinationRepository {
  Future<List<Destination>> load();
  Future<void> saveAll(List<Destination> destinations);
}
