import 'package:shared_preferences/shared_preferences.dart';

/// Bounded local diagnostic history; no coordinates or destination names.
class ArrivalDiagnostics {
  static const key = 'arrival.diagnostics.v1';
  final _prefs = SharedPreferencesAsync();
  Future<void> record(String event) async {
    try {
      final rows = await _prefs.getStringList(key) ?? [];
      rows.add('${DateTime.now().toIso8601String()} $event');
      await _prefs.setStringList(
        key,
        rows.length > 400 ? rows.sublist(rows.length - 400) : rows,
      );
    } catch (_) {
      // Diagnostic storage must never prevent an alarm from firing.
    }
  }

  Future<String> read() async =>
      (await _prefs.getStringList(key) ?? []).join('\n');
}
