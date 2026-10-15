// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ImmersionCaption",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ImmersionCaption", targets: ["ImmersionCaption"])],
    dependencies: [.package(path: "Packages/CaptionCore")],
    targets: [
        .executableTarget(
            name: "ImmersionCaption",
            dependencies: [.product(name: "CaptionCore", package: "CaptionCore")]
        ),
        .testTarget(name: "ImmersionCaptionTests", dependencies: ["ImmersionCaption"])
    ]
)
