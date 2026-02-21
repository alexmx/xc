import ProjectDescription

let project = Project(
    name: "SampleMacApp",
    targets: [
        .target(
            name: "SampleMacApp",
            destinations: [.mac],
            product: .app,
            bundleId: "dev.xc.sample-mac-app",
            infoPlist: .extendingDefault(with: [
                "LSMinimumSystemVersion": "14.0",
            ]),
            sources: "App/Sources/**",
            dependencies: [
                .target(name: "Core"),
            ]
        ),
        .target(
            name: "SampleMacAppTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "dev.xc.sample-mac-app-tests",
            infoPlist: .default,
            sources: "AppTests/**",
            dependencies: [
                .target(name: "SampleMacApp"),
            ]
        ),
        .target(
            name: "Core",
            destinations: [.mac],
            product: .framework,
            bundleId: "dev.xc.mac-core",
            infoPlist: .default,
            sources: "Core/Sources/**",
            dependencies: []
        ),
        .target(
            name: "CoreTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "dev.xc.mac-core-tests",
            infoPlist: .default,
            sources: "CoreTests/**",
            dependencies: [
                .target(name: "Core"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "SampleMacApp",
            shared: true,
            buildAction: .buildAction(targets: ["SampleMacApp"]),
            testAction: .targets(["SampleMacAppTests"]),
            runAction: .runAction(configuration: .debug),
            archiveAction: .archiveAction(configuration: .release)
        ),
        .scheme(
            name: "Core",
            shared: true,
            buildAction: .buildAction(targets: ["Core"]),
            testAction: .targets(["CoreTests"]),
            runAction: .runAction(configuration: .debug)
        ),
    ]
)
