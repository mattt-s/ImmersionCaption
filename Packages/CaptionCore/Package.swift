// swift-tools-version: 5.3
import PackageDescription

// This Foundation-only package can also be tested with the older tools installed initially.
let package = Package(
    name: "CaptionCore",
    products: [.library(name: "CaptionCore", targets: ["CaptionCore"])],
    targets: [
        .target(name: "CaptionCore"),
        .testTarget(name: "CaptionCoreTests", dependencies: ["CaptionCore"])
    ]
)
