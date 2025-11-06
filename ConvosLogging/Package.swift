// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ConvosLogging",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ConvosLogging",
            targets: ["ConvosLogging"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0")
    ],
    targets: [
        .target(
            name: "ConvosLogging",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ]
        )
    ]
)
