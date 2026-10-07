// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Tasks",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "Tasks", swiftSettings: [.swiftLanguageMode(.v5)])]
)
