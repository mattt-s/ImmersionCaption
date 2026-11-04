# Current caption policy

Updated 2026-11-04 (Asia/Tokyo) for **0.5.0, captions only**. Recognized Mandarin is published directly; translation and its queue/context are removed. This document describes implemented behavior.

**Punctuation commits immediately, without stability confirmation.** Revision alignment follows consumed speech to reduce replay; it does not certify accuracy or amend old captions.

## Decision diagram

![Recognition-to-caption decisions](diagrams/caption-policy.svg)

[SVG](diagrams/caption-policy.svg) · [PNG](diagrams/caption-policy.png) · [Editable Mermaid](diagrams/caption-policy.mmd)

## Recognition events

[`AppleSpeechRecognizer`](../Sources/ImmersionCaption/Infrastructure/Speech/AppleSpeechRecognizer.swift) requires local zh-CN recognition, partial results, automatic punctuation, and the dictation hint. Each callback supplies cumulative text, actual isFinal, request ID, and optional UTF-16 ranges/timings through [`TranscriptEvent`](../Sources/ImmersionCaption/Application/Ports.swift). Confidence scores are not forwarded.

Obsolete callbacks are rejected. [`CaptionSession.receive`](../Sources/ImmersionCaption/Application/CaptionSession.swift) processes events while running, shows raw current-request text as **Hearing**, and calls the segmenter. Hearing includes consumed words and can change. Earlier request carry is internal to the segmenter.

## Boundary priority

[`TranscriptSegmenter`](../Packages/CaptionCore/Sources/CaptionCore/TranscriptSegmenter.swift) combines carry with current text, aligns consumption, and repeats these decisions on the remaining suffix:

| Priority | Condition | Action |
| --- | --- | --- |
| 1 | Sentence ending anywhere in pending text | Commit through the first ending, keeping earlier commas and adjacent closing quotes/brackets. |
| 2 | No sentence ending, actual isFinal true | Commit the entire remaining tail, including its commas. |
| 3 | No sentence ending, partial with eligible clause punctuation | Commit through the first comma/colon/semicolon at character position ten or later. |
| 4 | None of the above | Retain the unfinished suffix until another event supplies a boundary or real finality. |

Sentence endings are `。`, `！`, `？`, `!`, `?`, newline, and an eligible ASCII period. ASCII periods require following whitespace, an accepted closer, or end of text; listed English abbreviations/dotted initials are excluded. This is a heuristic parser.

Clause endings are `，`, `,`, `：`, `:`, `；`, and `;`. ASCII commas/colons immediately between numbers are excluded. Position counts Swift Character values from the pending start, including whitespace and candidate punctuation. Ten is a punctuation eligibility floor, not a maximum length. Punctuation-only slices advance consumption without publishing; emitted text is trimmed.

The scan checks the entire suffix for sentence endings before falling back to a clause. A punctuated partial can commit on its first callback. No repeated-hypothesis, confidence, timer, duration, gap, or VAD gate is applied.

## Examples

| Input | Actual final? | Newly published |
| --- | --- | --- |
| 老板见有了巴结的机会，立刻答应帮忙。 | No | Whole sentence, including comma. |
| 老板见有了巴结的机会，立刻答应 | No | 老板见有了巴结的机会， |
| Next update of same request: 老板见有了巴结的机会，立刻答应帮忙。 | No | 立刻答应帮忙。 The old clause is not merged back. |
| 谢谢，好的 | No | Nothing; comma is too early. |
| 今天我们讨论接下来应该怎么办 | No | Nothing, even after a long time unchanged. |
| 老板见有了巴结的机会，立刻答应帮忙 | Yes | Entire uncommitted utterance. |
| 第一件事。第二件事。还有未完成的内容 | No | Two history entries; overlay shows 第二件事。 Tail waits. |

## Revision alignment

After commitment, pendingStart chooses new speech using this priority:

1. Matching consumed text: skip the prefix.
2. Changed prefix with useful timing: skip segments starting before consumed end time minus 0.01 seconds, then adjacent punctuation/whitespace.
3. Missing/all-zero timing: [`TranscriptCursor`](../Packages/CaptionCore/Sources/CaptionCore/TranscriptCursor.swift) maps consumption through a text diff with unchanged content anchors/local separators. Fully rewritten text without anchors uses a bounded positional fallback.

UTF-16 ranges are validated. Timings align speech and never cause cuts. Legitimate repeated speech is not globally deduplicated. Revised/merged units can still cause lost/repeated text. Uncommitted tails can be revised; published captions are not repaired retroactively.

## Requests, publication, and lifecycle

The Apple adapter starts a request after a real final and rotates after 45 seconds. Maintenance cancels/replaces without inventing finality. On new request ID, beginUtterance carries unfinished text, resets anchors, and offsets new ranges by carry length. No overlapping audio buffer exists; text carry cannot recover unheard audio or re-recognize old audio.

Committed phrases become Caption(text:) synchronously on MainActor. No server call, inference task, context window, or pending queue remains. All phrases in one event enter history (newest 300), and the last becomes the overlay caption. This is not a paced playback queue.

Each publication replaces a 12-second expiry task. Expiry hides the display only. Six-line wrapping/scaling is separate from segmentation and may visually truncate long text. Export writes recognized text only. History survives stop/start until cleared or quit.

Pause/stop/failure/restart clears draft/carry/display. Generation checks reject old callbacks/expiry tasks. Stable-prefix/LocalAgreement confirmation, confidence scoring, VAD, SpeechAnalyzer finalized ranges, retroactive correction, and pagination are not implemented.

Domain tests cover punctuation, final tails, timing/revisions, and request carry. App tests cover direct publication, multi-phrase events, history bounds, stale callbacks, and lifecycle races. Synthetic fixtures do not establish real speech stability, quality, latency, permissions, or Spaces behavior. See [VALIDATION.md](VALIDATION.md) and [ARCHITECTURE.md](../ARCHITECTURE.md).
