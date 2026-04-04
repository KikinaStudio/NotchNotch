// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BoaNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BoaNotch",
            path: "BoaNotch",
            exclude: ["Info.plist", "BoaNotch.entitlements"],
            resources: [.copy("Resources")]
        )
    ]
)
