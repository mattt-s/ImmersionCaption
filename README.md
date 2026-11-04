# ImmersionCaption

**English** | [简体中文](README.zh-CN.md)

<img src="Resources/Artwork/AppIcon.png" alt="ImmersionCaption app icon" width="112" height="112">

A native macOS app displaying live captions for application audio in a user-selected spoken language. Capture and recognition run locally. No microphone, translation service, or Ollama installation is required.

**Version 0.7.1: configurable caption lines.** Choose One, Two, or Three visible wrapped lines in Settings (default: Three). Unlock the overlay, drag its handle, and lock it at a saved custom location. Partial results appear immediately and corrections replace the current text in place. Punctuation and final results no longer gate display. The [research note](docs/LIVE_CAPTIONS_RESEARCH.md) explains the macOS Live Captions reference and the limits of that comparison.

## Features

- Core Audio process-tap capture of system/application output; no screen or microphone recording.
- Spoken-language menu in the main window, settings, and menu bar. Options come from Apple Speech; on-device capability varies by language and Mac.
- On-device recognition without cloud fallback. Language selection is explicit, not automatic detection.
- Rolling, naturally wrapped text that supports revisions, scrolling, Follow live, and optional click-through.
- Font size, maximum visible lines (one/two/three), background opacity, lock/unlock control, saved draggable positions, position presets, preview, and automatic hiding during silence.
- Start/pause/resume/stop, menu controls, visible errors, and latest-300-block memory-only history with text export.

## Requirements

- macOS 14.2+ and on-device speech assets for the selected language; Apple Silicon recommended.
- Xcode 15.2+ with Swift 5.9+ for building. CaptionCore also supports the original Swift 5.3 compatibility checks.
- No third-party source-package dependencies or external inference services.

Language options are discovered at startup. Only options advertising on-device support are shown. A saved unavailable language falls back to a visible option; if none qualify, the menu shows an empty-state message. Install missing language data in macOS Keyboard → Dictation settings and reopen the app. Start rechecks recognition availability; the app fails explicitly instead of using a network recognizer.

## Build and install

Download the ready-to-install **Apple Silicon / macOS 14.2+** packages from [GitHub Releases](https://github.com/mattt-s/ImmersionCaption/releases/tag/v0.7.1). Choose the DMG for drag-and-drop installation or the PKG for macOS Installer; both are development packages without Developer ID signing or notarization. Source-build instructions follow.

Complete Xcode setup and select its command-line tools. From the repository root:

```sh
swift test --package-path Packages/CaptionCore
swift test
scripts/build-app.sh
open build/ImmersionCaption.app
```

The build generates the icon and an ad-hoc signed development bundle at build/ImmersionCaption.app. Copy it into Applications to install locally. Quit older copies and use one bundle for permissions. Launch the packaged app for permission testing rather than swift run.

## Installation packages

Run `scripts/package-app.sh` to rebuild the app and create native installers in build/:

- **[ImmersionCaption-0.7.1-arm64.pkg](https://github.com/mattt-s/ImmersionCaption/releases/download/v0.7.1/ImmersionCaption-0.7.1-arm64.pkg):** double-click to install into /Applications/ImmersionCaption.app using macOS Installer. Administrator authorization may be required. Quit older copies before installation. The package stays at this fixed destination instead of locating and replacing development copies elsewhere.
- **[ImmersionCaption-0.7.1-arm64.dmg](https://github.com/mattt-s/ImmersionCaption/releases/download/v0.7.1/ImmersionCaption-0.7.1-arm64.dmg):** open the disk image, drag the app onto Applications, then launch the installed copy. The image includes English/Chinese installation notes.
- **[ImmersionCaption-0.7.1-arm64.sha256](https://github.com/mattt-s/ImmersionCaption/releases/download/v0.7.1/ImmersionCaption-0.7.1-arm64.sha256):** SHA-256 checksums for both files. From the repository root, verify with `(cd build && shasum -a 256 -c ImmersionCaption-0.7.1-arm64.sha256)`. While inside build/, use `shasum -a 256 -c ImmersionCaption-0.7.1-arm64.sha256`.

Names reflect the app version and actual binary architecture. The current arm64 artifacts require Apple Silicon and macOS 14.2+. The installer checks the app's OS/architecture requirements and contains only the app, with no installation scripts. Preferences, history, and AI language assets are not bundled; system-managed language resources remain a prerequisite.

These are development packages: the app is ad-hoc signed by default, the .pkg is unsigned, and neither artifact is notarized. Developer ID distribution signing and notarization remain planned. If certificates are available, CODE_SIGN_IDENTITY configures app signing and INSTALLER_SIGN_IDENTITY configures installer signing; notarization is a separate step. Packaging does not install or launch the app automatically.

## Publishing a release

Maintainers and coding agents should follow the [release guide](docs/RELEASING.md) for GitHub CLI authentication, packaging, draft uploads, checksum/download verification, publication, and documentation updates. The key requirements are also recorded in [AGENTS.md](AGENTS.md).

## Usage

1. Choose **Spoken language**, matching the audio you intend to play, then **Start captions**.
2. Allow Speech Recognition and System Audio Recording. The audio-only permission may appear under Privacy & Security → Screen & System Audio Recording → System Audio Recording Only. Screen and microphone permissions are not needed.
3. Play audio in another application. Text appears as recognized, including unfinished speech; earlier words may change.
4. To change language, pause or stop, choose another language, then resume/start. The live window starts fresh; existing history keeps its language labels.
5. In interactive mode, leave **Follow live** on to track new text, or turn it off to scroll back. When locked with **Click-through overlay** enabled, the header/toggle and scrollbars are hidden and following is automatic. The small corner lock button remains clickable.
6. Click the corner **lock** button to unlock positioning, then drag **Drag to move** in the caption header. Click the open lock to fix the position. Unlocking temporarily accepts mouse input and keeps the window visible, even in silence; locking restores your saved click-through preference and normal hiding.
7. If captions are hidden, use **Unlock and move captions** in the menu bar or Settings. Locations survive caption updates, hide/show, and app reopening; reopening starts locked. Settings shows **Custom** after dragging. Choose **Top**, **Middle**, or **Bottom** to reset the custom location.
8. Adjust font, **Maximum caption lines** (One/Two/Three), and opacity in Settings. The panel follows the chosen line count; Follow live shows the newest text. Earlier text remains scrollable and in history. Preview shows the overlay while stopped/paused without recording; it does not override automatic hiding during a running session. Unlocked positioning is a separate editing mode.

Closing the main window leaves menu controls available; Quit ImmersionCaption exits. When locked, the entire caption window, including its background and lock button, hides after about one second without audible system output. Recognition continues. The window reappears when a changed recognition result arrives with recent audio; sound alone and late results in silence do not reveal old text. The former Keep Onscreen override is removed. Pause/stop clears the live display but retains history. Clear affects history, and subsequent updates can add the active block again. Export writes the current text snapshots to a chosen location.

## Display policy and limits

See the [policy diagram](docs/CAPTION_POLICY.md) and [architecture](ARCHITECTURE.md). Each recognition request owns a revisable block. Partials replace its text instead of appending duplicate sentences. A real final marks the same entry final. The window retains three recent request blocks and shows at most the selected one, two, or three wrapped lines at the chosen font size, without arbitrary source cuts or font shrinking. History retains the latest 300 blocks.

The 45-second legacy request rotation can create audio gaps; audio overlap buffering is not implemented. Separate requests can repeat overlapping speech because no cross-request text deduplication is imposed. The public recognizer's latency/quality and supported locales can differ from built-in Live Captions. Sentence-level history, automatic language detection, semantic endpointing, translation, and direct asset downloading are not implemented.

Capture uses a private global stereo mix without changing default devices. Protected audio may be unavailable. Device-format changes and speech errors stop processing visibly. Dragging is supported through the unlocked header; manual resizing is not implemented. Saved positions use a display-relative top-left anchor and are constrained to the visible screen. If the saved monitor is absent, the window falls back to the main screen; reconnecting can restore the original monitor. This is an ad-hoc development build; distribution signing and notarization remain planned.

## Project structure and verification

```text
Packages/CaptionCore/                 caption snapshots, transcript/lifecycle policy, overlay geometry, tests
Sources/ImmersionCaption/
  App/                               composition root and app lifecycle
  Application/                       capture/speech ports, language values, caption session
  Infrastructure/                    Core Audio, selected Apple Speech locale, preferences
  Presentation/                      language menus, controls, settings, history, rolling overlay
Resources/                           icon, privacy descriptions, entitlements
Tests/ImmersionCaptionTests/          revisions, languages, lifecycle, PCM, positioning, persistence, native panels/line layout
scripts/                             build, launch, environment, compatibility checks
docs/                                research, policy, architecture diagrams, validation
```

Run scripts/test-core-compat.sh for lightweight domain checks (Foundation and native geometry types). scripts/check-app-launch.sh checks process/window metadata after building and leaves the app open; it does not test live audio. See [validation evidence](docs/VALIDATION.md) and [development rules](AGENTS.md).

A passive PCM monitor uses a conservative -80 dBFS peak floor and a one-second grace to avoid flickering between words. It is an output-activity heuristic rather than voice detection; unusually quiet signals can fall below its floor. Audio and history are not automatically saved. Preferences use UserDefaults; export is explicit. Logs contain lifecycle/error categories rather than audio/transcripts. Initial OS asset downloads may need internet; installed local assets are required for offline recognition. Removing the old translation integration does not uninstall external apps or their models.
