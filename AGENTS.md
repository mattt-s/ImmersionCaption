# ImmersionCaption development instructions

## Product and privacy

- Build a native macOS app displaying recognized Mandarin application audio as floating captions. Translation is removed; do not reintroduce inference services, prompts, bilingual UI, or backend preferences without an explicit request.
- Capture output with Core Audio process taps and NSAudioCaptureUsageDescription. No ScreenCaptureKit, screen permission requests, or microphone input. Keep tap/aggregate private, playback unmuted, and default devices unchanged.
- Require on-device recognition without cloud fallback. Do not log audio/transcripts. History is memory-only unless explicitly exported.

## Architecture and Swift

- Swift 5.9+, macOS 14.2+. Use structured concurrency and MainActor presentation/session state.
- Domain rules in Packages/CaptionCore; orchestration/ports in Application; adapters in Infrastructure; UI in Presentation. Select providers only in App/AppContainer.swift.
- Keep recognition behind SpeechRecognizing and capture behind SystemAudioCapturing. No Apple recognition types in domain models. Caption contains recognized text only.
- Prefer focused types/injected dependencies; document nontrivial APIs and ownership/synchronization. Avoid unused abstractions/dependencies.
- Publish phrases directly; cap history at 300. Invalidate session generations and cancel expiry on pause/stop/failure. Never publish stale callbacks.
- Preserve sentence-first punctuation. In a partial with no sentence ending, comma/colon/semicolon can delimit a clause at character position ten or later. Never force cuts by maximum length, duration, timing gap, pause, or unchanged-text timeout. Real finals may flush the tail; maintenance must not fabricate finality.
- Carry unfinished text and reset/offset timing ranges across request IDs. All-zero timings are unavailable, not an audio watermark. Use timing/text anchors; preserve UTF-16/emoji and legitimate repeated speech.
- There is no precommit stability confirmation. Do not call revision alignment stabilization or promise retroactive correction.
- Copy HAL buffers before returning; synchronize stop/delivery and clean up partial startup. Defer overlay NSHostingView creation until view startup, never during AppContainer initialization.
- Keep Resources/Artwork/AppIcon.png as icon source; package native sizes before signing and preserve provenance.

## Verification and delivery

- For runtime changes run swift test --package-path Packages/CaptionCore, swift test, and scripts/build-app.sh. Foundation-only fallback: scripts/test-core-compat.sh.
- For startup/overlay changes run scripts/check-app-launch.sh. It leaves the app open and checks process/window metadata, not live audio or permissions.
- Test lifecycle races, publication/history, segmentation/revisions, request carry, and PCM ownership where changed. Manually verify permissions, Mandarin assets, sustained audio, output devices, and Spaces/fullscreen before release.
- Keep README.md, ARCHITECTURE.md, docs/CAPTION_POLICY.md, docs/VALIDATION.md, and editable/rendered diagrams consistent. Regeneration instructions: docs/diagrams/README.md. Distinguish implemented, tested, and planned features.
- Use Git, preserve user work, and keep generated bundles, models, logs, and personal history out of commits. Removing an integration must not delete external apps or their model files.
- Direct speech-model management, alternative embedded engines, distribution signing, and notarization remain planned.
