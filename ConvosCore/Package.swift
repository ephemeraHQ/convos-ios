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
        .package(url: "https://github.com/xmtp/xmtp-ios.git", from: "4.4.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.61.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "12.1.0")
    ],
    targets: [
        .target(
            name: "ConvosCore",
            dependencies: [
                .product(name: "XMTPiOS", package: "xmtp-ios"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAppCheck", package: "firebase-ios-sdk")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .define("DEBUG", .when(configuration: .debug)),
                // Define XCODE_BUILD for non-release configurations (Local, Dev)
                // This helps distinguish Xcode builds from CI/Archive builds
                .define("XCODE_BUILD", .when(configuration: .debug))
            ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .testTarget(
            name: "ConvosCoreTests",
            dependencies: ["ConvosCore"]
        ),
    ]
)
