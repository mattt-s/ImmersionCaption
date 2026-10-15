import AppKit
import CoreGraphics

// Read-only inspection: no Accessibility, screen-image, microphone, or audio access.
let bundlePath = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath().path
let startedAt = Date(timeIntervalSince1970: TimeInterval(CommandLine.arguments[2]) ?? 0)
let deadline = Date().addingTimeInterval(10)
var visibleSince: Date?
while Date() < deadline {
    let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "app.ImmersionCaption")
    // A working app can open on another Space or restore a minimized window. Inspect
    // all window metadata rather than requiring it to be on the caller's current screen.
    let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    var hasApplicationWindow = false
    for application in applications where application.bundleURL?.resolvingSymlinksInPath().path == bundlePath &&
        (application.launchDate ?? .distantPast) >= startedAt {
        let applicationWindows = windows.filter { window in
            guard (window[kCGWindowOwnerPID as String] as? Int32) == application.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? NSNumber,
                  let height = bounds["Height"] as? NSNumber else { return false }
            return width.doubleValue > 0 && height.doubleValue > 0
        }
        if application.isFinishedLaunching && !application.isTerminated && !applicationWindows.isEmpty {
            hasApplicationWindow = true
            if visibleSince == nil { visibleSince = Date() }
            if let visibleSince, Date().timeIntervalSince(visibleSince) >= 2 {
                print("ImmersionCaption launched successfully and retained an application window for two seconds (including other Spaces).")
                exit(0)
            }
        }
    }
    if !hasApplicationWindow { visibleSince = nil }
    Thread.sleep(forTimeInterval: 0.1)
}
fputs("ImmersionCaption did not finish launching and retain an application window within 10 seconds. Check its process/window state and any crash report.\n", stderr)
exit(1)
