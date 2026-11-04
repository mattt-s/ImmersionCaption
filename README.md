# ImmersionCaption

<img src="Resources/Artwork/AppIcon.png" alt="ImmersionCaption app icon" width="112" height="112">

A native macOS application displaying recognized Mandarin from application audio as floating captions. Capture and recognition run locally; the microphone is never used.

**Version 0.5.0: captions only.** Translation, Ollama integration, prompts, the inference queue, bilingual display, and backend preferences have been removed. No Ollama installation or translation models are required. This change does not uninstall external applications or delete their models.

## Features

- Core Audio process-tap capture of application/system output; no screen capture or microphone input.
- On-device Mandarin (`zh-CN`) recognition through Apple's installed speech assets, with no cloud fallback.
- Click-through floating captions across Spaces/fullscreen, font size, opacity, position presets, and preview.
- Start/pause/resume/stop, menu bar controls, and visible errors.
- Sentence-first punctuation, request continuation, and revision alignment to reduce replay.
- Memory-only history of the latest 300 phrases; clear and explicit plain-text export.

## Requirements

- macOS 14.2+ and Apple's installed on-device Mandarin recognition assets. Apple Silicon recommended.
- Xcode 15.2+ and Swift 5.9+ for building. CaptionCore also supports the original Swift 5.3 compatibility checks.
- There are no third-party source-package dependencies or inference services to configure.

Speech assets may need downloading through macOS Dictation settings before offline use. Recognition refuses to start when local Mandarin support is unavailable.

## Build and install

Complete Xcode setup and select its command-line tools. From the project root:

```sh
swift test --package-path Packages/CaptionCore
swift test
scripts/build-app.sh
open build/ImmersionCaption.app
```

The build creates an ad-hoc signed development bundle with the native icon at `build/ImmersionCaption.app`. Copy it into Applications to install locally. Quit older copies first and use one copy for privacy permissions. Launch the packaged app for permission testing; `swift run` is not the supported installation path.

## Usage and configuration

1. Open the app and choose **Start captions**.
2. Allow **Speech Recognition** and **System Audio Recording**. macOS may list the audio-only permission inside Privacy & Security → Screen & System Audio Recording → System Audio Recording Only. Screen recording and microphone access are not needed.
3. Play Mandarin in another application. Recognized phrases appear directly in the overlay and history. **Hearing** shows the current, revisable hypothesis.
4. Adjust font size, background opacity, and top/middle/bottom position in Settings. Preview works without recording.
5. Pause/resume or stop from the window/menu bar. Closing the window leaves menu controls available; **Quit ImmersionCaption** exits.

Captions disappear 12 seconds after their last committed update. History survives stop/start until cleared or the process exits. Export writes recognized text to a chosen location. Retired backend/bilingual preference keys are removed on settings initialization; appearance is preserved.

## Caption policy and limitations

The [policy diagram and walkthrough](docs/CAPTION_POLICY.md) describe exact decisions. An available sentence ending takes priority over commas. Otherwise a real final result commits remaining text, or an eligible comma/colon/semicolon at character position ten or later commits a partial clause. No maximum-length, duration, pause, or unchanged-text cuts are used.

Punctuated partials can commit immediately; there is no stability confirmation gate. Timing/text-diff alignment tries to avoid replay and does not repair earlier captions. Unpunctuated speech may wait for a boundary or final result. Requests rotate every 45 seconds, carrying unfinished recognized text without overlapping audio buffering.

Every committed phrase enters history directly. When one callback emits multiple phrases, the overlay shows the last; history keeps all subject to its 300-entry limit. Six-line overlay layout may scale down or visually truncate long text. Pagination, dragging, per-app capture selection, automatic language detection, and semantic endpoint detection are not implemented.

Capture uses a private global stereo mix without changing default devices. Protected audio may be unavailable. Output-format changes and unexpected speech errors stop the session visibly. Permission recovery, sustained recognition, and overlay appearance across Spaces require interactive acceptance. This is a development build; distribution signing and notarization are not implemented.

## Project structure and verification

```text
Packages/CaptionCore/                 caption values, segmentation, revision alignment, domain tests
Sources/ImmersionCaption/
  App/                               composition root and lifecycle
  Application/                       capture/speech ports and caption session
  Infrastructure/                    Core Audio, Apple Speech, appearance preferences
  Presentation/                      controls, settings, history, overlay
Resources/                           artwork, privacy descriptions, entitlements
Tests/ImmersionCaptionTests/          session, settings, startup, and PCM tests
scripts/                             environment, build, launch, compatibility checks
docs/                                policy, diagrams, verification record
```

See [ARCHITECTURE.md](ARCHITECTURE.md), [AGENTS.md](AGENTS.md), and [validation evidence](docs/VALIDATION.md). `scripts/test-core-compat.sh` runs Foundation-only production checks. After building, `scripts/check-app-launch.sh` checks process/window metadata and leaves the app open; it does not grant permissions or test live capture.

Audio and history are not automatically saved. Preferences use UserDefaults and history export is explicit. Logs contain lifecycle/error categories rather than audio/transcripts. Offline operation needs already installed Apple speech assets. Direct speech-model management and alternative embedded recognition engines remain planned.
