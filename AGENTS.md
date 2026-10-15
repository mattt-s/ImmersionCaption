# ImmersionCaption development instructions

## Product and privacy

- Build a native macOS application for Mandarin system-audio captions translated into idiomatic English.
- Capture application output with Core Audio process taps and `NSAudioCaptureUsageDescription`; do not introduce ScreenCaptureKit, screen permission requests, or a microphone input. Keep tap/aggregate private, playback unmuted, and default devices unchanged. Copy HAL callback buffers before returning; synchronize stop with delivery and clean up partial startup.
- Never capture the microphone. Never silently use cloud recognition or remote translation.
- Require on-device speech recognition. Ollama connections must remain loopback-only.
- Do not log audio, transcripts, translations, or request bodies. History is memory-only unless the user explicitly exports it.
- Keep subtitle text faithful to meaning, tone, and intent; do not invent facts or teach vocabulary inside translations.

## Architecture and Swift

- Swift 5.9+; macOS 14.2+. Use structured concurrency and isolate presentation/session state to MainActor.
- Keep domain policy in Packages/CaptionCore, orchestration and ports in Application, native adapters in Infrastructure, UI in Presentation. Wire dependencies only in App/AppContainer.swift.
- Keep AI providers behind SpeechRecognizing and TranslationEngine. No Ollama DTOs or Apple recognition types in domain models.
- Prefer small focused types, explicit injected dependencies, and descriptive names. Avoid speculative abstraction.
- Add documentation comments for protocols, public APIs, and nontrivial behavior. Explain ownership and synchronization at concurrency boundaries.
- Cancel tasks and invalidate session generations on pause, stop, or error. Never publish stale results.
- Bound live queues and history. Surface dropped work rather than allowing unbounded latency.
- Translate speech only on genuine `isFinal == true`. Drafts, even punctuated/stable drafts, update Hearing only. Pass the whole final text once; never cut by punctuation, character count, duration, word timing, pause, or timers, and never concatenate unfinalized drafts into later requests. Use request IDs for bounded duplicate-final tracking, not global text deduplication.
- Finish native requests gracefully with endAudio/finish and await the actual final callback before restarting. Maintenance must not cancel in order to translate a last draft or synthesize a final event. Bound finalization waits and in-memory captured-audio handoff; preserve sample order, reject stale session receivers, clear audio on stop, and fail visibly on timeout/overflow without a partial-text fallback. Keep Hearing previews and post-translation wrapping separate from finalized input. Test revised 港/岗 drafts, duplicate/empty finals, genuine repetitions, whole-input fidelity, lifecycle races, and audio replay limits/order.
- Keep Resources/Artwork/AppIcon.png as the icon build source. Generate native sizes with scripts/build-icon.sh and include the ICNS before signing; document a replacement asset's provenance/prompt.

## Verification and delivery

- Run `swift test --package-path Packages/CaptionCore` for business rules; run `swift test` and `scripts/build-app.sh` with modern Xcode tools for adapter/app checks.
- With local Ollama and translategemma:4b available, opt into the real adapter check using `IMMERSIONCAPTION_LIVE_TEST=1 swift test --filter LocalTranslationIntegrationTests`.
- After changing startup or overlay ownership, run `scripts/check-app-launch.sh` against the built bundle. It checks process/window metadata and leaves the app open; it does not grant permissions or validate live capture.
- Do not construct the overlay's NSHostingView inside AppContainer initialization: SwiftUI resolves the StateObject during its own graph update. Defer presentation to the view task to avoid a startup precondition failure.
- Do not claim that source parsing or core tests prove the macOS app compiles or captures audio.
- Test lifecycle races, final-result gating and audio handoff, loopback enforcement, request/response contracts, cancellation, and overload behavior when changing them.
- Verify actual system-audio-only and Speech permission flows, Mandarin model availability, overlay behavior across Spaces, and translation quality on a Mac before release.
- Maintain README.md, ARCHITECTURE.md, and docs/VALIDATION.md with implementation changes. Distinguish implemented, verified, and planned features.
- Keep docs/diagrams/architecture.mmd and its SVG/PNG exports in sync when changing the architecture; regeneration instructions are in docs/diagrams/README.md. Gray planned components must not be presented as implemented.
- Use Git, preserve user work, keep generated bundles, models, and personal history out of commits. Do not add external dependencies without a concrete need.
- Standalone embedded inference, direct model management, notarization, and distribution remain planned; do not imply they are implemented.
