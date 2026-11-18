import ProjectDescription

let project = Project(
    name: "PreviewsApp",
    packages: [.local(path: "../..")],
    targets: [
        .target(
            name: "PreviewsApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.snapshots.PreviewsApp",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: ["UILaunchScreen": [:]]),
            sources: ["Sources/**"],
            dependencies: [.package(product: "TuistSnapshots")]
        ),
        .target(
            name: "PreviewsAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.snapshots.PreviewsAppTests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "PreviewsApp"),
                .package(product: "TuistSnapshotsTesting"),
            ]
        ),
    ]
)
