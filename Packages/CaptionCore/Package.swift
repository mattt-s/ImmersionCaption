// swift-tools-version:5.3
import PackageDescription

// Domain values and native geometry; also supports the original lightweight compatibility checks.
let package = Package(
    name: "CaptionCore",
    products: [.library(name: "CaptionCore", targets: ["CaptionCore"])],
    targets: [
        .target(name: "CaptionCore"),
        .testTarget(name: "CaptionCoreTests", dependencies: ["CaptionCore"])
    ]
)
