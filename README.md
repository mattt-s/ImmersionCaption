# ImmersionCaption

<img src="Resources/Artwork/AppIcon.png" alt="ImmersionCaption app icon" width="112" height="112">

A native macOS app for learning English while listening to Mandarin audio from other applications. It turns application audio into English floating subtitles, with recognition and translation performed locally.

**Status: local development app built and launched.** Version 0.3.0 replaces display-based ScreenCaptureKit capture with private Core Audio process taps and system-audio-only permission, requiring macOS 14.2+. The generated icon and Short/Balanced caption controls remain available. Permission-driven audio capture, sustained transcription, and visual overlay acceptance remain to be checked interactively. See [validation evidence](docs/VALIDATION.md) for current test/build results.

## Implemented in source

- Core Audio process-tap capture of system/application output; no screen capture or microphone input.
- On-device Mandarin (`zh-CN`) recognition through Apple's Speech framework, with no cloud fallback.
- Local Ollama translation, defaulting to the installed `translategemma:4b` model.
- A natural-English translation prompt with up to two previous translated phrases as context.
- Start, pause, resume, stop, menu bar controls, and surfaced errors.
- Floating, click-through subtitles on the primary display; top/middle/bottom placement, font size, background transparency, and optional Chinese text.
- A native Finder/Dock app icon, built from the generated [master artwork](Resources/Artwork/AppIcon.png).
- Persistent preferences; memory-only history capped at 300 entries; explicit text export.
- Text-only translation check and overlay preview for setup.
- Short clauses using punctuation, recognized-word pauses, word boundaries, duration/length targets, and stable-draft flushing; a three-item pending queue; cancellation/generation checks that reject late results.

These features are implemented; build, automated tests, and basic launch have been verified. The remaining manual acceptance checks are listed below. Embedded inference and model management are planned, not implemented.

## Architecture

![ImmersionCaption architecture diagram](docs/diagrams/architecture.svg)

The caption session coordinates replaceable audio, speech, and translation providers. The current app uses local Apple speech recognition and a separate Ollama process; the gray section shows planned embedded inference and model management. See [ARCHITECTURE.md](ARCHITECTURE.md) for responsibilities, runtime data flow, and concurrency, or open the [editable diagram](docs/diagrams/architecture.mmd).

## Requirements

- macOS 14.2+; Apple Silicon recommended. An M2 Pro with 16 GB is a suitable initial target, but sustained audio performance has not been measured.
- Xcode 15.2+ with Swift 5.9+ and a macOS 14.2+ SDK. A current Xcode compatible with your macOS is recommended. Old command-line tools are insufficient.
- Apple's on-device Mandarin recognition assets. Availability varies by OS/language; the app refuses recognition if `supportsOnDeviceRecognition` is false.
- Ollama running locally and a downloaded local model. No API key or paid service is used. Initial development detected `translategemma:4b` already installed.

## Build and install locally

Finish installing Xcode and launch it once to complete its setup. Select its command-line tools, either in Xcode Settings → Locations or:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

From this repository:

```sh
scripts/check-environment.sh
swift test --package-path Packages/CaptionCore
swift test
scripts/build-app.sh
scripts/check-app-launch.sh
open build/ImmersionCaption.app
```

The build script creates an ad-hoc signed development `.app` with privacy descriptions and the speech entitlement. Use that bundle for permission testing. Opening Package.swift in Xcode is useful for editing/debugging; `swift run` is not the supported permission-testing installation path.

The same script builds `AppIcon.icns` from the project artwork using native macOS tools and includes it before signing. See [icon source and generation prompt](Resources/Artwork/README.md). No image-generation service is needed to build or run the app.

Set `CODE_SIGN_IDENTITY` to an available development identity to use it instead of ad-hoc signing. Signed distribution, provisioning, hardened runtime, notarization, and App Store packaging have not been configured or validated. If speech authorization fails with an ad-hoc bundle, use an appropriately provisioned development identity and recheck its entitlement.

To install after a successful build, copy `build/ImmersionCaption.app` into Applications. Keep one copy for permission testing so macOS does not confuse development bundles with the same identifier.

`scripts/check-app-launch.sh` leaves the application open and verifies that its process has a visible window. It does not click controls, capture audio, or request macOS privacy permissions.

## Configure

1. Open Ollama. If it is not running, use `ollama serve`. Do not start a second server if the Ollama app is already serving.
2. Verify `ollama list` includes `translategemma:4b`. If needed, `ollama pull translategemma:4b` downloads it; this requires internet and model storage.
3. In ImmersionCaption Settings, leave the default address `http://127.0.0.1:11434` and model `translategemma:4b`.
4. Use **Translate sample** to test the service before capturing audio.
5. If Mandarin recognition is unavailable, check System Settings → Keyboard → Dictation and enable/download Chinese (Mandarin, China mainland). This is a troubleshooting step, not a guarantee that macOS will provide an on-device model. The app checks actual availability at runtime.

Only explicit HTTP loopback addresses are accepted. HTTP redirects and proxies are disabled by the production adapter. Run a trusted Ollama installation with genuinely local models; a third-party service listening locally or an Ollama cloud-backed model is outside this application's privacy boundary. Do not configure cloud models.

## Use

1. Start Mandarin playback in another app, then select **Start translating**.
2. Allow **Speech Recognition** and **System Audio Recording** when macOS requests them. Screen recording and microphone access are not needed. The audio-only toggle may appear inside Privacy & Security → Screen & System Audio Recording → System Audio Recording Only. If you previously installed version 0.2 or earlier, macOS may retain its old screen-recording entry; you can disable that broader permission and allow audio-only access for this build. Quit older running copies before testing the replacement. Restart translation (or reopen the app) after changing permissions.
3. Adjust the overlay in Settings; enable **Preview subtitle overlay** to see changes during silence. Disable preview when finished.
   Choose **Short** (default) for smaller phrases, or **Balanced** for longer context. Caption-length changes apply when you next start or resume.
4. Pause releases capture and recognition, discards pending translations, and hides the current subtitle. Resume starts fresh recognition/context; it does not replay audio heard while paused.
5. Stop cancels processing. Closing the main window leaves menu bar controls available. Quit from the menu bar to exit.

Subtitles disappear 12 seconds after their last update. History remains for the current app process, including across stop/start, until cleared. **Export** explicitly writes a plain-text copy to a location you choose.

## Latency and translation quality

The splitter combines several cues rather than assuming that every silence ends a sentence:

- **Short** targets 28 recognized characters or approximately 3.2 seconds of speech. It accepts gaps of at least 350 ms between recognized words after a minimum four-character phrase.
- **Balanced** targets 44 characters or approximately 4.5 seconds, with a 450 ms word-gap threshold.
- The speech adapter requests automatic punctuation. Chinese sentence punctuation ends a phrase immediately. Commas/colons can end clauses once they contain at least 10 characters; numeric commas and time colons are preserved.
- Length and duration splits prefer recognized boundaries. Because the recognizer can group a whole clause into one segment, oversized/missing units fall back to Foundation word tokenization (then grapheme boundaries if needed). A long unbroken Latin proper name may exceed the target. These are soft targets, not a fixed English word count.
- A draft unchanged for 650 ms flushes as a fallback. This is text stability, not an acoustic silence detector. Short pauses alone do not prove that the meaning is complete.

Apple's [recognized-word timestamps](https://developer.apple.com/documentation/speech/sftranscriptionsegment/timestamp) supply pause/duration cues. No additional model, paid API, or raw-audio VAD dependency is added. Spoken-language boundaries remain heuristic; these thresholds are not end-to-end latency guarantees. Recognition requests still rotate every 45 seconds, with a possible gap because there is no overlapping audio buffer.

Only one translation runs at a time. At most three phrases wait behind it; overflow discards the oldest pending phrase and shows a skipped-phrase count. This limits accumulated backlog, not worst-case end-to-end latency. Steady speech can still outpace the model. The first translation may take several seconds to load the model.

Prompts favor concise, natural spoken English, idiomatic equivalents, faithful meaning, and tone, with no added teaching commentary or summarization. The splitter carries the remaining speech into later captions rather than truncating it; the existing overload policy can still skip queued phrases if the model cannot keep up. A 4B model can still misread ambiguity, alter nuance, or translate too literally. The six public [quality cases](docs/translation-quality-cases.json) are human-review material, not an automated fluency score. Warm **text translation** requests measured 0.46–0.97 seconds across two initial runs; this excludes audio capture, ASR, segmentation, and display time.

## Project structure

```text
Package.swift                         macOS executable and adapter/session tests
Packages/CaptionCore/                 Foundation-only models and policy tests
Sources/ImmersionCaption/
  App/                                composition root and application lifecycle
  Application/                        engine ports and caption session orchestration
  Infrastructure/                     capture, speech, Ollama, preferences
  Presentation/                       SwiftUI controls, history, settings, AppKit overlay
Resources/                            icon artwork, app identity, privacy descriptions, entitlements
Tests/ImmersionCaptionTests/           audio-buffer, lifecycle, and HTTP contract tests
scripts/                              build, environment, domain checks, local model smoke test
docs/                                 validation results and translation review fixtures
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for data flow and replacement engines, and [AGENTS.md](AGENTS.md) for development rules.

## Verification

```sh
# Runs production domain policies even with the original Swift 5.3 command-line tools:
scripts/test-core-compat.sh

# Sends only the public sample phrases to installed local TranslateGemma:
scripts/smoke-translation.sh

# Exercise the production Swift HTTP adapter against installed local TranslateGemma:
IMMERSIONCAPTION_LIVE_TEST=1 swift test --filter LocalTranslationIntegrationTests
```

The smoke script uses the production Swift prompt builder and a Python standard-library HTTP client. The opt-in XCTest instead runs the production Swift HTTP adapter against local Ollama and checks that a short Chinese phrase returns English text; it skips by default so ordinary tests do not depend on a model server. Neither is an automated fluency assessment or a test of live audio, permissions, or overlay interaction. The full XCTest suites need modern Xcode.

## Known limitations and roadmap

- The current Apple Silicon bundle is an ad-hoc signed development build. Compilation, launch, signature checks, and automated tests pass; live audio, permission handling, sustained use, and visual overlay behavior still need manual acceptance. No notarized release has been produced.
- On-device Mandarin availability is controlled by macOS. Direct model download/selection is not implemented.
- Captures a global stereo mix of application output using a private, tap-only aggregate device, without changing your default audio devices. This process is excluded when it already has a Core Audio process object; the app itself does not play audio. There is no per-app selector, audio mixing control, or multi-display subtitle selector. If the tap format changes after switching an output device, translation stops with a restart message rather than decoding buffers with the wrong format.
- Protected/DRM content or some application audio may be unavailable to capture.
- The legacy Speech framework may end recognition or return service errors. Requests restart on final results and rotate periodically; unexpected errors stop the session visibly. Long-duration and silent-input behavior need device testing.
- Partials can change after a phrase has been committed. Word timestamps help realign earlier text-length revisions without replaying consumed audio; providers without timings use positional fallback. Displayed translations cannot be corrected retroactively, and revised/merged word boundaries remain imperfect.
- The overlay supports presets, not dragging. Long text may scale down or be truncated within its bounded panel; use shorter phrases/smaller fonts.
- No audio replay, VAD, translation streaming, glossary, language learning analytics, or global shortcuts.
- No third-party source-package dependencies or analytics. The app stores preferences and explicitly exported history only; macOS/Ollama may have their own service logs.
- Embedded inference (for example a suitable local llama.cpp/MLX adapter), app-managed models with checksum/license/disk-space handling, and a standalone offline installer remain future work. Apple assets and Ollama models must already be installed for offline operation today.

## References and licensing

The capture adapter follows [Apple's Core Audio process-tap guidance](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps), using `NSAudioCaptureUsageDescription` for audio-only authorization. There is no ScreenCaptureKit fallback on older macOS versions. Recognition checks [on-device capability](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition) and requires local requests. The translation adapter follows the [Ollama chat API](https://docs.ollama.com/api/chat) and [TranslateGemma prompt guide](https://ollama.com/library/translategemma).

Application source is MIT licensed; see LICENSE. AI model weights and Apple/Ollama components have their own terms. No weights or external runtimes are bundled or redistributed.
