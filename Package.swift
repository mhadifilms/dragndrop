// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "dragndrop",
    platforms: [
        .macOS(.v15)  // macOS 15 Sequoia
    ],
    products: [
        .executable(name: "dragndrop-app", targets: ["DragNDropApp"]),
        .executable(name: "dragndrop-cli", targets: ["DragNDropCLI"]),
        .library(name: "DragNDropCore", targets: ["DragNDropCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0")
    ],
    targets: [
        // Core library with all business logic
        .target(
            name: "DragNDropCore",
            dependencies: [
                .product(name: "AWSS3", package: "aws-sdk-swift"),
                .product(name: "AWSSTS", package: "aws-sdk-swift"),
                .product(name: "AWSSSO", package: "aws-sdk-swift"),
                .product(name: "AWSSSOOIDC", package: "aws-sdk-swift"),
                .product(name: "AWSClientRuntime", package: "aws-sdk-swift"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/DragNDropCore"
        ),

        // Main macOS app
        .executableTarget(
            name: "DragNDropApp",
            dependencies: ["DragNDropCore"],
            path: "Sources/DragNDropApp",
            resources: [
                .process("Resources")
            ]
        ),

        // CLI tool for testing and automation
        .executableTarget(
            name: "DragNDropCLI",
            dependencies: [
                "DragNDropCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/DragNDropCLI"
        ),

        // Tests
        .testTarget(
            name: "DragNDropTests",
            dependencies: ["DragNDropCore"],
            path: "Tests/DragNDropTests"
        )
    ]
)
