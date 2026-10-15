# Architecture

ImmersionCaption uses a small MVVM-style presentation layer with a dedicated application coordinator and replaceable infrastructure adapters. The minimum runtime is macOS 14.2, which provides Core Audio process taps and system-audio-only authorization. Swift 5.9 is the minimum app compiler; the Foundation-only domain package also supports the initially installed Swift 5.3 tools.

## Responsibilities and dependencies

![ImmersionCaption architecture: presentation, caption session, domain policies, replaceable providers, local services, and planned standalone inference](docs/diagrams/architecture.svg)

[Open the full-size SVG](docs/diagrams/architecture.svg) · [PNG](docs/diagrams/architecture.png) · [Editable Mermaid source](docs/diagrams/architecture.mmd)

This is a component map, not a runtime sequence. Solid arrows show existing calls, observations, or policy dependencies. Each provider box pairs an application protocol with its current infrastructure adapter. The dashed arrow and gray section show the planned embedded replacement; they are not implemented. AppContainer assembles the current providers and settings and defers overlay creation until view startup. The sequence diagram below shows the actual audio-to-caption flow.

- **CaptionCore** has no UI, HTTP, Speech, Core Audio, Combine, or dependency on Ollama's transport. Its `TranslationPrompt` is a named TranslateGemma policy helper; other translation models can ignore it. Values and bounded queues remain provider-neutral.
- **Application/Ports.swift** defines `SystemAudioCapturing`, `SpeechRecognizing`, and `TranslationEngine`. Capture and speech exchange native `CMSampleBuffer` audio; the capture adapter copies HAL buffers into owning sample buffers without resampling. That boundary is intentionally macOS-specific; replaceable speech adapters must accept or convert these buffers. Transcript events carry a request ID, cumulative text, and the recognizer's actual final flag. Timings and native recognition types do not cross this boundary; the application never reconstructs a finalized result from drafts. Translation values remain backend-independent.
- **CaptionSession** is the use-case coordinator and observable view model. It owns lifecycle, final-result gating and duplicate tracking, translation ordering, history, context, overload reporting, caption expiry, and cancellation.
- **Infrastructure/Audio** owns `CoreAudioTapCapture`: a private, unmuted global stereo process tap and a private aggregate containing only that tap. `NSAudioCaptureUsageDescription` requests system audio access. There is no display enumeration, ScreenCaptureKit dependency/fallback, physical input device, or microphone input. The existing HAL process object is excluded when available; this app produces no playback. The adapter reads the tap’s native PCM format and copies callback memory with `PCMBufferConverter`. A format-change listener stops the session if the format changes; unchanged notifications are ignored.
- **Infrastructure/Speech** manages local Mandarin recognition, PCM activity measurement, pause-triggered native request finishing, synchronized audio append, and a bounded audio handoff buffer. `SpeechPauseDetector` is a pure domain policy; native PCM parsing stays in `PCMActivityMeter`. Runtime capability is checked before recognition; `requiresOnDeviceRecognition` is always true.
- **Infrastructure/Translation** owns Ollama JSON, HTTP timeouts, loopback restriction, redirect rejection, completion validation, and error mapping. It does not choose UI state or store history.
- **Infrastructure/Persistence** stores appearance and backend preferences in UserDefaults. History and audio are not automatically persisted.
- **Presentation** observes session/settings. Its click-through panel handles Spaces/fullscreen positioning separately from the content views. Views invoke coordinator methods and do not construct inference adapters.
- **AppContainer** assembles concrete dependencies once. A view task creates the overlay after dependency resolution has finished, avoiding nested hosting-graph creation during SwiftUI StateObject initialization. It retains that overlay even when the main window is closed. The menu bar remains usable.

There is one source-level app module and one local domain package. More packages, repositories, generic pipeline frameworks, or an unused model-manager abstraction would add little value at this stage.

## Data flow

```mermaid
sequenceDiagram
    participant User
    participant Session as CaptionSession (MainActor)
    participant Capture as Core Audio process tap
    participant Speech as On-device Speech
    participant Model as Local translation engine
    participant UI as Overlay / History
    User->>Session: Start
    Session->>Speech: Authorize and require local Mandarin
    Session->>Capture: Authorize system audio / start private tap
    loop While running
        Capture->>Speech: CMSampleBuffer (capture queue)
        opt Recognized speech followed by sustained quiet
            Speech->>Speech: End input atomically / finish request
            Capture->>Speech: Buffer new audio while awaiting final
        end
        Speech->>Session: Request ID + text + actual isFinal
        alt Partial result
            Session->>UI: Hearing draft only
        else Final result
            Session->>Session: FinalTranscriptGate / enqueue whole result once
            Session->>Model: Final text + last two translations
            Model-->>Session: Completed English translation
            Session->>Session: Check cancellation and generation
            Session->>UI: Caption and bounded history
            Speech->>Speech: Begin next request / replay buffered audio
        end
    end
    User->>Session: Pause / Stop
    Session->>Session: Invalidate generation, cancel tasks, clear queue/context
    Session->>Capture: Release capture
    Session->>Speech: End audio and cancel recognition
    Session->>UI: Hide caption
```

## Concurrency and ownership

Presentation, settings, coordinator, and capture entry points are MainActor-isolated. Each `AudioTapRun` confines native setup/teardown and resource IDs to a serial control queue, keeping permission/device calls off MainActor. Core Audio invokes a separate serial sample queue synchronously. `PCMBufferConverter` copies HAL-owned interleaved or planar PCM into owning `CMSampleBuffer` data before the callback returns, retaining the native sample rate/channel format and advancing frame-based timestamps. A lock-protected `AudioTapOutput` serializes delivery with disable. `SpeechAudioSink` serializes append/endAudio, session-token checks, and ordered replay of its bounded in-memory audio handoff buffer. There is no unbounded task stream or disk audio storage. Conversion and format errors hop to MainActor once; stop suppresses queued failure delivery.

Apple recognition callbacks snapshot text/finality and dispatch onto MainActor. Session and request UUIDs reject callbacks after stop or after a request has completed and been replaced; a finishing request remains valid until its real final callback or failure. Session generation UUIDs reject translation results after pause, stop, failure, or restart, including providers that ignore cancellation. Transition counters prevent new starts during pending startup/teardown. The capture adapter has its own generation to handle cancellation during asynchronous setup/teardown. Stop disables delivery immediately, then stops/destroys the IOProc, removes the format listener, destroys the aggregate, and destroys the tap on the control queue. Partial startup failures follow the same cleanup path. Run resources are never reused by a later session.

One worker Task translates sequentially so context is ordered. At most three additional phrases wait; dropping the oldest pending phrase preserves newer dialogue at the expense of completeness. The caption-expiry Task is replaced/cancelled as appropriate; there is no stable-draft translation timer. A failed backend visibly stops the pipeline; there is no retry storm or cloud fallback.

## Final-result policy and latency

`CaptionSession` always updates the Hearing preview from recognition events, but only `isFinal == true` can pass `FinalTranscriptGate` into the translation queue. The gate accepts the whole finalized text once, trimming surrounding whitespace only, and remembers up to 128 completed IDs. The native adapter additionally rejects retired-request callbacks. Tracking resets with the session. Different request IDs can contain the same spoken words; no global text deduplication is performed. Manual Translate sample is an explicit text-only path outside the speech gate.

The previous `TranscriptSegmenter`, `TranscriptCursor`, and `SpeechSegment` types and their draft-alignment paths were removed. No partial punctuation, character count, word timing, or draft-stability timer supplies translation input. A pause ends native audio input, not a substring of a draft. There is no cross-request concatenation of draft text. Finalized input can contain several sentences and is sent intact.

The Apple adapter maps native `result.isFinal` unchanged. Partials update Hearing and confirm that the current request actually contains recognized speech; the sink checks both session and request tokens. `PCMActivityMeter` measures normalized RMS on each channel and takes the loudest channel, avoiding phase cancellation in stereo. It supports packed little-endian float32/64 and signed int16/32, interleaved or planar, and rejects invalid/nonfinite PCM. It reads Core Media's retained audio planes without copying the PCM payload. Only scalar activity measurements leave this parser.

`SpeechPauseDetector` requires at least 200 ms of audio activity, then one continuous second below -45 dBFS. Activity resets the quiet counter; leading silence and brief word gaps do not end requests. A 100 ms MainActor monitor asks the sink whether this request can end, also recognizing a one-second absence of new buffers using a monotonic clock. Under the append lock, the sink checks recognized-speech presence and current tokens, ends audio, and detaches the request before later buffers can arrive. The adapter calls `SFSpeechRecognitionTask.finish()` and keeps the request/session token valid while awaiting the actual final. It cancels pause monitoring when finishing, replacing, or stopping a request. The 45-second maintenance finish remains a safeguard for continuous input and can land mid-sentence; it is not a semantic boundary. Only a genuine final starts the next request. Finalization has a 10-second deadline; a missing final or native error stops the session rather than translating a draft.

During finishing, capture continues into `SpeechAudioSink`'s owning PCM buffer (maximum 12 seconds / 2,048 sample buffers), with each buffer's RMS/duration. Under the same lock, the next request receives those buffers in capture order before subsequent live samples. Replayed activity contributes to its pause detector, but speech confirmation resets and must come from that new recognizer. Buffered speech can span multiple pauses and be grouped into a larger final result. Session tokens prevent old receivers from appending into a restarted session. Invalid sample timing/PCM or overflow reports failure once; stop clears all queued audio and endpoint state. Only one native recognition request is active at a time, avoiding parallel-recognizer resource contention. The handoff stays in memory; no captured audio is saved or played back.

For a detected pause, the request finishes after about 1–1.1 seconds of quiet, plus any delayed speech confirmation, native finalization, buffered handoff, and inference. Energy detection is not a learned VAD or grammatical sentence detector: background music/noise can prevent quiet, soft speech can fall below the threshold, and a speaker may pause mid-sentence. Continuous input can still wait roughly 45 seconds. `isFinal` indicates completed recognition, not semantic completeness or guaranteed word accuracy. Sustained handoff and real material require listening validation. Long finalized segments can exceed the model's context/output limits or the bounded subtitle panel; pagination and model-context management remain future work.

Domain tests exercise pause policy, final gating, full-input fidelity, duplicate tracking, empty finals, legitimate repeated speech, and session reset. App tests cover PCM representations/phase cancellation, pause/stalled-input ending, retired tokens, speech confirmation reset, revised draft preview without translation, lifecycle races, and bounded audio replay/stop behavior. Non-streamed translation responses are published only when completed; recognition finality and model response completion are independent checks.

## Translation policy

The current adapter uses TranslateGemma's documented single user message, Chinese `zh-Hans` → English `en`, and its source separator. Guidance prioritizes natural conversational English, idiom meaning, tone, fidelity, and no added facts. Two previously translated pairs provide limited context, explicitly separated from the current source. The prompt requests one translation of the current fragment, no alternatives or repetition of context, no invented continuation, and preservation of narrative subjects. Temperature is 0 to reduce sampling variation; context changes and backend differences can still change wording. Output is accepted only after a complete nonempty response; token-limit truncation is an error. One response can legitimately contain multiple English sentences; it always creates just one caption entry.

Context can help ambiguous words but also propagate earlier mistakes. It is cleared on lifecycle transitions and when history is cleared. There is no claim that prompting guarantees semantic fidelity or native fluency. Human-reviewed regression fixtures record real weaknesses.

## Privacy boundary

The app does not configure a microphone and registers no microphone stream output. It never opens a screen-capture stream or stores captured audio, and retains at most 300 captions in memory. History export is user initiated. Logs describe lifecycle/failure categories only, not recognized or translated content. The explicit `--check-speech` developer mode accepts a generated test file, does not prepare the overlay or start capture, writes metadata only, and exits that test instance. Its script removes the temporary synthesized audio afterward.

The Ollama adapter accepts explicit HTTP loopback URLs, disables proxy configuration, and rejects redirects. This confines the application's HTTP transport; a locally configured server could itself forward data. Users must run trusted Ollama with a genuinely local model. Initial setup/model downloads can require internet. Offline operation requires both Apple's language assets and the translation weights/runtime to be available beforehand.

## Replacing AI engines and becoming standalone

1. Implement `TranslationEngine.translate(_:)` using a compatible embedded runtime. It receives a provider-neutral source/context value and returns English, honoring cancellation. Put model-specific prompts/tokenization inside that adapter.
2. In AppContainer, replace OllamaTranslationEngine with the embedded adapter. CaptionSession, history, overlay, and tests remain unchanged.
3. If replacing Apple Speech with Whisper or another local recognizer, implement SpeechRecognizing. Convert input CMSampleBuffer format internally, perform inference off-main, return cumulative draft/final events with stable request IDs and a genuine final flag, finish requests without fabricating finals, and enforce local-only behavior.
4. Add direct model management when an embedded backend is selected: manifests, source/license notices, storage location, size/free-space checks, integrity verification, interrupted-download handling, supported hardware/quantization, removal, and first-run readiness. None of these are implemented yet.
5. Package the runtime, permitted model assets or installer, entitlements, signing, and notarization into a distributable app. Validate with Ollama absent, network disabled, and a clean macOS account.

Standalone deployment is an architectural path, not a completed feature. The current app still requires Ollama and OS-managed speech assets.

## Verification boundaries

Domain XCTest sources and a compatibility runner exercise final gating, pause policy, bounded queues, translation prompts, and loopback policy. App XCTest sources cover audio activity, pause/handoff lifecycle, final-only submission/history, revised drafts, whole-input fidelity, duplicate finals, cancellation, HTTP contracts, and deferred native-window creation. An opt-in integration test runs the real Swift Ollama adapter. XCTest does not run Apple's recognition model. The separate `scripts/check-speech.sh` runs production native recognition on two temporary synthetic Mandarin utterances with pauses inside the signed app, requiring two genuine finals before maintenance and a final during continued feeding. It requires existing app authorization, uses no capture/microphone/Ollama, and reports counts/timing only. Interactive permission flows, actual system audio, sustained handoff, and perceived latency remain device checks. See docs/VALIDATION.md for current evidence.
