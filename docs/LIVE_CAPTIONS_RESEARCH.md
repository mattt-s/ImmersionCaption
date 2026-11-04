# Live Captions research and implementation decisions

Researched on 2026-11-04 (Asia/Tokyo), before changing the 0.5.0 display policy.

## Primary sources

- [Apple: Get captions of spoken and computer audio on Mac](https://support.apple.com/en-hk/guide/mac-help/mchldd11f4fd/mac): describes real-time, on-device captions, scrollable text, pause/resume, appearance controls, automatic hiding without audio, and Keep Onscreen. Language/device availability varies.
- [Apple: supportedLocales](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportedlocales%28%29?language=objc): enumerates recognized locales, but does not guarantee current recognition availability or offline support.
- [Apple: supportsOnDeviceRecognition](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition): identifies whether a recognizer can operate locally. The app still explicitly requires on-device recognition on every request.
- [Apple: SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer): a recognizer uses one selected locale. A language menu therefore selects the spoken input language rather than enabling automatic language detection.

## What is known and what is inferred

Apple's user guide describes visible behavior, not the internal recognition engine, hypothesis-commit algorithm, silence thresholds, or buffering policy. It does not establish that the public SFSpeechRecognizer API is the Live Captions engine. We do not claim to reproduce Apple's internals or accuracy.

Our implementation interprets a real-time rolling transcript as immediate partial display, replacement of revisions in place, and natural wrapping/scrolling. This is an application design decision, supported by the existing recognizer's cumulative partial-result contract. It does not require finality or sentence boundaries before display.

## Implemented choices (0.6.x, positioning in 0.7.0, line choices in 0.7.1)

| Concern | Choice |
| --- | --- |
| Spoken language | Native menu in the main window, settings, and menu bar; options are discovered from Apple Speech. |
| Offline availability | Options without on-device support are hidden (updated in 0.6.1); capability/availability is checked again on start. Missing assets require macOS Dictation setup and app reopening. |
| Language transition | Pause or stop first, select a language, then resume/start. Capture and recognition share the normal lifecycle cleanup path. |
| Partial results | Show the latest text immediately; earlier words can be replaced or deleted. |
| Repeated callbacks | Replace the same request entry; unchanged callbacks do not create entries or reset idle display time. |
| Final results | Mark the existing entry final. Finality is metadata, not a display gate. |
| Rolling layout | Recent three request blocks wrap at the selected font size in a native text scroll view. Since 0.7.1, Settings chooses one, two, or three visible wrapped lines (default three), without truncating the buffered text. Follow live scrolls to the newest text; turn it off to review. |
| History | Latest 300 request snapshots in memory, revised in place. This is not a word-by-word event log or a list of punctuation-delimited sentences. |
| Idle window | Since 0.6.2, passively measure captured PCM and hide the whole panel after about one second of silence. Resume visibility only with changed recognized text and recent audio. This threshold/grace is our own heuristic. Keep Onscreen was removed at the user's request. |
| Interaction | Interactive overlay by default; locked click-through hides the header/Follow live toggle and enables automatic following. A separate corner lock button stays clickable. Unlocking is our explicit editing mode: keep visible, accept mouse input, and drag a dedicated handle. Relock restores normal hiding/click-through. Explicit preview is limited to non-running states. |
| Position | Native AppKit dragging saves a validated display-relative top-left anchor; presets clear the custom location. Restore within visible screen bounds after monitor changes. Every launch starts locked. These are our positioning choices, not a claim about Apple's private implementation. |
| Request limits | Retain the legacy 45-second rotation. A new request starts a new block; no invented finality or old-text concatenation. Audio overlap buffering remains unimplemented. |

No translation, network speech fallback, new inference runtime, microphone input, screen capture, or automatic language detection is introduced. See [current policy](CAPTION_POLICY.md), [architecture](../ARCHITECTURE.md), and [verification record](VALIDATION.md).
