import XCTest
import AppKit
@testable import ImmersionCaption

@MainActor
final class AppContainerTests: XCTestCase {
    func testDependencyInitializationDefersNativeWindows() {
        let windowsBefore = NSApplication.shared.windows.count
        let container = AppContainer()

        XCTAssertNil(container.overlay, "Creating a hosting view during StateObject resolution crashes SwiftUI startup.")
        XCTAssertEqual(NSApplication.shared.windows.count, windowsBefore)
        XCTAssertEqual(container.session.state, .stopped)
        XCTAssertNil(container.session.currentCaption)
    }
}
