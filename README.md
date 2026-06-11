# PushBro 💪

A hands-free pushup counter for iPhone. Put the phone flat on the floor under your face, screen up, and do pushups over it — the front TrueDepth camera measures the distance to your face and counts every rep. No touching, no guessing.

## How it works

1. **Calibrate once** — hold your *up* position (arms extended), then lower yourself while PushBro measures the descent. It records the lowest reliable distance as your *down* position and normalizes everything in between as *depth* (0 = up, 1 = down).
2. **Say "start"** (or press the self-timer Start button: 3/5/10 s) — a spoken countdown gives you time to get into position.
3. **Do pushups** — a rep counts when you cross the depth threshold and come back up. Each rep number is spoken aloud, so you never need to look at the screen. Partial reps are rejected.
4. **Rest a few seconds** and the session automatically splits into sets.
5. **Say "stop"** — no phantom reps while you stand up. The session is saved, with optional Apple Health logging.

The required rep depth is adjustable in Settings (Easy ≈ 60% of your range, Hard ≈ 90%).

## Features

- 📷 **Camera counting** via the raw TrueDepth depth map — measures whatever is overhead (face, chin, chest), no face recognition required; ARKit face tracking as fallback on devices without the depth sensor
- 👃 **Tap mode** fallback — nose-tap the screen on devices without face tracking
- 🗣️ **Voice start/stop** — on-device speech recognition, guarded against being triggered by the app's own voice
- 🔊 **Spoken rep counting** through the loudspeaker
- 📅 **History** — calendar heatmap against your daily goal, day drill-down to sessions and sets
- 📊 **Stats** — totals, best set, best day, longest session, average pace, current & best streak
- 🍎 **Apple Health** — sessions saved as functional strength workouts
- ⌚ **Apple Watch** — a companion watch app tracks live heart rate during workouts (an HKWorkoutSession keeps it running with the wrist down), shows reps on the wrist, draws a per-session heart-rate graph over the set timeline, and upgrades calories to watch-computed energy (fallback chain: watch energy → Keytel HR formula → Mifflin-St Jeor → weight-only METs)
- 🎓 Built-in tutorial (first launch, the `?` button, or Settings)

## Building

Requires the **Xcode 27 beta** toolchain (the project format is newer than Xcode 26.x understands). Deployment target: iOS 26.

```sh
cd PushBro
# Build + run all tests on a simulator
DEVELOPER_DIR=/Applications/Xcode-beta.app xcodebuild \
  -project PushBro.xcodeproj -scheme PushBro \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Camera mode needs a real device with face tracking (any Face ID iPhone). In the Simulator, a **simulated provider** generates an endless loop of synthetic pushups (one every 2 s, a rest every 5 reps) so the whole camera flow — calibration included — can be exercised without hardware.

Debug builds show a **Seed** wand in the History tab that inserts six weeks of demo data.

## Architecture

Three strictly separated layers:

| Layer | What lives there |
|---|---|
| **Pure logic** (`DetectionCore/`, `Stats/*Calculator`) | Rep-detection state machine, smoothing, threshold math, stats/streaks. No framework imports, no clocks — time comes from sample timestamps, so unit tests replay canned traces deterministically. |
| **Device adapters** (`Detection/`, `Audio/`, `Health/`) | Distance providers (TrueDepth depth map preferred, ARKit face tracking as fallback, a simulated one for the Simulator), speech recognizer, TTS announcer, audio session coordinator, HealthKit writer. Each behind a small protocol. |
| **UI + persistence** (`Workout/`, `History/`, `Settings/`, `Models/`) | SwiftUI views, the `@Observable` `WorkoutEngine`, SwiftData models. |

The key abstraction: **`WorkoutEngine` consumes rep events, not camera frames.** Camera mode feeds it through the detection pipeline (`provider → smoother → state machine`); tap mode feeds it screen taps. Sets, rest detection, persistence, spoken counting, Health logging, and the summary are identical in both modes.

### Rep detection in one paragraph

Distance samples are smoothed (median-of-5 + EMA), normalized to depth using the calibration, and fed to `RepCounterStateMachine`: `armed → descending → bottomReached → armed` emits a rep; going back up early rejects a partial; dwelling in the up zone (or losing the face) past the rest threshold emits a rest. Losing the face while already deep counts as reaching the bottom — at the bottom of a rep the chin often drops below the TrueDepth sensor's minimum range, and this rule rescues those reps.

## Logging

Everything important logs through `Support/Log.swift` (a thin wrapper over `os.Logger`), with scannable level emojis:

- 🟢 debug · 🔵 info · 🟡 warning · 🔴 error

Filter in Console.app by subsystem `com.greenSphereStudios.PushBro`; categories: `Calibration`, `Detection`, `Workout`, `Voice`, `Audio`, `Health`, `Data`, `App`. Calibration logs include sample counts and untracked-frame counts per measuring window — the first place to look when a capture fails.

## Project layout

```
PushBro/PushBro/
├── Models/          SwiftData models, calibration profile, settings keys
├── DetectionCore/   pure rep-detection logic (state machine, smoothing, config)
├── Detection/       ARKit / simulated face-distance providers
├── Audio/           audio session, TTS announcer, voice command listener
├── Workout/         engine, workout & calibration UI
├── History/         calendar heatmap, day detail
├── Stats/           stat cards, calculators
├── Settings/        settings screen
├── Onboarding/      tutorial
├── Health/          HealthKit writer
└── Support/         logging, entitlements, debug seed
PushBro/PushBroTests/  unit tests (Swift Testing)
```

## Known limitations

- Face tracking always cuts out near the bottom of a rep (the face drops below the TrueDepth minimum range, or out of frame). Detection and calibration are designed around this: the bottom is inferred from "descending deep, then lost tracking". Placement matters — phone directly under the **face**, so you stay in frame as long as possible.
- Voice commands are English ("start"/"stop") for now.
- No app icon artwork yet.
