// swift-tools-version: 6.0
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
        .executable(name: "solid-like-a-rock", targets: ["solid-like-a-rock"]),
        .library(name: "SolidCore", targets: ["SolidCore"]),
        // Exposed so any package depending on SolidLikeARock can run
        // `swift package solid-lint` — architecture linting for free in CI.
        .plugin(name: "SolidLint", targets: ["SolidLint"]),
        // Build-tool plugin: lints automatically on every `swift build`.
        .plugin(name: "SolidLintBuildTool", targets: ["SolidLintBuildTool"]),
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
        // The target is named after the product on purpose: a command plugin can
        // only locate a same-package executable via `context.tool(named:)` when
        // the target name matches the product name (see swift-package-manager#6524).
        .executableTarget(
            name: "solid-like-a-rock",
            dependencies: [
                "SolidCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/SolidCLI"
        ),
        .testTarget(
            name: "SolidCoreTests",
            dependencies: ["SolidCore"],
            // `.copy` treats the whole tree as a resource bundle, so the sample
            // `.swift` files are NOT compiled into the test target — they're only
            // read back as text fixtures via `Bundle.module` at runtime.
            resources: [.copy("Fixtures")]
        ),
        .plugin(
            name: "SolidLint",
            capability: .command(
                intent: .custom(
                    verb: "solid-lint",
                    description: "Enforce architectural import boundaries (SOLID / Clean Architecture)."
                )
                // Read-only: no `permissions` needed — the plugin only parses sources.
            ),
            dependencies: [.target(name: "solid-like-a-rock")]
        ),
        .plugin(
            name: "SolidLintBuildTool",
            capability: .buildTool(),
            // A prebuild command can't build its tool from source, so it uses the
            // prebuilt binary from the published artifactbundle.
            dependencies: [.target(name: "SolidLikeARockBinary")]
        ),
        .binaryTarget(
            name: "SolidLikeARockBinary",
            url: "https://github.com/nenadvulic/solid-like-a-rock/releases/download/v0.5.0/solid-like-a-rock.artifactbundle.zip",
            checksum: "ab130dd2451afc7594114d960acad2cc9e3b209dac40759c3186741147e28542"
        ),
    ],
    // tools-version 6.0 is required so the command plugin can invoke the
    // same-package executable, but we stay on the Swift 5 language mode — we
    // aren't opting into Swift 6 strict concurrency here.
    swiftLanguageModes: [.v5]
)
