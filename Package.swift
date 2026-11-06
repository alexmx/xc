// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "xc",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", .upToNextMinor(from: "1.0.2"))
    ],
    targets: [
        .executableTarget(
            name: "xc",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Subprocess", package: "swift-subprocess")
            ],
            path: "Sources/XC"
        ),
        .testTarget(
            name: "XCTests",
            dependencies: ["xc"]
        )
    ]
)
