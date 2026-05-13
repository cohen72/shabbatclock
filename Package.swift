// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ShabbatClock",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "ShabbatClock",
            targets: ["ShabbatClock"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Elyahu41/KosherSwift.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "ShabbatClock",
            dependencies: ["KosherSwift"],
            path: "ShabbatClock"
        ),
    ]
)
