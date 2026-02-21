import ProjectDescription

let project = Project(
    name: "SampleApp",
    targets: [
        .target(
            name: "SampleApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.xc.sample-app",
            infoPlist: .extendingDefault(with: [
                "UILaunchStoryboardName": "LaunchScreen",
            ]),
            sources: "App/Sources/**",
            dependencies: [
                .target(name: "Core"),
            ]
        ),
        .target(
            name: "SampleAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.xc.sample-app-tests",
            infoPlist: .default,
            sources: "AppTests/**",
            dependencies: [
                .target(name: "SampleApp"),
            ]
        ),
        .target(
            name: "Core",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.xc.core",
            infoPlist: .default,
            sources: "Core/Sources/**",
            dependencies: []
        ),
        .target(
            name: "CoreTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.xc.core-tests",
            infoPlist: .default,
            sources: "CoreTests/**",
            dependencies: [
                .target(name: "Core"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "SampleApp",
            shared: true,
            buildAction: .buildAction(targets: ["SampleApp"]),
            testAction: .targets(["SampleAppTests"]),
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
