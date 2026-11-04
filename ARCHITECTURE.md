# Architecture

ImmersionCaption 0.5.0 is a native Mandarin caption app for macOS 14.2+. It has an MVVM-style presentation layer, an application coordinator, a Foundation-only domain package, and replaceable capture/speech adapters. There is no translation module, HTTP client, inference service, prompt, or translation queue.

## Components

![Caption-only architecture](docs/diagrams/architecture.svg)

[SVG](docs/diagrams/architecture.svg) · [PNG](docs/diagrams/architecture.png) · [Editable Mermaid](docs/diagrams/architecture.mmd)

- **CaptionCore:** `Caption` holds recognized `text`, identity, and creation time; `SessionState` defines lifecycle policy. `TranscriptSegmenter`, `TranscriptCursor`, and `SpeechSegment` implement punctuation, request carry, and revision alignment. No UI, networking, or native audio/speech dependency.
- **Application/Ports.swift:** `SystemAudioCapturing` delivers owning `CMSampleBuffer` values. `SpeechRecognizing` consumes those buffers and emits cumulative `TranscriptEvent` values containing request ID, actual finality, and optional provider-neutral UTF-16 ranges/timings. Adapters handle audio conversion internally.
- **CaptionSession:** MainActor coordinator for lifecycle, segmentation, direct publication, memory-only history, expiry, and stale-callback rejection. Committed phrases become `Caption(text:)` values synchronously without a backend task or work queue.
- **Infrastructure/Audio:** `CoreAudioTapCapture` owns a private, unmuted global stereo tap and private tap-only aggregate. HAL setup/cleanup uses a serial control queue. `PCMBufferConverter` copies callback memory. Format changes and conversion failures stop processing visibly.
- **Infrastructure/Speech:** `AppleSpeechRecognizer` requires on-device `zh-CN`, requests partial results/punctuation, snapshots callbacks, and rotates legacy requests. Its locked sink synchronizes append with replacement/endAudio. Cloud fallback is disabled.
- **Infrastructure/Persistence:** `AppSettings` stores font size, opacity, and position; preview is transient. Retired backend/bilingual keys are removed on initialization. Audio/history are not automatically persisted.
- **Presentation:** SwiftUI controls/settings/history observe the session. A click-through AppKit panel hosts recognized text across Spaces/fullscreen. Explicit export writes recognized text only.
- **AppContainer:** Chooses concrete capture/speech providers and owns presentation. Overlay construction waits for view startup to avoid nested SwiftUI graph initialization.

## Data flow

```mermaid
sequenceDiagram
    participant User
    participant Session as CaptionSession (MainActor)
    participant Capture as Core Audio tap
    participant Speech as On-device Apple Speech
    participant UI as Overlay and history
    User->>Session: Start captions
    Session->>Speech: Authorize and require local Mandarin
    Session->>Capture: Authorize system audio and start tap
    loop While running
        Capture->>Speech: Owning CMSampleBuffer
        Speech->>Session: Cumulative text, ID, finality, timings
        Session->>Session: Align consumption and select punctuation boundaries
        Session->>UI: Publish recognized phrases directly
    end
    User->>Session: Pause or stop
    Session->>Session: Invalidate generation, clear draft/carry, cancel expiry
    Session->>Speech: End audio and cancel recognition
    Session->>Capture: Release resources
    Session->>UI: Hide current caption; retain history
```

The [policy walkthrough](docs/CAPTION_POLICY.md) explains exact priority and examples. A punctuated partial can commit immediately. Revision alignment reduces replay; it does not establish stability or correct past captions. Only genuine finality can flush an unpunctuated tail.

## Concurrency and lifecycle

Presentation/settings/session use MainActor. Capture has dedicated serial control/sample queues. HAL buffers are copied before returning and never saved to disk. `AudioTapOutput` synchronizes delivery/disable and suppresses queued failures after stop; `SpeechAudioSink` synchronizes append with request replacement/endAudio.

Session/request UUIDs reject obsolete callbacks. Coordinator generation IDs invalidate callbacks and expiry tasks. Transition counters prevent overlapping starts during permission/teardown. Delayed permission cannot revive a stopped session. Capture has its own generation and partial-setup cleanup.

Every committed phrase enters history, capped at 300; the last phrase in a multi-phrase event becomes the overlay caption. A publication replaces the 12-second expiry task. There is no pending queue or inference latency. Pause/stop/failure clears display and carry while retaining history. Unexpected errors stop processing visibly, without retry loops or cloud fallback.

## Replacing recognition and operating offline

Implement `SpeechRecognizing` and select the adapter in AppContainer. Accept/convert audio internally, perform inference off MainActor, and emit cumulative hypotheses with request IDs, actual finality, and UTF-16 timings where available. Domain/views remain independent of Apple's recognition types. Delta/range-finalized results need an adapter or an explicit transcript-contract update.

The current engine uses OS-managed language assets; initial downloads may need internet, but recognition requires local support. Direct asset management and alternative embedded speech runtimes remain unimplemented. Do not describe legacy cumulative partials as having native stability guarantees.

## Privacy and verification

Permissions are Speech Recognition and System Audio Recording. The app does not capture screens, open a microphone input, change default devices, or send transcripts to a network service. Protected audio may be unavailable. Logs contain lifecycle/error categories only. History is memory-only until explicitly exported.

Domain tests cover punctuation, revisions, carry, and caption values. App tests cover direct publication, history limits, settings migration, lifecycle races, deferred native startup, and PCM ownership. Synthetic tests do not prove live permissions, speech quality, or Spaces behavior. See [VALIDATION.md](docs/VALIDATION.md).
