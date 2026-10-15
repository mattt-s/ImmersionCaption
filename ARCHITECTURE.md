# Architecture

ImmersionCaption uses a small MVVM-style presentation layer with a dedicated application coordinator and replaceable infrastructure adapters. The minimum runtime is macOS 14.2, which provides Core Audio process taps and system-audio-only authorization. Swift 5.9 is the minimum app compiler; the Foundation-only domain package also supports the initially installed Swift 5.3 tools.

## Responsibilities and dependencies

![ImmersionCaption architecture: presentation, caption session, domain policies, replaceable providers, local services, and planned standalone inference](docs/diagrams/architecture.svg)

[Open the full-size SVG](docs/diagrams/architecture.svg) · [PNG](docs/diagrams/architecture.png) · [Editable Mermaid source](docs/diagrams/architecture.mmd)

This is a component map, not a runtime sequence. Solid arrows show existing calls, observations, or policy dependencies. Each provider box pairs an application protocol with its current infrastructure adapter. The dashed arrow and gray section show the planned embedded replacement; they are not implemented. AppContainer assembles the current providers and settings and defers overlay creation until view startup. The sequence diagram below shows the actual audio-to-caption flow.

- **CaptionCore** has no UI, HTTP, Speech, Core Audio, Combine, or dependency on Ollama's transport. Its `TranslationPrompt` is a named TranslateGemma policy helper; other translation models can ignore it. Values and bounded queues remain provider-neutral.
- **Application/Ports.swift** defines `SystemAudioCapturing`, `SpeechRecognizing`, and `TranslationEngine`. Capture and speech exchange native `CMSampleBuffer` audio; the capture adapter copies HAL buffers into owning sample buffers without resampling. That boundary is intentionally macOS-specific; replaceable speech adapters must accept or convert these buffers. Transcript events carry provider-neutral `SpeechSegment` values (UTF-16 range, start time, duration), so the domain can find word gaps and keep lexical units intact. Providers may omit timings, using the text-only fallback. Translation values remain backend-independent.
- **CaptionSession** is the use-case coordinator and observable view model. It owns lifecycle, segmentation, draft stabilization, translation ordering, history, context, overload reporting, caption expiry, and cancellation.
- **Infrastructure/Audio** owns `CoreAudioTapCapture`: a private, unmuted global stereo process tap and a private aggregate containing only that tap. `NSAudioCaptureUsageDescription` requests system audio access. There is no display enumeration, ScreenCaptureKit dependency/fallback, physical input device, or microphone input. The existing HAL process object is excluded when available; this app produces no playback. The adapter reads the tap’s native PCM format and copies callback memory with `PCMBufferConverter`. A format-change listener stops the session if the format changes; unchanged notifications are ignored.
- **Infrastructure/Speech** manages local Mandarin recognition, synchronized audio append/request replacement, and periodic recognition request rotation. Runtime capability is checked before recognition; `requiresOnDeviceRecognition` is always true.
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
        Speech->>Session: Cumulative hypothesis + utterance ID
        Session->>Session: Segment / stabilize / enqueue
        Session->>Model: Phrase + last two translations
        Model-->>Session: Completed English translation
        Session->>Session: Check cancellation and generation
        Session->>UI: Caption and bounded history
    end
    User->>Session: Pause / Stop
    Session->>Session: Invalidate generation, cancel tasks, clear queue/context
    Session->>Capture: Release capture
    Session->>Speech: End audio and cancel recognition
    Session->>UI: Hide caption
```

## Concurrency and ownership

Presentation, settings, coordinator, and capture entry points are MainActor-isolated. Each `AudioTapRun` confines native setup/teardown and resource IDs to a serial control queue, keeping permission/device calls off MainActor. Core Audio invokes a separate serial sample queue synchronously. `PCMBufferConverter` copies HAL-owned interleaved or planar PCM into owning `CMSampleBuffer` data before the callback returns, retaining the native sample rate/channel format and advancing frame-based timestamps. A lock-protected `AudioTapOutput` serializes delivery with disable; the existing `SpeechAudioSink` serializes append with request replacement/endAudio. There is no unbounded task stream or disk audio storage. Conversion and format errors hop to MainActor once; stop suppresses queued failure delivery.

Apple recognition callbacks snapshot text/finality and dispatch onto MainActor. Session and request UUIDs reject callbacks after stop or request rotation. Session generation UUIDs reject translation results after pause, stop, failure, or restart, including providers that ignore cancellation. Transition counters prevent new starts during pending startup/teardown. The capture adapter has its own generation to handle cancellation during asynchronous setup/teardown. Stop disables delivery immediately, then stops/destroys the IOProc, removes the format listener, destroys the aggregate, and destroys the tap on the control queue. Partial startup failures follow the same cleanup path. Run resources are never reused by a later session.

One worker Task translates sequentially so context is ordered. At most three additional phrases wait; dropping the oldest pending phrase preserves newer dialogue at the expense of completeness. Stable-draft and caption-expiry Tasks are replaced/cancelled as appropriate. A failed backend visibly stops the pipeline; there is no retry storm or cloud fallback.

## Segmentation and latency tradeoffs

The legacy recognizer emits cumulative hypotheses and speech-unit timestamps; one unit can contain several words. `AppleSpeechRecognizer` requests automatic punctuation and copies units into `SpeechSegment` values before crossing to MainActor. Ranges reference the original formatted text in UTF-16; the domain validates them before converting to Swift string indices.

`TranscriptSegmenter` uses strong punctuation, sufficiently long comma/colon clauses, and gaps between recognized units. Short (default) targets 28 characters / 3.2 seconds with a 350 ms gap threshold; Balanced targets 44 / 4.5 seconds with a 450 ms threshold. Pauses require at least four characters; soft punctuation requires ten. Numeric separators are not clause boundaries. Size/time cuts prefer recognized boundaries; an oversized multiword unit or missing timings uses Foundation word tokenization, with a grapheme-boundary fallback. A long unbroken Latin proper name can exceed the target. A 650 ms unchanged draft or a final result flushes the remaining tail.

These cues bound phrase size without assuming that a short silence guarantees semantic completeness. They use ASR timing and text stability, not a raw-audio VAD or a second inference pass. Translations receive two earlier phrases as context and are prompted for concise, idiomatic language without dropping meaning.

Once committed, text is not retracted. If earlier text changes length, consumed word timestamps realign the pending text to already-heard audio; missing/all-zero timings use `TranscriptCursor` to align the consumed character boundary through a text diff. All-zero timestamps must not establish an audio watermark. The text fallback anchors on matched content characters, then adjacent separators: matching a common full stop at the end of newly appended text must not discard new speech. A fully rewritten transcript without anchors uses a conservative positional fallback. Revised/merged ASR word boundaries remain an edge case. Tests cover timing gaps, rapid continuous speech, proper names, earlier revisions, UTF-16/emoji, invalid ranges, numeric punctuation, stable flushes, and no lost source characters across bounded chunks.

Requests rotate after 45 seconds, flushing the most recent hypothesis and starting a new request. There is no overlap buffer, so transition audio loss remains possible. A future timestamp-aware segmentation/VAD pipeline can improve this without changing translation/UI contracts.

Non-streamed short translations avoid displaying incomplete English sentences and simplify the initial adapter. Warm fixture translation was subsecond locally; actual end-to-end latency remains unmeasured. Stable segmentation, model load time, speech rate, and recognition availability dominate the user experience. Larger models may improve fluency while increasing memory/latency; changing models must be evaluated with real listening sessions.

## Translation policy

The current adapter uses TranslateGemma's documented single user message, Chinese `zh-Hans` → English `en`, and its source separator. Guidance prioritizes natural conversational English, idiom meaning, tone, fidelity, and no added facts. Two previously translated pairs provide limited context, explicitly separated from the current source. The prompt requests one translation of the current fragment, no alternatives or repetition of context, no invented continuation, and preservation of narrative subjects. Temperature is 0 to reduce sampling variation; context changes and backend differences can still change wording. Output is accepted only after a complete nonempty response; token-limit truncation is an error. One response can legitimately contain multiple English sentences; it always creates just one caption entry.

Context can help ambiguous words but also propagate earlier mistakes. It is cleared on lifecycle transitions and when history is cleared. There is no claim that prompting guarantees semantic fidelity or native fluency. Human-reviewed regression fixtures record real weaknesses.

## Privacy boundary

The app does not configure a microphone and registers no microphone stream output. It never opens a screen-capture stream, stores no raw audio, and retains at most 300 captions in memory. History export is user initiated. Logs describe lifecycle/failure categories only, not recognized or translated content.

The Ollama adapter accepts explicit HTTP loopback URLs, disables proxy configuration, and rejects redirects. This confines the application's HTTP transport; a locally configured server could itself forward data. Users must run trusted Ollama with a genuinely local model. Initial setup/model downloads can require internet. Offline operation requires both Apple's language assets and the translation weights/runtime to be available beforehand.

## Replacing AI engines and becoming standalone

1. Implement `TranslationEngine.translate(_:)` using a compatible embedded runtime. It receives a provider-neutral source/context value and returns English, honoring cancellation. Put model-specific prompts/tokenization inside that adapter.
2. In AppContainer, replace OllamaTranslationEngine with the embedded adapter. CaptionSession, history, overlay, and tests remain unchanged.
3. If replacing Apple Speech with Whisper or another local recognizer, implement SpeechRecognizing. Convert input CMSampleBuffer format internally, perform inference off-main, return cumulative hypotheses with stable utterance IDs, include UTF-16 word ranges/timings where available, and enforce local-only behavior.
4. Add direct model management when an embedded backend is selected: manifests, source/license notices, storage location, size/free-space checks, integrity verification, interrupted-download handling, supported hardware/quantization, removal, and first-run readiness. None of these are implemented yet.
5. Package the runtime, permitted model assets or installer, entitlements, signing, and notarization into a distributable app. Validate with Ollama absent, network disabled, and a clean macOS account.

Standalone deployment is an architectural path, not a completed feature. The current app still requires Ollama and OS-managed speech assets.

## Verification boundaries

Domain XCTest sources and a compatibility runner exercise actual production rules, including timed segmentation. App XCTest sources cover timing propagation, lifecycle cancellation/generation races, overload/context ordering, recognition failure teardown, the HTTP request schema, invalid responses, endpoint validation, and deferred native-window creation. An opt-in integration test runs the real Swift Ollama adapter against installed TranslateGemma. Interactive permissions, overlay behavior, sustained speech, and end-to-end audio tests remain outstanding. See docs/VALIDATION.md for current test/build/launch evidence and the acceptance checklist.
