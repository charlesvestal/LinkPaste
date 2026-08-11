// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LinkPaste",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure, side-effect-free logic. Everything here is unit tested.
        .target(name: "LinkPasteCore"),

        // The app: event tap, Accessibility, menu bar UI. Not unit testable.
        .executableTarget(name: "LinkPasteApp", dependencies: ["LinkPasteCore"]),

        .testTarget(name: "LinkPasteCoreTests", dependencies: ["LinkPasteCore"]),
    ]
)
