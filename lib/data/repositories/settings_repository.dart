import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  SettingsRepository(this.preferences);
  final SharedPreferences preferences;
  String get theme => preferences.getString('theme') ?? 'system';
  bool get onboardingComplete =>
      preferences.getBool('onboarding_complete') ?? false;
  Future<void> setTheme(String value) async {
    await preferences.setString('theme', value);
  }

  Future<void> completeOnboarding() async {
    await preferences.setBool('onboarding_complete', true);
  }
}
