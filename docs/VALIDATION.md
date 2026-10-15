# Validation record

Initial development: 2026-10-15 (Asia/Tokyo).

## Environment observed

- Empty starting workspace; Git repository initialized on `main`.
- Apple Silicon `arm64`; host reports macOS 27.0.1.
- Active developer directory: `/Library/Developer/CommandLineTools`.
- Swift 5.3.2; macOS SDK points to macOS 11.1.
- Full Xcode is absent; `/Applications/Xcode.appdownload` is a placeholder, not a usable installation.
- `xcodebuild` is unavailable with these selected tools; `xctest` is missing.
- Ollama 0.40.4 is serving locally; `translategemma:4b` is installed (3.3 GB as reported by Ollama).

## Checks performed

| Check | Result | What it establishes |
| --- | --- | --- |
| Compile CaptionCore production files with installed Swift compiler | Passed | Foundation domain sources compile with Swift 5.3.2 |
| `scripts/test-core-compat.sh` | 24 checks passed | Segmentation, revisions, no duplicate flushes, bounded queue behavior, loopback URLs, context limit, prompt separator, translation guidance, start policy |
| Shell syntax check for scripts | Passed | Shell scripts parse |
| Info.plist and speech entitlements validation | Passed | Property lists parse |
| `scripts/check-environment.sh` | Correctly refused | Installed compiler is below Swift 5.9 |
| Core/root `swift test` | Blocked before test execution | Installed tools lack the XCTest runner; no XCTest pass is claimed |
| Full app build and launch | Blocked | Modern compiler and ScreenCaptureKit SDK are absent |
| Local TranslateGemma smoke test | Six completed nonempty translations | Production Swift prompt works against the installed service; not Swift HTTP adapter or audio verification |

## Observed translation examples

`scripts/smoke-translation.sh` used production TranslationPrompt output, the installed model, temperature 0.2, 4096-token context, and 384-token output limit. Timings are wall time for HTTP model requests only, without transcription/segmentation/display.

| Chinese | Model output | Seconds |
| --- | --- | ---: |
| 别着急，咱们一步一步来。 | Don't worry, let's take it step by step. | 4.75 |
| 这事儿八字还没一撇呢。 | This is just starting to unfold. | 0.46 |
| 你可别放我鸽子啊。 | Don't stand me up. | 0.46 |
| 我也不是非得今天拿到，明天也行。 | I'm not saying I need to get it today; tomorrow is fine too. | 0.83 |
| 他可能只是没看到消息，别想太多。 | He might just not have seen the news, so don't overthink it. | 0.69 |
| 这个价格有点离谱，我们再看看吧。 | This price seems a bit outrageous, let's take a closer look. | 0.63 |

The idiom in row 2 means nothing is settled/it is too early to say; the output shifts that implication. Row 5 chooses “news” where “message” is more likely in an interpersonal context. Row 6 sounds fluent but “let's keep looking” better matches shopping elsewhere than “take a closer look.” These are model weaknesses, not passing semantic-quality assertions. A second pass should evaluate contextual dialogue and compare suitable local models before a learning-focused release. Do not silently rewrite model output using fixture-specific replacements.

## Required before calling the app working

After modern Xcode installation:

1. Run both XCTest suites and build the signed application bundle. Resolve any SDK/compiler errors before launch.
2. Grant/deny/revoke Speech and Screen/System Audio Recording permissions; verify actionable errors and retry after relaunch. Confirm no microphone request or input indicator is caused by the app.
3. Verify `supportsOnDeviceRecognition` for zh-CN on this machine. Test with network disconnected, then without the required model assets; unavailable assets must fail explicitly.
4. Play Mandarin in Safari and another native app. Verify the subtitle output is based on system audio while the microphone is muted/disconnected, and that protected content failures are handled.
5. Pause/resume/stop repeatedly during active capture, startup permission dialogs, silence, and slow translations. Old captions must not reappear and capture must stop.
6. Keep the app running over multiple 45-second recognition rotations, and during several minutes of silence. Check for gaps, duplicates, errors, resource leaks, and sustained CPU/memory usage.
7. Check the overlay on desktop, fullscreen apps, Spaces, changed display arrangements, different font sizes, opacity levels, and bilingual mode. Verify clicks pass through and captions remain readable.
8. Stop Ollama, select an absent model, enter a remote endpoint, and simulate slow/incomplete responses. Fail visibly without cloud fallback or an unbounded queue.
9. Review the quality fixtures and contextual dialogue for idioms, collocations, uncertainty, negation, names, tone, and added/omitted meaning. Record end-to-end latency separately from inference time.
10. Verify memory-only history limit, clear, explicit export/cancel, persistence of settings, menu bar controls after closing the main window, and clean quit.

## Future release checks

Embedded inference and app-managed downloads require offline tests with Ollama uninstalled, clean-account setup, model integrity/license/storage handling, hardware performance checks, signing/provisioning, notarization, and distribution testing. These have not been implemented.
