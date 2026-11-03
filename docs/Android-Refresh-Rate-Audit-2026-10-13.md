# Android refresh-rate audit — 2026-10-13

## Status

**Unresolved: D.C.E. still displays at 60Hz on this Redmi K70.**
Current phone installation is the user-requested debug-audit APK, with D.C.E. selected for debugging. The original formal Update APK is retained separately.
The engine counter can report hundreds of render iterations while the
physical display remains 60Hz. Counter results must not be reported as a
successful 120FPS display regression.

## Same-device comparison

| Foreground application | Stable physical display mode | Current MIUI maximum vote |
|---|---:|---:|
| NF `com.NovaFlareEngine` | 120Hz | 120Hz |
| D.C.E. `com.DCEEngine` | 60Hz | 60Hz |
| Temporary D.C.E. `com.DCEEngineBackup1` | 60Hz | 60Hz |

D.C.E. requested 120Hz on both its Window and actual SDL SurfaceView.
`APP_REQUEST_BASE_MODE_REFRESH_RATE` was 120, but the higher-priority
`PRIORITY_MIUI_REFRESH_RATE` vote was capped at 60. NF and D.C.E. both target
SDK 36 and declare the game category. NF has enabled switches in the system
high-refresh list; both D.C.E. identities instead show “follow in-app settings”.
The exact condition causing this policy difference is not yet established.

Evidence under `_build/android-permission-crash`:

- NF: `nf-current.png`, `nf-sf.txt`, `nf-display.txt`,
  `nf-after-identity-stable-sf.txt` and `nf-after-identity-display.txt`.
- Formal D.C.E.: `dce-after-nf-sf.txt`, `dce-policy-live.txt`.
- Temporary identity: `probe-back-stable-sf.txt`,
  `probe-back-stable-display.txt`, `probe-back-stable-screen.png`.
- System UI: `nf-highrefresh-setting.png`, `dce-highrefresh-setting.png`,
  `identity-highrefresh-fresh.png`.

## NF snapshot comparison

Compared `E:/FNF-NovaFlare-Engine-1.2.1`, its Hotfix directory, the Desktop
`_nf121_base` tree, and the V1.2.0 tag's preference callbacks.
SDLWindow.cpp, SDLApplication.cpp and NativeApplication.hx match the E: NF
snapshot after normalizing line endings. Both projects disable VSync in
Project.xml. The current NF snapshot already separates update and render caps.
V1.2.0 assigned the TPS value to FlxG.drawFramerate in its TPS callback;
copying that callback would violate the user's requirement for an independent
render cap. No missing NF high-refresh bridge was found in the examined snapshot.

Two same-package diagnostic builds were tested: removing Window mode hints,
and disabling all new Java refresh requests to follow NF's original approach.
Both remained at 60Hz. Their generated changes were reverted, and the formal
APK was reinstalled. The category-only probe performed earlier also failed;
that result alone does not establish a category cause or exclude cached policy.

A temporary coexistence APK changed applicationId to the already-supported
Backup1 identity and forced its diagnostic display request to at least 120Hz.
Its engine rendered 120 iterations/sec but the stable physical mode remained
60Hz. The user explicitly approved all-files access for this test package.
ADB new-app installs were rejected by the phone installer; the user installed
it manually. It was subsequently uninstalled successfully, and package listing
confirmed only the formal D.C.E. remains. External engine/NF files were retained.

## Measurement boundary

A thermal 60Hz vote appeared in one temporary-package sample. Later stable
NF/probe comparisons had different MIUI votes with no current thermal vote;
temperature alone has not been established as the cause. Testing continued
as requested without waiting for cooling. No thermal protection, system optimization, global refresh preference, or system-app data was disabled/reset. A separate temporary global key `disable_game_default_frame_rate` was written and restored to absent. This was the wrong configuration to inspect: the actual developer-option property `debug.graphics.game_default_frame_rate.disabled` was already `true`. The temporary-key sample had Settings in the foreground and must not be interpreted as a D.C.E. refresh result.
SurfaceFlinger latency output had no usable samples; per-frame presentation
FPS was not measured. The physical refresh modes above are measured modes.

The formal package and generated manifest/Java/Gradle configuration are restored.
The temporary diagnostic does not change the final engine cap to a fixed 120.

## Debuggable application follow-up

At the user's request, a release-signed Android-debuggable diagnostic APK was
created at `_release/D.C.E-Android-DebugAudit.apk` and installed as an update.
The phone retains its existing app data, and its selected debug application is
`com.DCEEngine` with `wait_for_debugger=0`. The formal Update APK remains a
separate non-debuggable release artifact. Only generated build files gained
the diagnostic flag and a package-visibility query scoped to NF.

JDWP attached successfully. A breakpoint in RefreshRateExtension.apply verified
both application categories are 0 (game), NF target SDK is 36, D.C.E.'s target
render cap is 2000, and its preferred display mode is 2 (120Hz). A live
DecorView 120Hz request was also tried and did not remove the 60Hz limit.
The debugger was detached and all breakpoints and ADB forwards were removed.
The initial disconnection was an ordinary force-stop due to changing debug-app
selection, confirmed by `dce-process-exit-info.txt`, not a native crash.
Evidence: `jdwp-application-classification.txt` and `debugger-resumed-sf.txt`.

Direct APK comparison confirms NF and D.C.E. have the identical ARM64
`liblime.so` hash, prefix `8c46c853dafa6715`; D.C.E. additionally includes VLC.
Current media player/resource-manager records do not show an active D.C.E.
hardware decoder. VLC has not been established as the cause.

SurfaceFlinger TimeStats now provides actual presentation evidence:
`dce-timestats.txt` reports the D.C.E. SurfaceView at displayRefreshRate=60
and renderRate=60, with 4149 layer frames and predominantly 16ms rounded
present-to-present intervals. This supersedes the earlier no-sample latency
limitation for this sampled interval. Collection was then disabled.

The source of the MIUI 60Hz policy remains unresolved. Reading its protected
PowerKeeper configuration provider was denied to ADB shell, so those policy
records were not accessed. No high-refresh fix has been established by copying
NF callbacks, disabling the added bridge, using a fresh app identity, selecting
the app for debugging, or requesting a 120Hz root view.

Normal generated Gradle/manifest files were restored after saving the diagnostic variants; at this stage the phone retained the debug-audit installation for further debugging. That diagnostic APK SHA256: `BF5C23525750CF4AD16E094980325D384D6FDD207BAD5C8FB30A245299D6A9D5`.

## GC and both NF versions follow-up

See [Android GC and frame rate audit](Android-GC-Frame-Rate-Audit-2026-10-13.md) for the subsequent 180-second native GC sampling, both NF package presentation measurements, actual 24/120/2000 cap checks, and render-thread A/B. The newer NF includes the identical VLC library, correcting the scope of the older APK-only VLC comparison above. The phone now retains the separate GC-audit diagnostic update. The MIUI limit remains unresolved; no high-refresh fix is claimed.
