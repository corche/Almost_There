# Alarm output

Private Flutter plugin registered on both the UI engine and Android service engine.
Android uses one native `MediaPlayer` shared between engines; iOS uses `AVAudioPlayer`.
Flutter `just_audio` remains the browser/macOS preview fallback.

## Routing

- Speaker mode requests the built-in speaker. Android stays muted until `getRoutedDevice()` confirms it; iOS overrides the audio session output and checks the route.
- Earphone mode requires a wired, Bluetooth, or USB headset output. Missing or unsupported output stays silent.
- Android guards `ACTION_AUDIO_BECOMING_NOISY`, device removal, routing changes, and polls the route while playing. iOS mutes/stops on audio route notifications. It never intentionally falls back to speaker. Actual transition timing depends on OS/device routing callbacks and requires wired/Bluetooth device testing.
- Android's “same volume” option shares the alarm stream; disabling it uses the media stream for earphones. App gain is preserved in either case. iOS exposes one system output volume; it can preserve app gain but cannot equalize perceived loudness between physical outputs.
- Fade is applied by the native player, so Dart UI frame scheduling does not control it.

## Background execution

Android: an explicit user activation starts a location + media-playback foreground service. `SharedPreferencesAsync` stores the configuration, one-shot fired flags, and current alarm; only the UI uses Hive. The service owns playback, persists the trigger before notifying the UI, and retains the alarm until dismissed. No boot autostart is configured: reopen the app after a reboot or force-stop. OS/OEM battery restrictions may still stop monitoring.

iOS: `geolocator` uses Core Location with background location updates on the main engine, `location`/`audio` background modes, and Always permission. `flutter_background_service` is not treated as an unlimited iOS service. The OS may suspend/terminate the app. A local notification is used in the background; the full-screen page opens on tapping it. No Android-style system overlay or automatic full-screen launch is possible. Notification sound/vibration is disabled because playback must respect the selected exclusive output; if iOS suspends custom playback there is no fallback speaker sound.

The notification channel intentionally has no sound or vibration: native audio/vibration is the sole owner and must not be doubled by the operating system notification. Android 14+ full-screen intent access is inspected/requested separately from overlay permission. Distribution eligibility and granted access determine whether Android shows a full-screen view or heads-up notification.

## Original audio

`tool/generate_audio.py` reproducibly generates `assets/audio/gentle.wav`, `bell.wav`, and `chime.wav` using sine harmonics. The files contain no third-party recordings.

## Device verification before distribution

Build on Android and macOS/iOS toolchains. Check screen-off GPS arrival, permission revocation, one-shot arrival after process recreation, notification tap/cold start, two active destinations, Android battery saver, wired/Bluetooth unplug mid-alarm, speaker mode with headphones attached, iOS background delivery, and hardware vibration amplitude support. iOS devices without amplitude control use their supported vibration strength.

Primary references: [background service](https://pub.dev/packages/flutter_background_service), [local notifications](https://pub.dev/packages/flutter_local_notifications/versions/19.5.0), [Android full-screen intent limits](https://source.android.com/docs/core/permissions/fsi-limits), [audio session](https://pub.dev/packages/audio_session).
