// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "xc",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .executableTarget(
            name: "xc",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/XC"
        ),
        .testTarget(
            name: "XCTests",
            dependencies: ["xc"]
        )
    ]
)
