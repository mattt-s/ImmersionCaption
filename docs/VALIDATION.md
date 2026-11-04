# Validation record

## 0.5.0: captions only — 2026-11-04 (Asia/Tokyo)

Removed translation adapters/ports, prompt/endpoint policies, inference queue/context, backend UI/preferences, bilingual display, sample translation, smoke tooling, and model integration tests. Recognized Mandarin is published directly as Caption(text:). Existing punctuation/revision/request-continuation rules are retained. Appearance, history/export, menu controls, native capture, and deferred overlay startup remain.

Verified for this implementation:

- **31 CaptionCore tests and 25 application tests passed: 56 total, zero failures.** Coverage includes immediate recognized-text publication, all phrases in multi-phrase callbacks, 300-entry history retention, obsolete callbacks, permission/startup/stop races, request carry, zero-timed revisions, settings migration, PCM ownership, and native startup deferral.
- The Foundation-only compatibility runner passed **10 production-domain checks**.
- Release build and ad-hoc signature verification passed; the bundle reports version **0.5.0, build 6**. Resource property lists validate.
- The new-instance launch check passed: the app retained a visible application window for two seconds. The check leaves it open and does not start recording.
- Both Mermaid diagrams rendered from their updated sources. SVG XML and 23 local documentation links validate; PNGs were visually inspected for clipping/overlapping labels.
- Source review found no remaining translation engine/port, HTTP request adapter, prompts, or inference queue. Legacy preference-key cleanup and artwork provenance mention the removed feature intentionally; Core Audio's TranslatePIDToProcessObject property is unrelated to language translation.

Earlier release evidence remains in Git history and is not evidence for this implementation.

Interactive acceptance is still required for Speech Recognition/System Audio Recording permissions, Mandarin asset readiness, continuous playback, pause/resume, output-device changes, Spaces/fullscreen appearance, and recognition quality. Synthetic fixtures and process/window metadata do not establish those behaviors.
