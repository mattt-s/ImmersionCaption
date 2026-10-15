# Current caption policy: recognition, revisions, and translation

Code review date: 2026-10-16 (Asia/Tokyo). This document describes the implemented **0.4.0** policy, restored by commit `dc923e2` to the source tree of `80d9e9a`. It describes behavior rather than proposing a new implementation. Runtime code and the app version are unchanged by this documentation update.

**The app commits recognized punctuation immediately. It does not first confirm that a partial transcript is stable.** Revision alignment tries to follow speech already consumed; it neither certifies recognition stability nor corrects previously published translations.

## Decision diagram

![Current recognition-to-caption commitment policy](diagrams/caption-policy.svg)

[Full-size SVG](diagrams/caption-policy.svg) · [PNG](diagrams/caption-policy.png) · [Editable Mermaid](diagrams/caption-policy.mmd)

The boundary decision repeats until there is no further usable boundary in the current hypothesis. Collected phrases are then enqueued. The diagram abbreviates alignment and lifecycle details; the precise rules follow.

## 1. What the recognizer supplies

[`AppleSpeechRecognizer.beginRequest()`](../Sources/ImmersionCaption/Infrastructure/Speech/AppleSpeechRecognizer.swift) configures `SFSpeechRecognizer` for `zh-CN`, requires on-device recognition, enables partial results and automatic punctuation, and uses the dictation task hint.

Every callback snapshots the current cumulative `bestTranscription.formattedString`, actual `result.isFinal`, and speech-segment UTF-16 ranges/start times/durations into a [`TranscriptEvent`](../Sources/ImmersionCaption/Application/Ports.swift). Confidence scores are not forwarded. Session/request IDs reject obsolete callbacks; the session accepts transcript events only while running.

[`CaptionSession.receive(_:)`](../Sources/ImmersionCaption/Application/CaptionSession.swift) shows the event's text as `sourceDraft` (the **Hearing** text) and immediately calls the segmenter. Hearing is the current request's cumulative hypothesis, including already consumed text; it is not a stability indicator or just the pending translation tail. Any continuation carried from an earlier request is internal to the segmenter.

There is no requirement for repeated matching hypotheses, a stable-prefix score, a quiet period, or a minimum unchanged-text duration.

## 2. Exact boundary priority

[`TranscriptSegmenter.ingest(_:isFinal:segments:)`](../Packages/CaptionCore/Sources/CaptionCore/TranscriptSegmenter.swift) combines carried text with the current hypothesis, aligns the consumed boundary, then repeatedly applies these rules to the remaining suffix:

| Priority | Condition | Action |
| --- | --- | --- |
| 1 | Any recognized sentence ending exists in the pending suffix | Commit through the **first** sentence ending, including any earlier commas and immediately adjacent closing quotes/brackets. |
| 2 | No sentence ending exists, and this is a genuine final result | Commit the entire remaining suffix, including any commas. |
| 3 | No sentence ending exists, and this is a partial result with eligible clause punctuation | Commit through the **first eligible** comma, colon, or semicolon at character position 10 or later. |
| 4 | None of the above | Retain the text until another recognition event supplies a usable boundary or an actual final result. |

Sentence endings are `。`, `！`, `？`, `!`, `?`, newline, and an eligible ASCII period. An ASCII period must precede whitespace, an accepted closing quote/bracket, or the end of the hypothesis; the helper excludes its listed English abbreviations and dotted initials. These are code heuristics, not a complete linguistic parser.

Clause endings are `，`, `,`, `：`, `:`, `；`, and `;`. ASCII commas/colons immediately between numeric characters are excluded. The ten-character floor is counted with Swift `Character` values from the pending suffix's start, **including the candidate punctuation and any whitespace**. It is an eligibility threshold for punctuation, not a maximum caption size or a forced cut at character ten. An earlier ineligible short comma can be included in a later eligible clause.

The scan searches the entire available suffix for a sentence ending before falling back to a remembered clause boundary. A partial result can therefore be committed on its **first callback**, even with `isFinal == false`. Leading whitespace is trimmed from emitted phrases; punctuation-only/whitespace-only slices advance the consumed cursor but are not sent to translation.

### Examples of actual decisions

Examples below are independent unless the row explicitly continues the preceding row. Quotes around inputs are omitted; punctuation shown is part of the input.

| Input | Actual `isFinal` | Newly committed source |
| --- | --- | --- |
| 老板见有了巴结的机会，立刻答应帮忙。 | false | The entire sentence, including its comma. |
| 老板见有了巴结的机会，立刻答应 | false | 老板见有了巴结的机会， |
| Next update of that same request: 老板见有了巴结的机会，立刻答应帮忙。 | false | 立刻答应帮忙。 The earlier clause cannot be merged back. |
| 谢谢，好的 | false | Nothing; its comma is before the minimum position. |
| 今天我们讨论接下来应该怎么办 | false | Nothing, even if unchanged for a long time. |
| 老板见有了巴结的机会，立刻答应帮忙 | true | The entire uncommitted utterance, including its comma. |
| 第一件事。第二件事。还有未完成的内容 | false | Two phrases: 第一件事。 and 第二件事。 The tail waits. |

These examples match the existing boundary tests. They describe source-text segmentation, not model-generated English wording.

## 3. How revisions are followed

The segmenter records a consumed prefix and, when usable speech timings exist, a consumed audio end time. On a later cumulative hypothesis, `pendingStart()` applies this order:

1. **Exact prefix still matches:** start immediately after the already committed prefix.
2. **Prefix changed and usable timing exists:** use segments starting before the consumed end time minus 0.01 seconds, move past their text ranges, then skip adjacent punctuation/whitespace. This is a timing-based alignment heuristic.
3. **Useful timing is absent, including all-zero timing:** use [`TranscriptCursor.align`](../Packages/CaptionCore/Sources/CaptionCore/TranscriptCursor.swift) to map the consumed character boundary through a text diff. It uses unchanged content characters as anchors and then follows local separators. With no reliable content anchor, it retains a bounded positional fallback rather than replaying the whole transcript.

Ranges are validated before conversion from UTF-16 to Swift string indices. Timings locate consumed speech; they never trigger sentence cuts. Repeated phrases are not globally deduplicated, because a speaker can legitimately repeat the same words.

This is **replay avoidance after commitment**. It does not wait for agreement before commitment. Revisions to an uncommitted tail replace that tail, but revisions to text already sent to translation do not retract, amend, or automatically retranslate the old caption. Ambiguous text diffs and revised/merged speech timing units can still misalign the boundary, causing lost or repeated text.

## 4. Recognition-request transitions

The Apple adapter starts a new request after an actual final result and performs a maintenance rotation after 45 seconds. Maintenance cancels the old task and replaces the request; it does not synthesize `isFinal == true` or flush text as a completed utterance.

When a transcript event with a different request ID arrives, `beginUtterance()` carries only the previously uncommitted tail, resets revision/timing state, and prefixes that tail to the new request's cumulative text. New request UTF-16 ranges are offset by the carried text length. A genuine final result normally leaves no substantive tail to carry.

There is no overlapping audio buffer during replacement. Carrying recognized text does not recover audio that was never recognized, and the next request cannot re-recognize the carried tail from its original audio.

## 5. Queue, translation, and display

Commitment advances the segmenter's consumed boundary **before** successful translation. The session uses a [`BoundedQueue`](../Packages/CaptionCore/Sources/CaptionCore/BoundedQueue.swift) with capacity three pending phrases and one separate in-flight translation. Overflow discards the oldest pending phrase and increments the skipped count; discarded phrases are not automatically recovered.

One worker sends each phrase plus the last two successful source/translation pairs to [`OllamaTranslationEngine`](../Sources/ImmersionCaption/Infrastructure/Translation/OllamaTranslationEngine.swift). The [`prompt`](../Packages/CaptionCore/Sources/CaptionCore/TranslationPrompt.swift) requests one faithful, natural English translation of the current fragment, with context for reference only. Requests use `stream: false`, temperature 0, a 4096-token context setting, and a 384-token output limit. A complete nonempty response is required; truncation is an error. One response creates one caption entry even if its English contains multiple sentences.

The session checks cancellation/generation before publishing. A successful translation becomes the current caption and is appended to memory-only history (maximum 300 entries). Caption expiry after 12 seconds only hides the current display; it neither finalizes speech nor triggers translation. Display wrapping/scaling does not choose source boundaries.

Pause, stop, failure, and restart invalidate work and discard pending/carry text and translation context; late callbacks/results cannot publish into the new generation. History remains until cleared or the process exits. A failure visibly ends processing rather than silently retrying.

The manual **Translate sample** path bypasses speech segmentation and enqueues the trimmed nonempty sample as one source input.

## Implemented versus researched

| Mechanism | Current 0.4.0 behavior |
| --- | --- |
| Punctuation-based sentence priority and clause fallback | Implemented; may commit provisional text immediately. |
| Actual `isFinal` handling | Implemented as a remaining-tail flush; it is not the gate for all translations. |
| Timing/text-diff revision alignment | Implemented after commitment; heuristic replay avoidance. |
| Stable-prefix / LocalAgreement confirmation | Not implemented. |
| Confidence-based stability scoring | Not implemented; confidence is not carried in transcript events. |
| VAD or silence-based finalization | Not implemented. |
| Character/duration/gap/unchanged-text forced cuts | Not implemented in 0.4.0. |
| `SpeechAnalyzer` / `SpeechTranscriber` and finalized audio ranges | Researched, not integrated. |
| Retroactive correction of translated captions | Not implemented. |

## Existing verification and limits

[`TimedSegmentationTests`](../Packages/CaptionCore/Tests/CaptionCoreTests/TimedSegmentationTests.swift) covers sentence priority, permitted partial clauses, genuine final tails, long input, numeric punctuation, quotes, and the absence of pause/duration cuts. [`TranscriptReplayTests`](../Packages/CaptionCore/Tests/CaptionCoreTests/TranscriptReplayTests.swift) covers revision alignment, zero timings, and legitimate repeats. [`UtteranceContinuationTests`](../Packages/CaptionCore/Tests/CaptionCoreTests/UtteranceContinuationTests.swift) covers request carry and timing/UTF-16 offsets. [`CaptionSessionTests`](../Tests/ImmersionCaptionTests/CaptionSessionTests.swift) covers request continuity, waiting on unpunctuated drafts, lifecycle cancellation, and overload.

Those tests establish the specified rules for synthetic inputs. They do not establish that Apple partial results are stable, that every clause is semantically complete, or that real continuous speech has a particular latency. See [VALIDATION.md](VALIDATION.md) for recorded verification, and [ARCHITECTURE.md](../ARCHITECTURE.md) for the component architecture.
