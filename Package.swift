// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OptaKube",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.5"),
    ],
    targets: [
        .executableTarget(
            name: "OptaKube",
            dependencies: ["Yams", "SwiftTerm"],
            path: "Sources/OptaKube",
            exclude: ["Info.plist"],
            resources: [.copy("Resources/AppIcon.icns")]
        ),
    ]
)
