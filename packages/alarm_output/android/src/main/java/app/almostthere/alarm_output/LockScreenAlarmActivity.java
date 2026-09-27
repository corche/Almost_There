package app.almostthere.alarm_output;

import android.os.Build;
import android.os.Bundle;
import android.view.WindowManager;
import io.flutter.embedding.android.FlutterActivity;

/** A separate task hosting the same Flutter alarm screen as the overlay. */
public final class LockScreenAlarmActivity extends FlutterActivity {
    @Override public String getDartEntrypointFunctionName() { return "overlayMain"; }

    @Override public String getInitialRoute() {
        return getIntent().getStringExtra("alarm_route");
    }

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true);
            setTurnScreenOn(true);
        } else {
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON);
        }
    }

    // The slider owns dismissal; Back must not leave an invisible ringing alarm.
    @Override public void onBackPressed() {}
}
