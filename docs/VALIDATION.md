# Validation record

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

Interactive acceptance remains necessary for actual language assets/permissions, multilingual continuous audio quality, revisable overlay scrolling and Follow live, position/font changes, Keep Onscreen/click-through, pause/resume language changes, device switching, and Spaces/fullscreen. A native capability query and synthetic tests do not establish end-to-end recognition quality or equivalence to Apple's private Live Captions implementation.
