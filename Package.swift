// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LinkPaste",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Pure, side-effect-free logic. Everything here is unit tested.
        .target(name: "LinkPasteCore"),

        // The app: event tap, Accessibility, menu bar UI. Not unit testable.
        .executableTarget(
            name: "LinkPasteApp",
            dependencies: [
                "LinkPasteCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),

        .testTarget(name: "LinkPasteCoreTests", dependencies: ["LinkPasteCore"]),
    ]
)
