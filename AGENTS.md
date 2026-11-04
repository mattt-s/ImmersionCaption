# ImmersionCaption development instructions

## Product and privacy

- Build multilingual native macOS captions for system/application audio. User chooses the spoken language. Translation is removed; do not reintroduce it without an explicit request.
- Capture output using Core Audio process taps and NSAudioCaptureUsageDescription. No ScreenCaptureKit, screen recording requests, or microphone input. Keep tap/aggregate private, playback unmuted, and default devices unchanged.
- Require on-device recognition, with no silent cloud fallback. Discover locales/capabilities, show only on-device options in language menus, resolve saved selection within that filtered list, and recheck availability on start. Never log audio/transcripts. History is memory-only until explicit export.

## Architecture and policy

- Swift 5.9+, macOS 14.2+. Use MainActor session/presentation and structured concurrency. Domain policy lives in Packages/CaptionCore; application ports/coordinator in Application; adapters in Infrastructure; views in Presentation. Select concrete providers in AppContainer.
- Recognition uses SpeechRecognizing with an explicit locale and cumulative text/request ID/actual finality events. No Apple recognition types in domain models. Caption holds a request snapshot and language metadata.
- Show partial text immediately. Replace revisions under the same identity/time; do not append duplicate partials or wait for punctuation/isFinal. Finality marks an existing entry, never gates first display. Empty partial revisions retract; final entries are immutable.
- Keep history bounded to 300 request snapshots and rolling display to three current-run blocks. Let layout wrap/scroll at the selected font; do not reintroduce source cuts or automatic font shrinking. Follow live can be paused for review.
- Language changes require paused/stopped state. Snapshot selection at start; preserve previous-language history while clearing the live display on restart. No automatic language detection is implemented.
- Invalidate session/request generations on stop/pause/failure. Do not publish obsolete callbacks or expiry tasks. Never fabricate finality during maintenance rotation. There is no overlap audio buffer or cross-request deduplication; document limitations honestly.
- Idle hiding is a 12-second unchanged-transcript heuristic; Keep Onscreen overrides it while running. Do not claim it is Apple's internal silence algorithm. Preserve optional click-through and accessible main-window history/export.
- Prefer focused types, explicit injection, and documented ownership. Copy HAL buffers before return, synchronize delivery/stop, and clean up partial startup. Defer overlay hosting-view creation until view startup.
- Keep icon source/provenance and native-size packaging before signing. Do not add dependencies without a concrete need.

## Verification and delivery

- Runtime changes: swift test --package-path Packages/CaptionCore, swift test, scripts/build-app.sh. Foundation-only checks: scripts/test-core-compat.sh.
- Startup/overlay changes: scripts/check-app-launch.sh checks process/window metadata and leaves the app open. It does not test audio/permissions.
- Test locale selection/persistence, local-only failure paths, revised partials, identity/finality, empty/Unicode text, bounds, and lifecycle races. Manually verify scrolling, language quality, permissions/assets, continuous audio, device changes, and Spaces/fullscreen before release.
- Maintain README.md, ARCHITECTURE.md, docs/CAPTION_POLICY.md, docs/LIVE_CAPTIONS_RESEARCH.md, docs/VALIDATION.md, and editable/rendered diagrams. Distinguish documented Apple behavior from our design choices, and automated evidence from interactive acceptance.
- Use Git; preserve user work. Do not commit bundles/models/logs/personal history. Do not delete external apps/models when removing an integration. Embedded alternative speech engines, asset management, distribution signing, and notarization remain planned.
