import AppKit
import CoreGraphics

// Read-only inspection: no Accessibility, screen-image, microphone, or audio access.
let bundlePath = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath().path
let deadline = Date().addingTimeInterval(10)
while Date() < deadline {
    let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "app.ImmersionCaption")
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for application in applications where application.bundleURL?.resolvingSymlinksInPath().path == bundlePath {
        let visibleWindows = windows.filter {
            ($0[kCGWindowOwnerPID as String] as? Int32) == application.processIdentifier &&
            ($0[kCGWindowLayer as String] as? Int) == 0
        }
        if application.isFinishedLaunching && !application.isTerminated && !visibleWindows.isEmpty {
            print("ImmersionCaption launched successfully with \(visibleWindows.count) visible application window(s).")
            exit(0)
        }
    }
    Thread.sleep(forTimeInterval: 0.1)
}
fputs("ImmersionCaption did not remain running with a visible window within 10 seconds. Check its crash report.\n", stderr)
exit(1)
