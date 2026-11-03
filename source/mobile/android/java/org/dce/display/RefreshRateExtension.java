package org.dce.display;

import android.os.Build;
import android.util.Log;
import android.view.Display;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import java.util.WeakHashMap;
import org.haxe.extension.Extension;

/** Display requests belong to this app window and do not change system settings. */
public class RefreshRateExtension extends Extension {
    private static int targetFrameRate = 60;
    private static float surfaceFrameRate = 60;
    private static final WeakHashMap<SurfaceView, Boolean> watched = new WeakHashMap<>();

    public static void setTargetFrameRate(int framesPerSecond) {
        targetFrameRate = Math.max(24, framesPerSecond);
        if (mainActivity != null) mainActivity.runOnUiThread(RefreshRateExtension::apply);
    }

    @Override public void onResume() {
        if (mainActivity != null) mainActivity.runOnUiThread(RefreshRateExtension::apply);
    }

    private static void apply() {
        if (mainActivity == null || Build.VERSION.SDK_INT < 23) return;
        try {
            Display display = mainActivity.getWindowManager().getDefaultDisplay();
            Display.Mode current = display.getMode();
            Display.Mode selected = null;
            Display.Mode fastest = current;
            for (Display.Mode mode : display.getSupportedModes()) {
                if (mode.getPhysicalWidth() != current.getPhysicalWidth()
                        || mode.getPhysicalHeight() != current.getPhysicalHeight()) continue;
                if (mode.getRefreshRate() > fastest.getRefreshRate()) fastest = mode;
                if (mode.getRefreshRate() + 0.5f >= targetFrameRate
                        && (selected == null || mode.getRefreshRate() < selected.getRefreshRate())) selected = mode;
            }
            if (selected == null) selected = fastest;
            surfaceFrameRate = Math.min(targetFrameRate, selected.getRefreshRate());
            WindowManager.LayoutParams attributes = mainActivity.getWindow().getAttributes();
            attributes.preferredDisplayModeId = selected.getModeId();
            attributes.preferredRefreshRate = selected.getRefreshRate();
            mainActivity.getWindow().setAttributes(attributes);
            // SDL can replace its layout after orientation or native startup.
            // Traverse the attached window rather than a cached Extension view.
            visit(mainActivity.getWindow().getDecorView());
            Log.i("DCE-Display", "renderCap=" + targetFrameRate + " requestedMode="
                    + selected.getModeId() + " refresh=" + selected.getRefreshRate()
                    + " current=" + display.getRefreshRate());
        } catch (Exception error) {
            Log.w("DCE-Display", "Could not request display refresh rate", error);
        }
    }

    private static void visit(View view) {
        if (view instanceof SurfaceView) {
            SurfaceView surfaceView = (SurfaceView)view;
            if (Build.VERSION.SDK_INT >= 35) surfaceView.setRequestedFrameRate(surfaceFrameRate);
            if (!watched.containsKey(surfaceView)) {
                watched.put(surfaceView, true);
                surfaceView.getHolder().addCallback(new SurfaceHolder.Callback() {
                    @Override public void surfaceCreated(SurfaceHolder holder) { requestSurface(holder.getSurface()); }
                    @Override public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
                        requestSurface(holder.getSurface());
                    }
                    @Override public void surfaceDestroyed(SurfaceHolder holder) {}
                });
            }
            requestSurface(surfaceView.getHolder().getSurface());
        }
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup)view;
            for (int index = 0; index < group.getChildCount(); index++) visit(group.getChildAt(index));
        }
    }

    private static void requestSurface(Surface surface) {
        if (Build.VERSION.SDK_INT < 30 || surface == null || !surface.isValid()) return;
        if (Build.VERSION.SDK_INT >= 31)
            surface.setFrameRate(surfaceFrameRate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                    Surface.CHANGE_FRAME_RATE_ALWAYS);
        else surface.setFrameRate(surfaceFrameRate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT);
        Log.i("DCE-Display", "surfaceFrameRate=" + surfaceFrameRate);
    }
}
