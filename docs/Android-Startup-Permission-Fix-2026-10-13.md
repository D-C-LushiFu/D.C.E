# Android startup and storage repair — 2026-10-13

## Reproduction and cause

Device: Redmi K70 (23113RKC6C), Android 16, ADB serial 45f36a1d.
Package: com.DCEEngine, version 1.2.2.

The installed build crashed both after granting all-files access and when
reopened with that permission already granted. AppOps reported the grant as
`allow`. `/sdcard/.DCE/crash/` existed and contained a native crash report.

The native report recorded SIGSEGV at address `0x278`. The faulting libMain
offset `0x21e2ad4` maps to `Main.setupGame()`: its object-code function size and
instruction at relative offset `0x8bc` match the linked code. That instruction
dereferenced `FlxG.game` before a FlxGame had been constructed.

The premature call came from the Android identity check. Android reports the
display label `D.C.E.`, while the check compared it with application metadata
`file = DCE`. The display-label metadata is `name = D.C.E.`. This mismatch
triggered `FlxG.switchState(new PirateState())` during bootstrap.

Evidence: `_build/android-permission-crash/native-crash-original.txt`,
`app-logcat-before.txt`, `exit-info-before.txt`, and `startup-again.png`.

## Changes

- Compare the installed display label with metadata `name`.
- On identity-check failure, select PirateState as the initial state instead
  of switching through the uninitialized FlxG.game. Signature and package
  checks remain active.
- Wait for an actual permission grant before accessing external storage.
  Returning without permission leaves a tappable explanation and retry action.
- Put early diagnostics in the app-private storage directory; select the
  external crash directory after successful storage initialization.
- Default runtime directory:
  `/storage/emulated/0/D.C.Fantasy Land/Different Creatingness Engine/`.
- Keep an optional separate versioned workspace under the same container.
  Folder preferences now live inside `D.C.Fantasy Land/.dce_storage_config`.
  Existing hidden folders and their files are left in place.
- Check that the destination is a directory and can actually be written to
  before changing the working directory. A failure reports its path and reason.
- Retain the mobile DebugMonitor overlay being disabled.

## Validation

- Release APK: `_release/D.C.E-Android-Update.apk`, 491285986 bytes;
  SHA256 `675181F2455674A8FCF732D1D25FA837130F710BE95BD32417CB413FBFF3D39B`.
- Installed as an update on Redmi K70 (45f36a1d), Android 16. The corrected
  APK is also in `/sdcard/Download/D.C.E-Android-Update.apk`. No uninstall or
  data reset of the formal engine or NF was performed.
- Denied permission leaves a Chinese/English waiting screen. Touch retry
  opens permission settings; granting access resumes the same process and
  selects the requested nested external directory. Evidence:
  `final-permission-cn-confirmed.png`, `final-permission-retry-cn.png`,
  `final-permission-flow-logcat.txt` under `_build/android-permission-crash`.
- Restored the prior Phigros Freeplay implementation by merging source changes
  and adding its missing background video. Visible song/difficulty selection
  and spectrum evidence: `freeplay-restored-confirm.png`, `freeplay-touch-song.png`.
- Chart Editor fits the landscape canvas. Touch opens/closes history; adding
  one BF note, top-bar undo, and redo visibly change the note count 1/0/1.
  The test note was undone before exit. Evidence: `chart-history-note-touch.png`,
  `chart-touch-undo.png`, `chart-touch-redo.png`, `chart-touch-clean.png`.
- No claim of a complete editor regression: other editor paths and the
  restored Freeplay return route remain outside the completed Android checks.
- Drawing-cap counters responded to exact 30, 60, 90, 120 and 206 settings.
  This is engine rendering evidence, not proof of physical screen presentation.
  The remaining 60Hz issue is documented in `Android-Refresh-Rate-Audit-2026-10-13.md`.
- Current formal PID 32635 has no fatal signal or Java fatal exception in
  `final-current-logcat.txt`. Windows was not rebuilt with this Freeplay merge.
