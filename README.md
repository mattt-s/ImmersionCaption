# ImmersionCaption

A native macOS app for learning English while listening to Mandarin audio from other applications. It turns application audio into English floating subtitles, with recognition and translation performed locally.

**Status: initial implementation, not yet validated as a running macOS app.** The production domain checks and local TranslateGemma smoke tests pass. The full application cannot currently be compiled on the development machine because it has Swift 5.3.2, a macOS 11.1 SDK, and no XCTest runner. Finish installing modern Xcode before using the app. See [validation evidence](docs/VALIDATION.md).

## Implemented in source

- ScreenCaptureKit system/application audio capture, excluding ImmersionCaption; no microphone input.
- On-device Mandarin (`zh-CN`) recognition through Apple's Speech framework, with no cloud fallback.
- Local Ollama translation, defaulting to the installed `translategemma:4b` model.
- A natural-English translation prompt with up to two previous translated phrases as context.
- Start, pause, resume, stop, menu bar controls, and surfaced errors.
- Floating, click-through subtitles on the primary display; top/middle/bottom placement, font size, background transparency, and optional Chinese text.
- Persistent preferences; memory-only history capped at 300 entries; explicit text export.
- Text-only translation check and overlay preview for setup.
- Stable partial-transcript flushing, bounded phrase lengths, a three-item pending translation queue, and cancellation/generation checks that reject late results.

These features are implemented but still require the build and manual acceptance checks below. Embedded inference and model management are planned, not implemented.

## Requirements

- macOS 13+; Apple Silicon recommended. An M2 Pro with 16 GB is a suitable initial target, but sustained audio performance has not been measured.
- Xcode 15+ with Swift 5.9+ and a macOS 13+ SDK. A current Xcode compatible with your macOS is recommended. Old command-line tools are insufficient.
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
open build/ImmersionCaption.app
```

The build script creates an ad-hoc signed development `.app` with privacy descriptions and the speech entitlement. Use that bundle for permission testing. Opening Package.swift in Xcode is useful for editing/debugging; `swift run` is not the supported permission-testing installation path.

Set `CODE_SIGN_IDENTITY` to an available development identity to use it instead of ad-hoc signing. Signed distribution, provisioning, hardened runtime, notarization, and App Store packaging have not been configured or validated. If speech authorization fails with an ad-hoc bundle, use an appropriately provisioned development identity and recheck its entitlement.

To install after a successful build, copy `build/ImmersionCaption.app` into Applications. Keep one copy for permission testing so macOS does not confuse development bundles with the same identifier.

## Configure

1. Open Ollama. If it is not running, use `ollama serve`. Do not start a second server if the Ollama app is already serving.
2. Verify `ollama list` includes `translategemma:4b`. If needed, `ollama pull translategemma:4b` downloads it; this requires internet and model storage.
3. In ImmersionCaption Settings, leave the default address `http://127.0.0.1:11434` and model `translategemma:4b`.
4. Use **Translate sample** to test the service before capturing audio.
5. If Mandarin recognition is unavailable, check System Settings → Keyboard → Dictation and enable/download Chinese (Mandarin, China mainland). This is a troubleshooting step, not a guarantee that macOS will provide an on-device model. The app checks actual availability at runtime.

Only explicit HTTP loopback addresses are accepted. HTTP redirects and proxies are disabled by the production adapter. Run a trusted Ollama installation with genuinely local models; a third-party service listening locally or an Ollama cloud-backed model is outside this application's privacy boundary. Do not configure cloud models.

## Use

1. Start Mandarin playback in another app, then select **Start translating**.
2. Allow Speech Recognition and Screen Recording / Screen & System Audio Recording when macOS requests them. The exact label depends on macOS. A microphone permission is never requested. You may need to quit/reopen the app after granting capture access.
3. Adjust the overlay in Settings; enable **Preview subtitle overlay** to see changes during silence. Disable preview when finished.
4. Pause releases capture and recognition, discards pending translations, and hides the current subtitle. Resume starts fresh recognition/context; it does not replay audio heard while paused.
5. Stop cancels processing. Closing the main window leaves menu bar controls available. Quit from the menu bar to exit.

Subtitles disappear 12 seconds after their last update. History remains for the current app process, including across stop/start, until cleared. **Export** explicitly writes a plain-text copy to a location you choose.

## Latency and translation quality

Sentences are sent when a recognized punctuation boundary arrives, when a draft remains unchanged for one second, or when the recognizer finalizes/rotates. Long phrases split at 80 characters. Recognition requests rotate every 45 seconds. A small transition gap is possible because there is no overlapping audio buffer.

Only one translation runs at a time. At most three phrases wait behind it; overflow discards the oldest pending phrase and shows a skipped-phrase count. This limits accumulated backlog, not worst-case end-to-end latency. Steady speech can still outpace the model. The first translation may take several seconds to load the model.

Prompts favor natural spoken English, idiomatic equivalents, faithful meaning, and tone, with no added teaching commentary. A 4B model can still misread ambiguity, alter nuance, or translate too literally. The six public [quality cases](docs/translation-quality-cases.json) are human-review material, not an automated fluency score. Warm **text translation** requests measured 0.46–0.83 seconds on the initial machine; this excludes audio capture, ASR, segmentation, and display time.

## Project structure

```text
Package.swift                         macOS executable and adapter/session tests
Packages/CaptionCore/                 Foundation-only models and policy tests
Sources/ImmersionCaption/
  App/                                composition root and application lifecycle
  Application/                        engine ports and caption session orchestration
  Infrastructure/                     capture, speech, Ollama, preferences
  Presentation/                       SwiftUI controls, history, settings, AppKit overlay
Resources/                            app identity, privacy descriptions, entitlements
Tests/ImmersionCaptionTests/           lifecycle and HTTP contract tests
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
```

The smoke test uses the production Swift prompt builder and a Python standard-library HTTP client. It does **not** verify the Swift HTTP adapter, microphone exclusion at runtime, audio transcription, permissions, or UI. The full XCTest suites need modern Xcode.

## Known limitations and roadmap

- Full app compilation and end-to-end use are unverified pending modern Xcode; do not treat this as a release build.
- On-device Mandarin availability is controlled by macOS. Direct model download/selection is not implemented.
- Captures aggregate application audio using the first available display filter. There is no per-app selector, audio mixing control, or multi-display subtitle selector.
- Protected/DRM content or some application audio may be unavailable to capture.
- The legacy Speech framework may end recognition or return service errors. Requests restart on final results and rotate periodically; unexpected errors stop the session visibly. Long-duration and silent-input behavior need device testing.
- Partials can change after a phrase has been committed. Already displayed translations are not revised; prefix alignment can omit or split words following earlier recognition edits.
- The overlay supports presets, not dragging. Long text may scale down or be truncated within its bounded panel; use shorter phrases/smaller fonts.
- No audio replay, VAD, translation streaming, glossary, language learning analytics, or global shortcuts.
- No external dependencies or analytics. The app stores preferences and explicitly exported history only; macOS/Ollama may have their own service logs.
- Embedded inference (for example a suitable local llama.cpp/MLX adapter), app-managed models with checksum/license/disk-space handling, and a standalone offline installer remain future work. Apple assets and Ollama models must already be installed for offline operation today.

## References and licensing

The capture adapter follows [Apple's ScreenCaptureKit guidance](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos). Recognition checks [on-device capability](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition) and requires local requests. The translation adapter follows the [Ollama chat API](https://docs.ollama.com/api/chat) and [TranslateGemma prompt guide](https://ollama.com/library/translategemma).

Application source is MIT licensed; see LICENSE. AI model weights and Apple/Ollama components have their own terms. No weights or external runtimes are bundled or redistributed.
