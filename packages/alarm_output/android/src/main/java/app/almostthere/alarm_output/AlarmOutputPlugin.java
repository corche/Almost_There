package app.almostthere.alarm_output;

import android.app.NotificationManager;
import android.app.Notification;
import android.app.PendingIntent;
import android.app.KeyguardManager;
import android.content.Context;
import android.content.BroadcastReceiver;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.res.AssetFileDescriptor;
import android.app.Activity;
import android.net.Uri;
import android.provider.OpenableColumns;
import android.provider.Settings;
import android.util.Log;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.database.Cursor;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioDeviceCallback;
import android.media.AudioDeviceInfo;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.embedding.engine.loader.FlutterLoader;
import io.flutter.embedding.android.FlutterSurfaceView;
import io.flutter.embedding.android.FlutterView;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import org.json.JSONObject;

/** Output is shared across engines, so dismissing in the UI stops service audio. */
public final class AlarmOutputPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler,
        ActivityAware, PluginRegistry.ActivityResultListener {
    private static final String TAG = "AlmostThereOverlay";
    private static final int PICK_AUDIO_REQUEST = 49142;
    private MethodChannel channel;
    private FlutterPluginBinding binding;
    private ActivityPluginBinding activityBinding;
    private MethodChannel.Result audioPickerResult;
    private final boolean overlayInstance;
    private static MediaPlayer player;
    private static AudioManager audio;
    private static AudioManager.OnAudioFocusChangeListener audioFocusListener;
    private static AudioFocusRequest audioFocusRequest;
    private static int previousMediaVolume = -1;
    private static int targetMediaVolume = -1;
    private static int appliedMediaVolume = -1;
    private static boolean mediaVolumeAdjusted;
    private static AudioDeviceCallback deviceCallback;
    private static BroadcastReceiver noisyReceiver;
    private static Context playbackContext;
    private static final Handler handler = new Handler(Looper.getMainLooper());
    private static int generation = 0;
    private static String playbackOwner;
    private static WindowManager overlayWindowManager;
    private static View overlayView;
    private static FlutterEngine overlayEngine;
    private static final List<MethodChannel> workerChannels = new ArrayList<>();

    public AlarmOutputPlugin() { this(false); }
    private AlarmOutputPlugin(boolean overlayInstance) { this.overlayInstance = overlayInstance; }

    @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
        this.binding = binding;
        channel = new MethodChannel(binding.getBinaryMessenger(), "almost_there/alarm_output");
        channel.setMethodCallHandler(this);
        if (!overlayInstance) synchronized (workerChannels) { workerChannels.add(channel); }
    }

    @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
        if (!overlayInstance) synchronized (workerChannels) { workerChannels.remove(channel); }
        channel.setMethodCallHandler(null);
    }

    @Override public void onAttachedToActivity(ActivityPluginBinding binding) {
        activityBinding = binding;
        binding.addActivityResultListener(this);
        if (binding.getActivity() instanceof LockScreenAlarmActivity) {
            synchronized (workerChannels) { workerChannels.remove(channel); }
            // A notification tap can replace an already-visible overlay.
            hideOverlay();
        }
    }

    @Override public void onDetachedFromActivityForConfigChanges() { detachActivity(); }
    @Override public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }
    @Override public void onDetachedFromActivity() { detachActivity(); }

    private void detachActivity() {
        if (activityBinding != null) activityBinding.removeActivityResultListener(this);
        activityBinding = null;
        if (audioPickerResult != null) {
            audioPickerResult.error("picker_closed", "Audio picker was closed.", null);
            audioPickerResult = null;
        }
    }

    @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        try {
            if (call.method.equals("stop")) {
                String owner = call.argument("owner");
                if (owner == null || owner.equals(playbackOwner)) stop();
                result.success(null); return;
            }
            if (call.method.equals("hideAlarmTask")) {
                if (activityBinding != null) activityBinding.getActivity().moveTaskToBack(true);
                result.success(null); return;
            }
            if (call.method.equals("showAlarmOverlay")) {
                Context context = binding.getApplicationContext();
                KeyguardManager keyguard = (KeyguardManager) context.getSystemService(Context.KEYGUARD_SERVICE);
                // The alarm notification owns lock-screen presentation in its
                // dedicated task. Never bring the main UI forward here.
                if (keyguard != null && keyguard.isKeyguardLocked()) {
                    result.success(true); return;
                }
                if (!Settings.canDrawOverlays(context)) {
                    result.success(false); return;
                }
                showOverlay(context, call.arguments);
                result.success(true); return;
            }
            if (call.method.equals("hideAlarmOverlay")) {
                hideOverlay();
                finishLockScreenAlarm();
                result.success(null); return;
            }
            if (call.method.equals("dismissOverlay")) {
                dismissOverlay(call.argument("id"));
                finishLockScreenAlarm();
                ((NotificationManager) binding.getApplicationContext()
                    .getSystemService(Context.NOTIFICATION_SERVICE)).cancel(4201);
                result.success(null); return;
            }
            if (call.method.equals("showAlarmNotification")) {
                Context context = binding.getApplicationContext();
                String route = "/alarm?data=" + Uri.encode(new JSONObject((Map) call.arguments).toString());
                Intent intent = new Intent(context, LockScreenAlarmActivity.class)
                    .putExtra("alarm_route", route)
                    .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
                PendingIntent pending = PendingIntent.getActivity(context, 4201, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
                Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                    ? new Notification.Builder(context, "arrival_alarm_silent_v1")
                    : new Notification.Builder(context);
                int icon = context.getResources().getIdentifier("ic_stat_arrival", "drawable", context.getPackageName());
                builder.setSmallIcon(icon != 0 ? icon : android.R.drawable.ic_lock_idle_alarm)
                    .setContentTitle(call.argument("name") + "에 다왔어요")
                    .setContentText("목적지에 도착했어요. 알람을 밀어서 종료해주세요.")
                    .setCategory(Notification.CATEGORY_ALARM)
                    .setPriority(Notification.PRIORITY_MAX)
                    .setVisibility(Notification.VISIBILITY_PUBLIC)
                    .setOngoing(true).setAutoCancel(false)
                    .setContentIntent(pending);
                KeyguardManager keyguard = (KeyguardManager) context.getSystemService(Context.KEYGUARD_SERVICE);
                if (keyguard != null && keyguard.isKeyguardLocked()) {
                    builder.setFullScreenIntent(pending, true);
                }
                ((NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE))
                    .notify(4201, builder.build());
                result.success(null); return;
            }
            if (call.method.equals("canFullScreen")) {
                NotificationManager manager = (NotificationManager) binding.getApplicationContext()
                    .getSystemService(Context.NOTIFICATION_SERVICE);
                result.success(Build.VERSION.SDK_INT < 34 || manager.canUseFullScreenIntent());
                return;
            }
            if (call.method.equals("pickAudioFile")) {
                if (activityBinding == null) {
                    result.error("picker_unavailable", "Audio selection requires an active screen.", null);
                    return;
                }
                if (audioPickerResult != null) {
                    result.error("picker_busy", "Audio picker is already open.", null);
                    return;
                }
                Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);
                intent.setType("audio/*");
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                audioPickerResult = result;
                activityBinding.getActivity().startActivityForResult(intent, PICK_AUDIO_REQUEST);
                return;
            }
            if (!call.method.equals("start")) { result.notImplemented(); return; }
            String assetPath = call.argument("asset");
            String filePath = call.argument("filePath");
            if (assetPath == null && filePath == null) {
                result.error("missing_audio", "An asset or file path is required.", null); return;
            }
            stop();
            playbackOwner = call.argument("owner");
            Context context = binding.getApplicationContext();
            audio = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
            boolean earphones = Boolean.TRUE.equals(call.argument("earphones"));
            AudioDeviceInfo target = null;
            for (AudioDeviceInfo device : audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
                if (earphones ? isHeadphone(device) : device.getType() == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) {
                    target = device; break;
                }
            }
            if (target == null) { result.success(false); return; }
            final int token = generation;
            playbackContext = context;
            noisyReceiver = new BroadcastReceiver() {
                @Override public void onReceive(Context ignored, Intent intent) { stop(); }
            };
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(noisyReceiver, new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), Context.RECEIVER_NOT_EXPORTED);
            } else {
                context.registerReceiver(noisyReceiver, new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY));
            }
            final MediaPlayer output = new MediaPlayer();
            player = output;
            final double volume = Math.max(0, Math.min(1, ((Number)call.argument("volume")).doubleValue()));
            final int fadeMs = Math.max(0, ((Number)call.argument("fadeSeconds")).intValue() * 1000);
            final AudioAttributes outputAttributes = new AudioAttributes.Builder()
                // Earphone alarms use the media route.  Alarm usage is often
                // forced to the handset speaker by Android and Bluetooth ROMs.
                .setUsage(earphones ? AudioAttributes.USAGE_MEDIA : AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build();
            requestAlarmAudioFocus();
            if (earphones) prepareEarphoneMediaVolume(volume);
            output.setAudioAttributes(outputAttributes);
            // Start muted: setPreferredDevice is a preference, not a routing guarantee.
            output.setVolume(0f, 0f);
            final long started = android.os.SystemClock.elapsedRealtime();
            if (earphones) {
                final int targetId = target.getId();
                deviceCallback = new AudioDeviceCallback() {
                    @Override public void onAudioDevicesRemoved(AudioDeviceInfo[] removed) {
                        for (AudioDeviceInfo device : removed) if (device.getId() == targetId) stop();
                    }
                };
                audio.registerAudioDeviceCallback(deviceCallback, handler);
            }
            if (filePath != null) {
                output.setDataSource(filePath);
            } else {
                String key = binding.getFlutterAssets().getAssetFilePathByName(assetPath);
                try (AssetFileDescriptor asset = context.getAssets().openFd(key)) {
                    output.setDataSource(asset.getFileDescriptor(), asset.getStartOffset(), asset.getLength());
                }
            }
            output.setLooping(true);
            output.setOnErrorListener((mp, what, extra) -> { stop(); return true; });
            output.prepare();
            // In normal sound mode, prefer the handset speaker even when an
            // earphone is connected. Unlike the old implementation we never
            // mute based on the transient routed-device id afterwards.
            if (!earphones) output.setPreferredDevice(target);
            // Earphone mode uses Android's normal media route; a connected
            // headset is its default output.
            output.start();
            handler.post(new Runnable() {
                @Override public void run() {
                    if (token != generation || player != output) return;
                    long elapsed = android.os.SystemClock.elapsedRealtime() - started;
                    double progress = fadeMs == 0 ? 1 : Math.min(1d, (double)elapsed / fadeMs);
                    float gain = (float)(volume * progress);
                    output.setVolume(gain, gain);
                    if (earphones) updateEarphoneMediaVolume(progress);
                    handler.postDelayed(this, 50);
                }
            });
            result.success(true);
        } catch (Exception error) { stop(); result.error("audio_output", error.getMessage(), null); }
    }

    @Override public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != PICK_AUDIO_REQUEST) return false;
        MethodChannel.Result result = audioPickerResult;
        audioPickerResult = null;
        if (result == null) return true;
        if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
            result.success(null);
            return true;
        }
        try {
            Uri source = data.getData();
            Context context = binding.getApplicationContext();
            File mediaDirectory = new File(context.getFilesDir(), "alarm_media");
            if (!mediaDirectory.exists() && !mediaDirectory.mkdirs()) {
                throw new java.io.IOException("Could not create alarm media directory.");
            }
            String name = "alarm_sound";
            Cursor cursor = context.getContentResolver().query(source, null, null, null, null);
            if (cursor != null) {
                try {
                    int column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                    if (cursor.moveToFirst() && column >= 0 && cursor.getString(column) != null) name = cursor.getString(column);
                } finally { cursor.close(); }
            }
            // Keep the familiar file name in app storage. Add a suffix only
            // when the user deliberately imports a same-named file again.
            name = name.replaceAll("[\\\\/:*?\"<>|]", "_");
            if (name.length() == 0) name = "alarm_sound.audio";
            File destination = new File(mediaDirectory, name);
            if (destination.exists()) {
                int dot = name.lastIndexOf('.');
                String base = dot > 0 ? name.substring(0, dot) : name;
                String ext = dot > 0 ? name.substring(dot) : ".audio";
                destination = new File(mediaDirectory, base + " (" + System.currentTimeMillis() + ")" + ext);
            }
            try (InputStream input = context.getContentResolver().openInputStream(source);
                 FileOutputStream output = new FileOutputStream(destination)) {
                if (input == null) throw new java.io.IOException("Could not read selected audio.");
                byte[] buffer = new byte[8192];
                int count;
                while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            }
            result.success(destination.getAbsolutePath());
        } catch (Exception error) {
            result.error("audio_copy_failed", error.getMessage(), null);
        }
        return true;
    }

    private static void showOverlay(Context context, Object payload) {
        handler.post(() -> {
            if (overlayView != null) return;
            try {
                FlutterLoader loader = FlutterInjector.instance().flutterLoader();
                loader.startInitialization(context);
                loader.ensureInitializationComplete(context, null);
                FlutterEngine engine = new FlutterEngine(context);
                overlayEngine = engine;
                // The engine automatically registers plugins. Replace this
                // instance so the overlay never joins the worker channel list.
                engine.getPlugins().remove(AlarmOutputPlugin.class);
                engine.getPlugins().add(new AlarmOutputPlugin(true));
                String payloadJson = new JSONObject((Map) payload).toString();
                engine.getNavigationChannel().setInitialRoute("/alarm?data=" + Uri.encode(payloadJson));
                DartExecutor.DartEntrypoint entrypoint = new DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(), null, "overlayMain"
                );
                engine.getDartExecutor().executeDartEntrypoint(entrypoint);

                // Preserve the surface configuration used for the visible UI.
                FlutterSurfaceView surface = new FlutterSurfaceView(context);
                surface.setZOrderOnTop(true);
                final boolean debugOverlay = (context.getApplicationInfo().flags
                    & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
                FlutterView view = new FlutterView(context, surface) {
                    @Override public boolean dispatchTouchEvent(MotionEvent event) {
                        boolean handled = super.dispatchTouchEvent(event);
                        if (debugOverlay && (event.getActionMasked() == MotionEvent.ACTION_DOWN
                            || event.getActionMasked() == MotionEvent.ACTION_UP)) {
                            Log.d(TAG, "Android pointer action=" + event.getActionMasked()
                                + " handled=" + handled);
                        }
                        return handled;
                    }
                };
                view.attachToFlutterEngine(engine);
                WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                        | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                        | WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                    PixelFormat.TRANSLUCENT
                );
                params.gravity = Gravity.CENTER;
                params.setTitle("AlmostThereAlarmOverlay");
                WindowManager manager = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
                overlayWindowManager = manager;
                overlayView = view;
                manager.addView(view, params);
                // No FlutterActivity exists to forward lifecycle events for
                // this window. Enable frame scheduling on its own engine.
                engine.getLifecycleChannel().appIsResumed();
            } catch (Exception error) {
                Log.e(TAG, "Could not show the alarm overlay", error);
                hideOverlay();
            }
        });
    }

    private static View createAlarmOverlayView(Context context, Map payload) {
        String destinationId = String.valueOf(payload.get("id"));
        String destinationName = String.valueOf(payload.get("name"));
        FrameLayout root = new FrameLayout(context);
        root.setBackground(new GradientDrawable(
            GradientDrawable.Orientation.TL_BR, overlayColors(payload)
        ));

        TextView badge = text(context, "다왔어  ·  도착 알림", 16, Color.WHITE);
        badge.setGravity(Gravity.CENTER);
        FrameLayout.LayoutParams badgeParams = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, dp(context, 42), Gravity.TOP | Gravity.CENTER_HORIZONTAL
        );
        badgeParams.topMargin = dp(context, 54);
        root.addView(badge, badgeParams);

        TextView message = text(context, "눈 떠요, 거의 다왔어요", 17, 0xFFE4E3D8);
        message.setGravity(Gravity.CENTER);
        FrameLayout.LayoutParams messageParams = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER_HORIZONTAL | Gravity.CENTER_VERTICAL
        );
        messageParams.bottomMargin = dp(context, 126);
        root.addView(message, messageParams);

        TextView title = text(context, destinationName, 48, Color.WHITE);
        title.setGravity(Gravity.CENTER);
        title.setMaxLines(3);
        FrameLayout.LayoutParams titleParams = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER_HORIZONTAL | Gravity.CENTER_VERTICAL
        );
        titleParams.leftMargin = dp(context, 24);
        titleParams.rightMargin = dp(context, 24);
        titleParams.topMargin = dp(context, 24);
        root.addView(title, titleParams);

        String time = new SimpleDateFormat("HH:mm", Locale.KOREA).format(new Date());
        TextView clock = text(context, time, 27, Color.WHITE);
        clock.setGravity(Gravity.CENTER);
        FrameLayout.LayoutParams clockParams = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER_HORIZONTAL | Gravity.CENTER_VERTICAL
        );
        clockParams.topMargin = dp(context, 148);
        root.addView(clock, clockParams);

        FrameLayout slider = new FrameLayout(context);
        GradientDrawable sliderBackground = new GradientDrawable();
        sliderBackground.setColor(0x44000000);
        sliderBackground.setCornerRadius(dp(context, 40));
        slider.setBackground(sliderBackground);
        FrameLayout.LayoutParams sliderParams = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, dp(context, 76), Gravity.BOTTOM
        );
        sliderParams.leftMargin = dp(context, 24);
        sliderParams.rightMargin = dp(context, 24);
        sliderParams.bottomMargin = dp(context, 38);
        root.addView(slider, sliderParams);

        TextView hint = text(context, "밀어서 알람 종료", 15, Color.WHITE);
        hint.setGravity(Gravity.CENTER);
        FrameLayout.LayoutParams hintParams = new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT
        );
        hintParams.leftMargin = dp(context, 62);
        hintParams.rightMargin = dp(context, 18);
        slider.addView(hint, hintParams);

        TextView thumb = text(context, "›", 42, Color.WHITE);
        thumb.setGravity(Gravity.CENTER);
        GradientDrawable thumbBackground = new GradientDrawable();
        thumbBackground.setShape(GradientDrawable.OVAL);
        thumbBackground.setColor(0xFFFF6900);
        thumb.setBackground(thumbBackground);
        FrameLayout.LayoutParams thumbParams = new FrameLayout.LayoutParams(dp(context, 62), dp(context, 62));
        thumbParams.leftMargin = dp(context, 7);
        thumbParams.gravity = Gravity.CENTER_VERTICAL | Gravity.START;
        slider.addView(thumb, thumbParams);

        final float[] startX = new float[1];
        slider.setOnTouchListener((ignored, event) -> {
            int track = slider.getWidth() - dp(context, 76);
            if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
                startX[0] = event.getX();
                return true;
            }
            if (event.getActionMasked() == MotionEvent.ACTION_MOVE) {
                int offset = (int) Math.max(0, Math.min(track, event.getX() - startX[0]));
                FrameLayout.LayoutParams current = (FrameLayout.LayoutParams) thumb.getLayoutParams();
                current.leftMargin = dp(context, 7) + offset;
                thumb.setLayoutParams(current);
                return true;
            }
            if (event.getActionMasked() == MotionEvent.ACTION_UP || event.getActionMasked() == MotionEvent.ACTION_CANCEL) {
                float moved = event.getX() - startX[0];
                if (moved >= track * .62f) {
                    dismissOverlay(destinationId);
                } else {
                    FrameLayout.LayoutParams current = (FrameLayout.LayoutParams) thumb.getLayoutParams();
                    current.leftMargin = dp(context, 7);
                    thumb.setLayoutParams(current);
                }
                return true;
            }
            return true;
        });
        return root;
    }

    private static TextView text(Context context, String value, float size, int color) {
        TextView view = new TextView(context);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        return view;
    }

    private static int[] overlayColors(Map payload) {
        Object raw = payload.get("gradientColors");
        if (raw instanceof List && ((List) raw).size() >= 2) {
            List values = (List) raw;
            int[] colors = new int[values.size()];
            for (int index = 0; index < values.size(); index++) {
                Object value = values.get(index);
                colors[index] = value instanceof Number ? ((Number) value).intValue() : 0xFF384838;
            }
            return colors;
        }
        return new int[] {0xFF384838, 0xFF94744B, 0xFFE68A4D};
    }

    private static int dp(Context context, float value) {
        return (int) (value * context.getResources().getDisplayMetrics().density + .5f);
    }

    private static void hideOverlay() {
        Runnable close = () -> {
            final WindowManager manager = overlayWindowManager;
            final View view = overlayView;
            final FlutterEngine engine = overlayEngine;
            overlayWindowManager = null;
            overlayView = null;
            overlayEngine = null;
            if (view != null) {
                try { view.setVisibility(View.GONE); } catch (Exception ignored) {}
            }
            // Remove from WindowManager first. This immediately destroys the
            // Android input channel, so an invisible overlay cannot intercept
            // any touches while Flutter releases its render surface.
            if (manager != null && view != null) {
                try { manager.removeViewImmediate(view); } catch (Exception ignored) {}
            }
            if (view instanceof FlutterView) {
                try { ((FlutterView) view).detachFromFlutterEngine(); } catch (Exception ignored) {}
            }
            if (engine != null) {
                try { engine.getLifecycleChannel().appIsDetached(); } catch (Exception error) {
                    Log.w(TAG, "Could not detach overlay lifecycle", error);
                }
                try { engine.destroy(); } catch (Exception ignored) {}
            }
        };
        if (Looper.myLooper() == Looper.getMainLooper()) close.run();
        else handler.post(close);
    }

    private void finishLockScreenAlarm() {
        if (activityBinding != null && activityBinding.getActivity() instanceof LockScreenAlarmActivity) {
            Activity activity = activityBinding.getActivity();
            handler.post(activity::finishAndRemoveTask);
        }
    }

    private static void dismissOverlay(String id) {
        stop();
        Map<String, Object> args = new HashMap<>();
        args.put("id", id);
        synchronized (workerChannels) {
            for (MethodChannel worker : workerChannels) {
                try { worker.invokeMethod("overlayDismiss", args); } catch (Exception ignored) {}
            }
        }
        hideOverlay();
    }

    private static boolean isHeadphone(AudioDeviceInfo device) {
        int type = device.getType();
        return type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || type == AudioDeviceInfo.TYPE_WIRED_HEADSET
            || type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
            || type == AudioDeviceInfo.TYPE_USB_HEADSET
            || (Build.VERSION.SDK_INT >= 31 && (type == AudioDeviceInfo.TYPE_BLE_HEADSET
                || type == AudioDeviceInfo.TYPE_BLE_SPEAKER));
    }

    private static void stop() {
        generation++;
        playbackOwner = null;
        abandonAlarmAudioFocus();
        restoreEarphoneMediaVolume();
        if (player != null) {
            try { player.setVolume(0f, 0f); player.stop(); } catch (Exception ignored) {}
            player.release(); player = null;
        }
        if (audio != null && deviceCallback != null) audio.unregisterAudioDeviceCallback(deviceCallback);
        deviceCallback = null;
        if (playbackContext != null && noisyReceiver != null) {
            try { playbackContext.unregisterReceiver(noisyReceiver); } catch (Exception ignored) {}
        }
        noisyReceiver = null;
        playbackContext = null;
    }

    /**
     * Requests exclusive transient focus so compliant players such as YouTube
     * Music and Spotify pause instead of mixing with the arrival alarm.
     */
    private static void requestAlarmAudioFocus() {
        if (audio == null) return;
        abandonAlarmAudioFocus();
        audioFocusListener = change -> {
            if (change == AudioManager.AUDIOFOCUS_LOSS) stop();
        };
        int result;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            AudioAttributes focusAttributes = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build();
            audioFocusRequest = new AudioFocusRequest.Builder(
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
            ).setAudioAttributes(focusAttributes)
                .setWillPauseWhenDucked(true)
                .setAcceptsDelayedFocusGain(false)
                .setOnAudioFocusChangeListener(audioFocusListener, handler)
                .build();
            result = audio.requestAudioFocus(audioFocusRequest);
        } else {
            result = audio.requestAudioFocus(
                audioFocusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
            );
        }
        if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            Log.w(TAG, "Alarm audio focus was not granted; continuing alarm output");
        }
    }

    private static void abandonAlarmAudioFocus() {
        if (audio == null) return;
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusRequest != null) {
                audio.abandonAudioFocusRequest(audioFocusRequest);
            } else if (audioFocusListener != null) {
                audio.abandonAudioFocus(audioFocusListener);
            }
        } catch (Exception ignored) {}
        audioFocusRequest = null;
        audioFocusListener = null;
    }

    private static void prepareEarphoneMediaVolume(double setting) {
        if (audio == null) return;
        int maximum = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
        int current = audio.getStreamVolume(AudioManager.STREAM_MUSIC);
        if (maximum <= 0) return;
        previousMediaVolume = current;
        // 100% maps to 40% of Android's stream range: 60 on Samsung's
        // commonly displayed 0–150 media scale. The audio file is unmodified.
        targetMediaVolume = (int) Math.ceil(maximum * .40d * setting);
        if (setting > 0 && targetMediaVolume == 0) targetMediaVolume = 1;
        targetMediaVolume = Math.min(maximum, targetMediaVolume);
        appliedMediaVolume = current;
        mediaVolumeAdjusted = targetMediaVolume != current;
    }

    private static void updateEarphoneMediaVolume(double progress) {
        if (audio == null || !mediaVolumeAdjusted || previousMediaVolume < 0 || targetMediaVolume < 0) return;
        int step = previousMediaVolume + (int) Math.round((targetMediaVolume - previousMediaVolume) * progress);
        if (step == appliedMediaVolume) return;
        try {
            audio.setStreamVolume(AudioManager.STREAM_MUSIC, step, 0);
            appliedMediaVolume = step;
        } catch (Exception ignored) {}
    }

    private static void restoreEarphoneMediaVolume() {
        if (audio != null && mediaVolumeAdjusted && previousMediaVolume >= 0) {
            try { audio.setStreamVolume(AudioManager.STREAM_MUSIC, previousMediaVolume, 0); } catch (Exception ignored) {}
        }
        previousMediaVolume = -1;
        targetMediaVolume = -1;
        appliedMediaVolume = -1;
        mediaVolumeAdjusted = false;
    }

}
