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
    private static float surfaceFrameRate = 0;
    private static final WeakHashMap<SurfaceView, Boolean> watched = new WeakHashMap<>();

    /** Keep the display at its fastest supported mode, independently of game FPS caps. */
    public static void requestMaximumRefreshRate() {
        if (mainActivity != null) mainActivity.runOnUiThread(RefreshRateExtension::apply);
    }

    /** The native window frame scheduler also needs a real supported display rate. */
    public static int getMaximumRefreshRate() {
        if (mainActivity == null || Build.VERSION.SDK_INT < 21) return 0;
        try {
            Display display = mainActivity.getWindowManager().getDefaultDisplay();
            float fastestRefreshRate = display.getRefreshRate();
            if (Build.VERSION.SDK_INT >= 23) {
                Display.Mode current = display.getMode();
                for (Display.Mode mode : display.getSupportedModes()) {
                    if (mode.getPhysicalWidth() != current.getPhysicalWidth()
                            || mode.getPhysicalHeight() != current.getPhysicalHeight()) continue;
                    if (mode.getRefreshRate() > fastestRefreshRate)
                        fastestRefreshRate = mode.getRefreshRate();
                }
            }
            return Math.round(fastestRefreshRate);
        } catch (Exception error) {
            Log.w("DCE-Display", "Could not read maximum display refresh rate", error);
            return 0;
        }
    }

    @Override public void onResume() {
        if (mainActivity != null) mainActivity.runOnUiThread(RefreshRateExtension::apply);
    }

    private static void apply() {
        if (mainActivity == null || Build.VERSION.SDK_INT < 21) return;
        try {
            Display display = mainActivity.getWindowManager().getDefaultDisplay();
            float fastestRefreshRate = display.getRefreshRate();
            Display.Mode fastestMode = null;
            if (Build.VERSION.SDK_INT >= 23) {
                Display.Mode current = display.getMode();
                for (Display.Mode mode : display.getSupportedModes()) {
                    if (mode.getPhysicalWidth() != current.getPhysicalWidth()
                            || mode.getPhysicalHeight() != current.getPhysicalHeight()) continue;
                    if (mode.getRefreshRate() > fastestRefreshRate) {
                        fastestRefreshRate = mode.getRefreshRate();
                        fastestMode = mode;
                    }
                }
            }
            surfaceFrameRate = fastestRefreshRate;
            WindowManager.LayoutParams attributes = mainActivity.getWindow().getAttributes();
            if (Build.VERSION.SDK_INT >= 23 && fastestMode != null)
                attributes.preferredDisplayModeId = fastestMode.getModeId();
            attributes.preferredRefreshRate = fastestRefreshRate;
            mainActivity.getWindow().setAttributes(attributes);
            // SDL can replace its layout after orientation or native startup.
            // Traverse the attached window rather than a cached Extension view.
            visit(mainActivity.getWindow().getDecorView());
            Log.i("DCE-Display", "requestedMaximumRefresh=" + fastestRefreshRate + " requestedMode="
                    + (fastestMode == null ? "preferredRefreshRate" : fastestMode.getModeId())
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
