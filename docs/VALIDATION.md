# Validation record

Initial development and subsequent build verification: 2026-10-15 (Asia/Tokyo).

## Version 0.6.0: finish recognition after natural pauses

Changes implemented on 2026-10-15:

- Added provider-neutral `SpeechPauseDetector`: at least 200 ms of audio activity, followed by one continuous second below -45 dBFS. Resumed activity resets quiet; leading silence and short clicks do not qualify. Nonempty native drafts only confirm speech presence for the current request; they never supply translation input or text boundaries.
- Added `PCMActivityMeter` for normalized per-channel RMS on packed little-endian float32/64 and signed int16/32, planar or interleaved. Taking the loudest channel avoids false silence from antiphase stereo. Invalid timing, unsupported formats, and nonfinite data stop visibly. A test caught Core Media rejecting an oversized interleaved buffer list; the meter now sizes it for the actual audio-plane count, and all representation fixtures pass.
- A 100 ms monitor asks the lock-protected sink to close input after eligible quiet, including a one-second absence of buffers. Session/request tokens and recognized-speech confirmation reject stale requests. Ending audio and detaching the request are atomic with append, so subsequent capture enters the existing bounded handoff buffer. `finish()` still must return a real final; no partial fallback, transcript slicing, or synthetic final was added. Monitoring is canceled on finish/replacement/stop. The 45-second maintenance safeguard remains for continuous audio and may occur mid-sentence.
- Buffered samples retain measured level/duration and replay in order; replacement resets speech confirmation and pause state. The new request must independently recognize speech. The existing 10-second finalization timeout, 12-second / 2,048-buffer limit, final gate, and translation queue remain in effect.
- **19 domain tests and 43 app/session/adapter tests passed: 62 total, zero failures**, including real local TranslateGemma inference. New coverage includes pause thresholds, initial silence, short/resumed gaps, missing callbacks, stale tokens, confirmation reset, ordered post-pause replay, invalid measurements, stereo phase cancellation, and native PCM formats. XCTest request-delivery fixtures do not run Apple's recognition model.
- The compatibility runner passed **29 production policy checks**. The arm64 version 0.6.0 / build 7 bundle compiled without warnings, passed strict signature verification, and passed the new-instance window launch check. `build/ImmersionCaption-0.6.0-arm64.zip` passed archive integrity verification. Architecture Mermaid/SVG/PNG exports were refreshed and the rendered diagram inspected.
- Added `scripts/check-speech.sh` and an explicit signed-app diagnostic mode. It synthesizes a temporary public Mandarin fixture with the installed Tingting voice, feeds it twice with 1.5-second gaps through the production Apple adapter, and requires two pause-triggered actual finals within 40 seconds, including a final during continued feeding. It reports only counts/timings/error categories, never transcriptions; no system capture, microphone, translation, or permission request is used. Temporary fixture/report files are removed by the script.
- **Native speech check passed after the user granted Speech Recognition permission to this bundle.** The initial attempt correctly reported missing authorization without opening a permission dialog. The repeated check used production on-device recognition and returned **two distinct actual final results from two pause-triggered finalizations**. The first final arrived **6.23 seconds** after check startup, while audio feeding continued; total check time was **13.34 seconds**, before any 45-second maintenance finish could occur. This validates the native pause/finish/final/restart path with a short synthesized fixture. Counts and timing were recorded without logging transcript text. It does not measure transcription accuracy or validate actual Core Audio capture, background music, sustained handoff, or the user's original audio. The separate read-only command-line capability probe reported on-device Mandarin supported; that process's authorization was not determined and is not used as proof of recognition.

**Acceptance limits:** expected endpoint request time is about 1–1.1 seconds after eligible quiet, plus delayed speech confirmation; native finalization and inference add latency. The 6.23-second observed first-final time includes speaking the fixture and is not a measurement of finalization delay alone. This is energy-based pause detection, not speech/noise separation or semantic sentence detection. Music/noise can hide gaps; quiet voices may cross the fixed threshold; speakers can pause mid-sentence. Uninterrupted audio can still reach the 45-second safeguard. Buffered speech may span multiple pauses and produce a larger final result. Test the user's actual material, pause/resume while finalizing, sustained multi-request continuity, silence, and background audio on the signed app before treating this as a validated live-caption release. To repeat the native check, grant Speech Recognition through normal app startup first, stop translation, then invoke the script against that same bundle.

## Version 0.5.0: translate finalized recognition only

Changes implemented on 2026-10-15:

- Live recognition events update Hearing immediately, but only actual `isFinal == true` results can pass `FinalTranscriptGate` into Ollama, history, and translated context. Each full final result is submitted once per request ID. The gate bounds duplicate tracking to 128 IDs and resets with the session; native request/session tokens independently reject retired callbacks. Identical speech in a different request remains valid. Manual Translate sample is an explicit text-only check outside recognition.
- Removed `TranscriptSegmenter`, `TranscriptCursor`, `SpeechSegment`, and the partial-text timing/continuation paths. This also removes the boundary-revision path that could replay a replaced final character such as 港 → 岗. No punctuation, character count, timing, or stable-draft trigger submits live translation work. Empty final results do not create captions.
- Changed the Apple adapter's 45-second maintenance from cancel/restart to `endAudio()` plus `SFSpeechRecognitionTask.finish()`, keeping the current token active until the real final callback. Only then is the next request started. A 10-second missing-final timeout stops with a visible error; it never promotes the last partial result.
- Extracted `SpeechAudioSink`, which buffers owning PCM samples during finalization (maximum 12 seconds / 2,048 sample buffers), replays them to the next request in order, and rejects stale session receivers. Invalid buffer timing or overflow reports failure once and stops the session; pause/stop discards pending audio. One native recognizer request is active at a time. There is no saved audio or user-facing audio replay.
- **12 domain tests and 33 app/session/adapter tests passed: 45 total, zero failures.** Replaced obsolete segmentation tests with final-gate regressions for punctuated/revised drafts, full long input, duplicate/empty finals, genuine repeated speech, cache bounds, and reset. Session tests cover 港/岗/港 drafts followed by one corrected full final, no draft history/context, duplicate finals, whole-input fidelity, and existing lifecycle/overload races. Six sink tests use overridden native request delivery (no speech task/model) to check ordered replay, duration/count limits, invalid samples, stop cleanup, repeated finishing, and stale receivers.
- The production Swift Ollama integration passed against installed local TranslateGemma (approximately 4.15 seconds for the public text sample; not audio latency). The compatibility runner passed its 24 production-policy checks.
- Release app build, signature verification, plist/version/audio-only-permission checks, and archive integrity passed. The initial launch check failed because it only inspected on-screen windows; metadata confirmed the new app process was running with a normal layer-0 window outside the on-screen list and no new crash report. The checker now checks all window metadata, retaining the new-process and two-second window requirements, so other Spaces/minimized windows do not create false startup failures. The updated new-instance launch check passed. Updated Mermaid/SVG/PNG diagrams now show `FinalTranscriptGate` rather than the removed draft segmenter/cursor/timing types; the rendered PNG was inspected.

**Still requires real-audio acceptance:** Apple's actual final callback after finish, timeout behavior, continuous handoff without missed words, native recognition under silence, pause/resume while finishing, and the user's original recording. Automated sink/gate tests do not run Apple's speech model. Final-only latency can be roughly 45 seconds or longer including finalization, buffered handoff, and inference; an earlier natural final can reduce that wait. `isFinal` indicates completed recognition for a request, not guaranteed word accuracy or grammatical completeness. Long finalized requests can exceed local-model/output limits or the existing bounded overlay; no pagination was added. Partial transcripts never serve as a fallback.

## Version 0.4.0: punctuation boundaries without forced cuts

Changes implemented on 2026-10-15:

- Removed source character limits, duration targets, word-gap cuts, tokenization fallback cuts, and the 650 ms stable-text translation timer. `CaptionLength`, the Short/Balanced picker, and its settings/composition-root wiring were removed; older stored preference values are ignored. The manual sample path also no longer truncates text at 500 characters.
- `TranscriptSegmenter` now searches all pending text for a complete punctuated sentence first. Available sentence endings take priority over earlier commas even for long text. When no complete sentence is available in a partial, a comma/colon/semicolon may delimit a clause after a minimum ten characters (a floor, never a maximum length). Numeric separators, common English abbreviations, and adjacent closing quotation marks are handled. A real final recognition result can commit an unpunctuated utterance intact.
- The 45-second maintenance rotation no longer fabricates a final recognition event. `beginUtterance()` carries only unfinished text between request IDs and resets timing/revision anchors. Current request UTF-16 timing ranges are offset into the combined text. Pause/stop clears the carry. This preserves recognized text across maintenance boundaries; it does not recover audio lost during request replacement.
- Reworked domain regressions around sentence priority, long input without forced cuts, pause/duration rejection, permitted punctuation clauses, final utterances, numeric separators, quotation marks, earlier revisions, and replay prevention. Added continuation tests for multiple rotations (including no-callback rotations), emoji/UTF-16 offsets, real timing revisions after a rotation, and already committed text. App tests check an unpunctuated draft still waits beyond the removed timeout, request continuity, pause cleanup, real finals, and no manual-input truncation.
- **33 domain tests and 26 app/session/adapter tests passed: 59 total, zero remaining failures.** The initial optional live model check could not reach Ollama; after reopening the installed app, the suite passed including production local TranslateGemma inference (approximately 4.69 seconds; not audio latency). The corrected continuation/timing fixtures were rerun and passed separately. The 24-check compatibility runner passed with the new intact-input expectations.
- Release app build, code signature verification, plist validation, new-instance launch/window checking, archive integrity, and version/audio-only-permission metadata checks passed. The Mermaid source and SVG/PNG exports were updated to remove `CaptionLength` and reflect punctuation segmentation. The rendered PNG was inspected.

**Behavior and acceptance limits:** punctuation remains an ASR heuristic, not a semantic completeness detector. A partial comma may be committed before a later full stop arrives; already translated clauses are not retracted. Without punctuation or a real final result, text waits longer. Long source sentences are no longer shortened to fit the overlay or model: the existing six-English-line/three-Chinese-line panel can visually truncate long translations, and the model retains context/output limits. Pagination is not implemented. Live replay of the user's original audio, long-running recognition, and perceptual caption quality remain interactive checks.

## Version 0.3.1: replayed clauses and translation consistency

Changes implemented on 2026-10-15:

- A synthetic replay of the reported pattern reproduced an app-side defect: a cumulative transcript with all-zero word timings first committed three clauses; an earlier text revision then re-emitted all three. Zero had been treated as a valid consumed-audio watermark, so revision alignment returned to the start. The caption export alone does not prove that the live recognizer supplied these exact timings; no raw-audio or transcript logging was introduced.
- All-zero timings no longer establish an audio watermark. A small `TranscriptCursor` text-diff helper follows the consumed boundary across earlier insertions/deletions when useful timings are absent. Content characters anchor the cursor before adjacent punctuation, preventing a matched full stop in newly appended speech from swallowing the new tail. Ambiguous/fully rewritten text and revised timing boundaries remain heuristic. Already displayed translations are not replaced retroactively.
- Added five domain regressions for zero-timed revisions, missing timings plus newly appended speech, loss of previously valid timings, legitimate repeated speech, and emoji/deletion alignment. Added one session regression proving repeated revisions do not enqueue old clauses for translation. No global string deduplication was added.
- The translation prompt now explicitly requests one translation of the current fragment, no alternatives/context repetition or invented continuation, and preservation of narrative roles. Temperature changed from 0.2 to 0 in both the production request and public-fixture smoke script. The HTTP contract test checks the option and instruction. These controls reduce sampling variability; they do not guarantee identical results with different context or correct mistranscribed input.
- **30 domain tests and 23 app/session/adapter tests passed: 53 total, zero failures**, including a real local TranslateGemma request (approximately 4.43 seconds; not audio latency).
- Eight public quality fixtures completed through the production prompt and local model at temperature 0, approximately 0.40–1.00 seconds each. This was a text-only spot check, not a fluency score: the model preserved the positive intent of 求之不得 in a clear complete sentence but used the overly strong “desperate”; other fixtures still showed nuance errors (such as “take a closer look” for 再看看). Narration subjects were preserved in the added waiter/boss fixture. A response legitimately contained two English sentences, demonstrating that sentence count within one response differs from replayed caption entries.

Release build, signature verification, archive integrity, new-instance launch/window checking, and the 24-check compatibility runner passed. The same synthetic replay probe now emits no old clauses after revision. The original recording still needs an interactive replay to confirm whether this fix resolves every observed duplicate and to assess speech-recognition accuracy; garbled text such as the reported 当场陨落 cannot be confidently repaired without the audio.

## Version 0.3.0: system audio permission only

Changes implemented on 2026-10-15:

- Replaced `ScreenAudioCapture` with `CoreAudioTapCapture` behind the existing `SystemAudioCapturing` port. The app no longer links ScreenCaptureKit or enumerates display/window content. A private, unmuted global stereo process tap feeds a private tap-only aggregate device. No physical input device or default-device changes are involved.
- Replaced `NSScreenCaptureUsageDescription` with `NSAudioCaptureUsageDescription`. Speech Recognition permission remains required. Package deployment target, bundle minimum, environment checks, and documentation now require macOS 14.2+ / Xcode 15.2+.
- Native setup/cleanup runs on a serial control queue. Audio delivery runs synchronously on a separate serial queue; stop disables delivery before tearing down native resources. Partial startup failures use the same teardown. A format-change listener ignores unchanged notifications and reports actual format changes for an explicit restart.
- Added eight tests covering owning copies of HAL memory, exact PCM timestamps/frame counts, interleaved and planar stereo, empty buffers, invalid formats and malformed planes, delivery disabled on stop, failure coalescing, and suppression of queued errors after stop. Initial conversion tests exposed Core Media's requirement for exact sample-clock timing: rounded nanosecond durations were rejected; the implementation now uses `CMTime(value: 1, timescale: sampleRate)`.
- `swift test --package-path Packages/CaptionCore`: **25 passed**. `swift test`: **21 passed**, with the opt-in live test skipped as expected. A separate `IMMERSIONCAPTION_LIVE_TEST=1 swift test --filter LocalTranslationIntegrationTests` run passed the real local TranslateGemma test in approximately 3.83 seconds. **47 distinct tests passed, zero remaining failures.** Translation timing excludes capture and recognition.
- Release `.app` build, signature verification, plist validation, shell syntax checks, and new-instance launch/window check passed. The executable's deployment minimum is 14.2; linked-framework inspection confirms Core Audio and no ScreenCaptureKit. Updated architecture SVG/PNG exports were regenerated from Mermaid source.

**Still requires interactive acceptance:** open the 0.3 bundle after quitting older copies, disable any retained broad screen-recording grant, allow System Audio Recording Only plus Speech Recognition, and play Mandarin in another app. Confirm captions with screen recording disabled, pause/resume/stop behavior, denial/regrant recovery, silence, sustained listening, and output-device changes. Automated PCM fixtures and a successful launch do not prove the actual permission prompt or live audio path. No TCC database/reset operations were performed. macOS may retain the older version's broader permission entry; this build does not request it.

## Version 0.2.0: icon and shorter captions

Changes implemented on 2026-10-15:

- Generated an original caption-bubble app icon with the built-in image tool. The 1254×1254 transparent master lives in `Resources/Artwork/AppIcon.png`; its prompt/provenance is documented beside it. Native `sips`/`iconutil` packaging builds all ten standard representations up to 1024 pixels. The app's `CFBundleIconFile` references the bundled ICNS.
- Short (default) targets 28 recognized characters / 3.2 seconds, with a 350 ms gap threshold. Balanced targets 44 / 4.5 seconds / 450 ms. Automatic punctuation, clause punctuation, valid UTF-16 ranges, speech-unit timing, Foundation word fallback, and 650 ms text-stability fallback are combined. A pause alone is not a semantic sentence detector, and recognition units can contain multiple words.
- Added tests for continuous rapid speech, short/threshold pauses, earlier recognition revisions, proper names, oversized multiword ASR units, UTF-16/emoji, invalid ranges, numeric punctuation, and preserving source text across chunks. Added a session test proving timing metadata reaches the splitter before its stable-text timeout.
- `swift test --package-path Packages/CaptionCore`: **25 tests passed**. App/session/HTTP tests with live inference enabled: **14 tests passed**. **39 total, zero failures**; a warm live local translation request completed in approximately 0.41 seconds (not an audio-latency measurement).
- The compatibility runner passed its 24 production-domain checks. The generated native icon round-tripped through `iconutil`; all ten expected representation dimensions validated, and the app metadata points to the icon. Shell syntax, plist format, and signature checks passed for the initial 0.2 build.
- Launch checking now requires a newly started app, rather than allowing an older running instance to mask a failure, and requires a visible window to remain for two seconds. It leaves existing app instances alone.

The final 0.2 release bundle built successfully, including the icon, and passed signature verification. The updated launch check passed against a new app instance with a visible window for two seconds. The bundle is staged away from the existing build before signing, so icon/signing failures do not leave a partially updated app. Actual end-to-end audio and perceptual boundary quality still require live listening; synthetic timings and text fixtures do not establish that semantic sentence boundaries will always be correct. Raw-audio VAD is not implemented.

## Initial native build verification (version 0.1)

After Xcode installation and the user's license acceptance:

- Xcode 27.0, build 27A266a; Swift 6.4; macOS 27.0 SDK. Active developer directory: `/Applications/Xcode.app/Contents/Developer`.
- Fixed the Swift 5.3 manifest directive's whitespace so the core package can be resolved by current SwiftPM while preserving the old tools-version declaration.
- `swift test --package-path Packages/CaptionCore`: **11 tests passed**.
- `IMMERSIONCAPTION_LIVE_TEST=1 swift test`: **13 tests passed**, including the native-initialization regression, eight session lifecycle tests, three HTTP contract/error tests, and one real local model integration test. Total across both packages: **24 tests, zero failures**.
- The production Swift Ollama adapter returned English for the public sample. Its first integration test took 4.275 seconds; the later warm run took 0.404 seconds. These are test/request times, not end-to-end audio latency.
- `scripts/build-app.sh`: release build succeeded and produced `build/ImmersionCaption.app` for Apple Silicon with an ad-hoc development signature. Signature verification passed.
- The first launch exposed an AttributeGraph precondition failure: creating the overlay's NSHostingView inside StateObject dependency initialization re-entered SwiftUI's graph update. Overlay creation now runs from the main view's task, after yielding, and remains owned by AppContainer.
- `scripts/check-app-launch.sh`: **passed**; the rebuilt application remained running with one visible main window. This inspects process/window metadata only, with no screenshot, Accessibility, audio, or microphone access.
- Ollama was initially stopped and was started from its existing installed application for the live integration check.

**Still unverified:** interactive privacy permission flows, actual system-audio transcription, offline speech asset readiness, long-running recognition/rotations, subtitle appearance across Spaces/fullscreen, and installation on another machine. A development bundle now exists; this is not yet a notarized or fully accepted release.

## Original environment (before Xcode installation)

- Empty starting workspace; Git repository initialized on `main`.
- Apple Silicon `arm64`; host reports macOS 27.0.1.
- Active developer directory: `/Library/Developer/CommandLineTools`.
- Swift 5.3.2; macOS SDK points to macOS 11.1.
- Full Xcode is absent; `/Applications/Xcode.appdownload` is a placeholder, not a usable installation.
- `xcodebuild` is unavailable with these selected tools; `xctest` is missing.
- Ollama 0.40.4 is serving locally; `translategemma:4b` is installed (3.3 GB as reported by Ollama).
- A read-only Speech framework probe reports `zh-CN` recognizer availability and on-device capability both `true`. Authorization remains not determined (`0`); no permission was requested and no recognition/audio capture was performed. This does not validate actual transcription or offline asset readiness.

## Initial checks before Xcode installation

| Check | Result | What it establishes |
| --- | --- | --- |
| Compile CaptionCore production files with installed Swift compiler | Passed | Foundation domain sources compile with Swift 5.3.2 |
| `scripts/test-core-compat.sh` | 24 checks passed | Segmentation, revisions, no duplicate flushes, bounded queue behavior, loopback URLs, context limit, prompt separator, translation guidance, start policy |
| Shell syntax check for scripts | Passed | Shell scripts parse |
| Info.plist and speech entitlements validation | Passed | Property lists parse |
| Read-only native Mandarin capability probe | Supported | Runtime advertises local zh-CN support; recording, authorization, and recognition remain untested |
| `scripts/check-environment.sh` | Correctly refused | Installed compiler is below Swift 5.9 |
| Core/root `swift test` | Blocked before test execution | Installed tools lack the XCTest runner; no XCTest pass is claimed |
| Full app build and launch | Blocked | Modern compiler and ScreenCaptureKit SDK are absent |
| Local TranslateGemma smoke test | Six completed nonempty translations | Production Swift prompt works against the installed service; not Swift HTTP adapter or audio verification |

## Observed translation examples

`scripts/smoke-translation.sh` used production TranslationPrompt output, the installed model, temperature 0.2, 4096-token context, and 384-token output limit. Timings are wall time for HTTP model requests only, without transcription/segmentation/display. This first run preceded a small prompt refinement:

| Chinese | Model output | Seconds |
| --- | --- | ---: |
| 别着急，咱们一步一步来。 | Don't worry, let's take it step by step. | 4.75 |
| 这事儿八字还没一撇呢。 | This is just starting to unfold. | 0.46 |
| 你可别放我鸽子啊。 | Don't stand me up. | 0.46 |
| 我也不是非得今天拿到，明天也行。 | I'm not saying I need to get it today; tomorrow is fine too. | 0.83 |
| 他可能只是没看到消息，别想太多。 | He might just not have seen the news, so don't overthink it. | 0.69 |
| 这个价格有点离谱，我们再看看吧。 | This price seems a bit outrageous, let's take a closer look. | 0.63 |

The idiom in row 2 means nothing is settled/it is too early to say; the output shifts that implication. Row 5 chooses “news” where “message” is more likely in an interpersonal context. Row 6 sounds fluent but “let's keep looking” better matches shopping elsewhere than “take a closer look.” These are model weaknesses, not passing semantic-quality assertions. A second pass should evaluate contextual dialogue and compare suitable local models before a learning-focused release. Do not silently rewrite model output using fixture-specific replacements.

The final prompt adds general guidance to preserve negation, temporal status, tentativeness, and an idiom's social intent, and to prefer everyday conversational interpretations when context is missing. A second run using that production prompt returned:

| Case | Final model output | Seconds |
| --- | --- | ---: |
| 1 | Don't worry, let's take it one step at a time. | 0.97 |
| 2 | This is just starting to unfold. | 0.51 |
| 3 | Don't stand me up. | 0.51 |
| 4 | I'm not saying I need it today; tomorrow is fine too. | 0.69 |
| 5 | He probably just didn't see the message, so don't worry about it too much. | 0.79 |
| 6 | This price seems a bit too high, let's take a closer look. | 0.71 |

The conversational sense of “message” improved, but case 2 remains inaccurate, case 6 remains too literal, and “probably” in case 5 conveys stronger confidence than “might.” Prompt refinement alone did not solve semantic fidelity. Both runs used isolated phrases without dialogue context and are not a broad model benchmark.

## Remaining manual acceptance checks

Build, XCTest, signature validation, local Swift inference, and basic launch now pass. Complete the following checks before calling live captions fully validated:

1. Verify app settings, controls, and history behavior in the running development bundle. The two test suites, release build, and basic launch check already pass.
2. Grant/deny/revoke Speech and Screen/System Audio Recording permissions; verify actionable errors and retry after relaunch. Confirm no microphone request or input indicator is caused by the app.
3. After authorization, verify actual local zh-CN transcription. The read-only capability probe already reports support, but test with network disconnected, then without the required model assets; unavailable assets must fail explicitly.
4. Play Mandarin in Safari and another native app. Verify the subtitle output is based on system audio while the microphone is muted/disconnected, and that protected content failures are handled.
5. Pause/resume/stop repeatedly during active capture, startup permission dialogs, silence, and slow translations. Old captions must not reappear and capture must stop.
6. Keep the app running over multiple 45-second recognition rotations, and during several minutes of silence. Check for gaps, duplicates, errors, resource leaks, and sustained CPU/memory usage.
7. Check the overlay on desktop, fullscreen apps, Spaces, changed display arrangements, different font sizes, opacity levels, and bilingual mode. Verify clicks pass through and captions remain readable.
8. Stop Ollama, select an absent model, enter a remote endpoint, and simulate slow/incomplete responses. Fail visibly without cloud fallback or an unbounded queue.
9. Review the quality fixtures and contextual dialogue for idioms, collocations, uncertainty, negation, names, tone, and added/omitted meaning. Record end-to-end latency separately from inference time.
10. Verify memory-only history limit, clear, explicit export/cancel, persistence of settings, menu bar controls after closing the main window, and clean quit.

## Future release checks

Embedded inference and app-managed downloads require offline tests with Ollama uninstalled, clean-account setup, model integrity/license/storage handling, hardware performance checks, signing/provisioning, notarization, and distribution testing. These have not been implemented.
