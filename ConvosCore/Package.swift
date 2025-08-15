// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ConvosCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "ConvosCore",
            targets: ["ConvosCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.5.0"),
        .package(url: "https://github.com/xmtp/xmtp-ios.git", from: "4.3.0")
    ],
    targets: [
        .target(
            name: "ConvosCore",
            dependencies: [
                .product(name: "XMTPiOS", package: "xmtp-ios"),
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "ConvosCoreTests",
            dependencies: ["ConvosCore"]
        ),
    ]
)
