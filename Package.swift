// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Segue",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SegueCore", targets: ["SegueCore"]),
        .executable(name: "Segue", targets: ["Segue"]),
        // Named segue-cli (not "segue") so the build product doesn't collide
        // with "Segue" on a case-insensitive filesystem. The bundle script
        // installs it as Contents/MacOS/segue.
        .executable(name: "segue-cli", targets: ["segue-cli"]),
    ],
    targets: [
        .target(name: "SegueCore"),
        .executableTarget(name: "Segue", dependencies: ["SegueCore"]),
        .executableTarget(name: "segue-cli", dependencies: ["SegueCore"]),
        .testTarget(name: "SegueCoreTests", dependencies: ["SegueCore"], exclude: ["Fixtures"]),
    ]
)
