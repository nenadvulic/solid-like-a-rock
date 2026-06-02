// swift-tools-version: 5.9
import PackageDescription

// NOTE on swift-syntax versioning:
// swift-syntax tags its major version per Swift release: 600 = Swift 6.0,
// 601 = Swift 6.1, 602 = Swift 6.2, etc. Each is treated as a *major* bump
// by SwiftPM, so `from: "600.0.0"` would NOT pick up 601/602. We use an
// explicit range so the package resolves against any recent toolchain.
let package = Package(
    name: "SolidLikeARock",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "solid-like-a-rock", targets: ["SolidCLI"]),
        .library(name: "SolidCore", targets: ["SolidCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"603.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "SolidCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .executableTarget(
            name: "SolidCLI",
            dependencies: [
                "SolidCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "SolidCoreTests",
            dependencies: ["SolidCore"]
        ),
    ]
)
