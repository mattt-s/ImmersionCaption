# Validation record

## 0.7.1: maximum visible caption lines — 2026-11-04 (Asia/Tokyo)

Added Settings → Maximum caption lines: One, Two, or Three, defaulting to Three. The saved choice resizes the caption viewport and panel immediately. The three-request rolling buffer and 300-block history remain unchanged. CaptionTextView uses native TextKit wrapping with shared CaptionTextMetrics for uniform line fragments and whole-line viewport sizing; following shows the newest lines while manual review keeps full buffered text available.

**Verified for 0.7.1, build 11:**

- **40 app tests and 13 domain tests passed: 53 total, zero failures.** New native TextKit checks count visible full line fragments for all three choices, font sizes 16/28/52, English, and Chinese with emoji. They also check full-text preservation, following versus manual review, width/height changes, preference defaults/persistence/invalid values, and custom top-left preservation while the panel shrinks from three lines to one.
- **11 production-domain compatibility checks passed.** The release bundle built, passed ad-hoc signature verification, and passed the new-instance launch/window check without starting capture.
- A temporary native view-rendering probe produced one/two/three-line PNGs from synthetic text for visual inspection, without screen/audio recording. The probe was removed afterwards. This is own-view rendering evidence, not a live playback or physical scrolling check.
- Architecture and policy diagrams were regenerated to SVG/PNG and visually inspected. Documentation links, SVG XML, privacy/version property lists, shell syntax, and Git whitespace checks passed.

The initial compile required explicitly qualifying a CGFloat size constant; no compile/test failures remain. Live multilingual playback, manual review scrolling, and UI behavior across actual monitor/Spaces transitions still require interactive acceptance. No recognition or permission changes are introduced.

## 0.7.0: lockable draggable overlay — 2026-11-04 (Asia/Tokyo)

Added a corner lock button, native drag handle, menu/settings positioning command, saved custom display-relative top-left anchors, preset reset, and screen-bound restoration. Unlocked positioning intentionally stays visible and interactive; relocking restores the saved click-through preference and normal silence/preview policy. Recognition callbacks no longer reset an already-visible frame.

**Verified for 0.7.0, build 10:**

- **36 app tests and 13 domain tests passed: 49 total, zero failures.** New checks cover negative-origin display round trips, top-edge preservation when control/font height changes, smaller fallback screens, oversized/offscreen frames, invalid anchors, legacy preference migration, custom persistence, preset reset, and transient unlock state. Native panel fixtures verify click-through restoration, stopped-session visibility, child attachment after hide/reveal, movement with the parent, and no snapping on speech revisions. Fixtures capture no audio and request no permissions.
- **11 production-domain compatibility checks passed.** Debug/release builds, ad-hoc signature verification, and the new-instance application/window launch check passed. The launch check leaves the app open without starting capture.
- Both architecture/policy diagrams were regenerated to SVG/PNG and their PNGs visually inspected. Local documentation links, SVG XML, privacy property lists, shell syntax, and Git whitespace checks passed.
- An initial native test caught AppKit detaching the child lock panel on orderOut. The controller now reattaches it when showing the caption; regression checks cover repeated hide/reveal. An initial compile also identified the native CoreGraphics geometry import needed by CaptionCore. Both issues were corrected before the passing runs.

Automated native checks move windows programmatically and inspect metadata. Physical mouse dragging, clicking the lock over other applications in click-through mode, actual monitor disconnection, Spaces/fullscreen, and live playback still need interactive acceptance. No new audio capture/recognition behavior or privacy permission is introduced. Manual resizing remains unimplemented.

## 0.6.2: click-through controls and silent-output hiding — 2026-11-04 (Asia/Tokyo)

Click-through mode now hides the header/Follow live toggle and scrollbars, with automatic following. Removed Keep Onscreen and its saved preference. A passive per-capture PCM activity monitor and one bounded visibility task hide the full panel after about one second of silence, without modifying recognition. New recognized text plus recent audio reopens it; late results in silence and sound alone do not. Explicit preview applies only outside running/starting states.

**Verified for 0.6.2, build 9:**

- **32 app tests and 8 domain tests passed: 40 total, zero failures.** New fixtures cover silent versus audible PCM, negative samples, second-channel planar audio, Float64/Int16 formats, quiet/nonfinite samples, silent callback stoppage, short gaps, late final results, sound-only resumption, newly recognized speech, and fresh monitor ownership across runs. Existing history/lifecycle/local-language tests pass.
- Release build, ad-hoc signature verification, privacy property-list checks, and the new-instance launch/window check passed. The launch check leaves the app open without starting capture.
- Architecture and policy diagrams were regenerated and their PNGs visually inspected. SVG XML, 30 local documentation links, shell syntax, and Git whitespace checks passed.
- The first test compile exposed an unsupported Float64 fixture accessor; the fixture was corrected to use its raw audio plane before the passing runs. No unresolved test failures remain.

Live playback, acoustic thresholds on the user's applications, and visual silence/resumption still require interactive acceptance; synthetic PCM and coordinator fixtures do not prove every real audio-source behavior.

## 0.6.1: filter language menus — 2026-11-04 (Asia/Tokyo)

All shared language menus now omit locales that do not advertise on-device support. Saved selections are resolved against the filtered catalog, including fallback when a previously selected locale becomes unavailable. An all-unavailable catalog produces the same explicit empty state as an empty catalog. Existing settings tests now cover these cases. Caption display and recognition behavior are unchanged.

**Verified:** 25 app tests and 8 domain tests passed (33 total, zero failures), including filtered catalog contents, fallback from a saved unavailable locale, and an all-unavailable catalog. Release build and ad-hoc signature verification passed for 0.6.1, build 8. Runtime caption policy and diagram topology are unchanged; diagrams were not regenerated for this menu-only update.

## 0.6.0: languages and rolling captions — 2026-11-04 (Asia/Tokyo)

Researched Apple's public Live Captions behavior and speech locale APIs before changing display policy; [sources and design decisions](LIVE_CAPTIONS_RESEARCH.md). Added native spoken-language menus, selected-locale recognition, immediate partial replacement, bounded rolling text, Follow live, optional click-through, and Keep Onscreen. Removed the punctuation/timing cursor policies and obsolete segmentation tests.

Verified for this implementation:

- **8 domain tests and 25 app tests passed: 33 total, zero failures.** Coverage includes immediate unpunctuated partials, earlier-word/Unicode/shorter revisions, identity/time preservation, final updates without duplication, empty retraction, immutable final snapshots, repeated speech, history/display bounds, locale persistence, unavailable/empty language failures, pause/resume language changes, and existing lifecycle/PCM/startup regressions.
- **11 production-domain compatibility checks passed.** Obsolete punctuation tests were removed with the old segmentation policy rather than retained as contradictory expectations.
- A read-only probe using the production Apple locale catalog reported **62 locales, with 5 advertising on-device support** on this Mac. zh-CN and en-US advertised support; ja-JP, fr-FR, and de-DE did not. This query requested no authorization, captured no audio, and installed no assets. It does not prove recognition quality or availability for an entire language family.
- Release build and ad-hoc signature verification passed for **0.6.0, build 7**. Resource property lists validate.
- The new-instance launch check passed: the app retained a visible application window for two seconds. It leaves the app open without starting capture.
- Both updated Mermaid sources rendered to SVG/PNG; SVG XML, 29 local documentation links, shell syntax, and Git whitespace checks passed. PNGs were visually inspected for clipping and label overlaps.

Earlier version evidence remains in Git history and is not proof of this implementation.

Interactive acceptance remains necessary for actual language assets/permissions, multilingual continuous audio quality, revisable overlay scrolling and Follow live, position/font changes, silence hiding/click-through, pause/resume language changes, device switching, and Spaces/fullscreen. A native capability query and synthetic tests do not establish end-to-end recognition quality or equivalence to Apple's private Live Captions implementation.
