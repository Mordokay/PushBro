# CLAUDE.md

iOS pushup-counter app (SwiftUI + SwiftData + ARKit). The phone lies on the floor under the user's chest; the front TrueDepth camera measures face distance and a state machine counts reps. See README.md for the product/architecture overview.

## Building & testing

The pbxproj is objectVersion 110 (Xcode 27 beta format). The default CLI Xcode (26.x) **cannot read it** — always prefix with `DEVELOPER_DIR`:

```sh
cd PushBro
DEVELOPER_DIR=/Applications/Xcode-beta.app xcodebuild \
  -project PushBro.xcodeproj -scheme PushBro \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

- Targets: `PushBro` (app), `PushBroTests` (unit tests, Swift Testing, hosted in the app), `PushBro Watch App` (watchOS companion, embedded via "Embed Watch Content"; its Info.plist lives at `Configs/PushBroWatch-Info.plist` — files named Info.plist inside filesystem-synchronized groups collide with the generated plist).
- Watch app: `HKWorkoutSession` + `workout-processing` background mode keep it alive during pushups; WCSession relays live HR/reps and the final summary; the watch saves the Health workout itself, so the phone skips its save when a watch session ran (`pendingWatchSession` flow in WorkoutView).
- The project uses filesystem-synchronized groups: new `.swift` files under `PushBro/PushBro/` are picked up automatically — no pbxproj edits needed for new files.
- The user runs the GUI from Xcode-beta; if it's open, it may canonicalize pbxproj edits.

## Build settings that bite

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — every type is MainActor unless marked `nonisolated` (e.g. `Log`, `AppLogger`, ARKit delegate callbacks).
- `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` — each file must explicitly import any module whose members it uses (`import SwiftData` for `.modelContainer`, etc.). SourceKit lags badly on fresh files and shows phantom "cannot find type" errors — trust `xcodebuild`, not the inline diagnostics.
- Deployment target iOS 26.0. Portrait-only. Permission strings live as `INFOPLIST_KEY_*` build settings in the pbxproj.

## Architecture rules

- **`DetectionCore/` stays pure**: no framework imports, no clocks, no logging. All timing comes from sample timestamps so tests replay canned traces deterministically (`PushBroTests/DetectionCoreTests.swift` builds synthetic 60 Hz traces). If you change the FSM, extend those replay tests.
- **`WorkoutEngine` consumes rep events, not camera frames.** Camera mode: `FaceDistanceProvider → DistanceSmoother → RepCounterStateMachine → CameraWorkoutController → engine.recordRep()`. Tap mode calls `recordRep()` directly. Anything downstream of the engine must work identically for both modes.
- Distance providers (preference order in `FaceDistanceProviderFactory`): `TrueDepthDistanceProvider` (raw AVFoundation depth map, 10th-percentile of central region — keep `isFilteringEnabled = false` so below-min-range frames read as nil instead of invented values), `ARFaceDistanceProvider` (ARKit fallback), `SimulatedFaceDistanceProvider` (Simulator).
- Set splitting is gap-based at rep time (`restThreshold` between reps), not timer-based.
- Settings are `@AppStorage` with keys centralized in `Models/AppSettings.swift` — never inline string keys.
- Logging goes through `Shared/Log.swift` (compiled into both the iOS and watch targets; `Log.calibration`, `Log.detection`, `Log.workout`, `Log.voice`, `Log.audio`, `Log.health`, `Log.data`, `Log.watch`, `Log.app`) with emoji levels 🟢 debug · 🔵 info · 🟡 warning · 🔴 error. Every line also appends to a rotating file (`LogFileStore`, ~2 MB + one previous, shareable from Settings → Diagnostics). Log state *transitions*, never per-frame data (samples arrive at 60 Hz). The `Shared/` synced folder is referenced by both app targets — put cross-platform code there.

## Gotchas learned the hard way

- Creating heavyweight objects (`AVSpeechSynthesizer`) inside a SwiftUI `View.init` **segfaults at app launch** — create them in `.onAppear`.
- `ARFaceAnchor.transform` is world-space; distance must be `simd_length(facePos − cameraPos)` per frame, never the anchor translation alone.
- The speaker and mic are centimeters apart on the floor: voice recognition must stay gated on `SpeechAnnouncer.isSpeaking` (+ echo tail) or TTS triggers commands.
- TrueDepth loses the face below ~15–20 cm; the FSM's "face lost while deep counts as bottom" rule depends on `deepFaceLossFraction` — don't remove it.
- `AVAudioSession` needs `.defaultToSpeaker` or TTS routes to the earpiece (inaudible from plank position).
- **Never use `if`/`else` inside a Swift Charts `Chart { }` content builder** — `_ConditionalContent<opaque ChartContent>` hits a runtime witness-table SIGSEGV the moment the chart lays out. Emit marks unconditionally with zero-height values (they render nothing) and ternaries in modifiers instead. Conditional *views* (e.g. inside `.annotation { }`) are fine.
- Debug launch hooks for Simulator automation (no tap access): `-seedData` populates demo workouts, `-openTab workout|history|stats|settings` selects the initial tab.

## Simulator workflow

- Camera mode in the Simulator uses `SimulatedFaceDistanceProvider` (synthetic pushup every 2 s, rest every 5 reps) — calibration and workouts are fully testable without hardware.
- Skip first-run friction: `xcrun simctl spawn <udid> defaults write com.greenSphereStudios.PushBro hasSeenTutorial -bool YES` and `voiceCommandsEnabled -bool NO` (speech-recognition TCC can't be granted via `simctl privacy`; a pending permission dialog survives relaunch and needs a simulator reboot to clear).
- Debug builds: "Seed" button in the History tab inserts demo data.
