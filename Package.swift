// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenTouchMapper",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ScreenTouchCore"),
        .executableTarget(name: "ScreenTouchMapper", dependencies: ["ScreenTouchCore"]),
        .testTarget(name: "ScreenTouchCoreTests", dependencies: ["ScreenTouchCore"]),
    ]
)
