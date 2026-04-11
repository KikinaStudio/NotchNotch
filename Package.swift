// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BoaNotch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .executableTarget(
            name: "BoaNotch",
            dependencies: [.product(name: "Yams", package: "Yams")],
            path: "BoaNotch",
            exclude: ["Info.plist", "BoaNotch.entitlements"],
            resources: [.copy("Resources")]
        )
    ]
)
