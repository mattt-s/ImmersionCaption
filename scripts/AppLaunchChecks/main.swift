import AppKit
import CoreGraphics

// Read-only inspection: no Accessibility, screen-image, microphone, or audio access.
let bundlePath = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath().path
let startedAt = Date(timeIntervalSince1970: TimeInterval(CommandLine.arguments[2]) ?? 0)
let deadline = Date().addingTimeInterval(10)
var visibleSince: Date?
while Date() < deadline {
    let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "app.ImmersionCaption")
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    var hasVisibleWindow = false
    for application in applications where application.bundleURL?.resolvingSymlinksInPath().path == bundlePath &&
        (application.launchDate ?? .distantPast) >= startedAt {
        let visibleWindows = windows.filter {
            ($0[kCGWindowOwnerPID as String] as? Int32) == application.processIdentifier &&
            ($0[kCGWindowLayer as String] as? Int) == 0
        }
        if application.isFinishedLaunching && !application.isTerminated && !visibleWindows.isEmpty {
            hasVisibleWindow = true
            if visibleSince == nil { visibleSince = Date() }
            if let visibleSince, Date().timeIntervalSince(visibleSince) >= 2 {
                print("ImmersionCaption launched successfully and retained a visible application window for two seconds.")
                exit(0)
            }
        }
    }
    if !hasVisibleWindow { visibleSince = nil }
    Thread.sleep(forTimeInterval: 0.1)
}
fputs("ImmersionCaption did not remain running with a visible window within 10 seconds. Check its crash report.\n", stderr)
exit(1)
