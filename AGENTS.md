# ImmersionCaption development instructions

## Product and privacy

- Build a native macOS application for Mandarin system-audio captions translated into idiomatic English.
- Never capture the microphone. Never silently use cloud recognition or remote translation.
- Require on-device speech recognition. Ollama connections must remain loopback-only.
- Do not log audio, transcripts, translations, or request bodies. History is memory-only unless the user explicitly exports it.
- Keep subtitle text faithful to meaning, tone, and intent; do not invent facts or teach vocabulary inside translations.

## Architecture and Swift

- Swift 5.9+; macOS 13+. Use structured concurrency and isolate presentation/session state to MainActor.
- Keep domain policy in Packages/CaptionCore, orchestration and ports in Application, native adapters in Infrastructure, UI in Presentation. Wire dependencies only in App/AppContainer.swift.
- Keep AI providers behind SpeechRecognizing and TranslationEngine. No Ollama DTOs or Apple recognition types in domain models.
- Prefer small focused types, explicit injected dependencies, and descriptive names. Avoid speculative abstraction.
- Add documentation comments for protocols, public APIs, and nontrivial behavior. Explain ownership and synchronization at concurrency boundaries.
- Cancel tasks and invalidate session generations on pause, stop, or error. Never publish stale results.
- Bound live queues and history. Surface dropped work rather than allowing unbounded latency.

## Verification and delivery

- Run `swift test --package-path Packages/CaptionCore` for business rules; run `swift test` and `scripts/build-app.sh` with modern Xcode tools for adapter/app checks.
- Do not claim that source parsing or core tests prove the macOS app compiles or captures audio.
- Test lifecycle races, segmentation, loopback enforcement, request/response contracts, cancellation, and overload behavior when changing them.
- Verify actual screen/audio permission flows, Mandarin model availability, overlay behavior across Spaces, and translation quality on a Mac before release.
- Maintain README.md, ARCHITECTURE.md, and docs/VALIDATION.md with implementation changes. Distinguish implemented, verified, and planned features.
- Use Git, preserve user work, keep generated bundles, models, and personal history out of commits. Do not add external dependencies without a concrete need.
- Standalone embedded inference, direct model management, notarization, and distribution remain planned; do not imply they are implemented.
