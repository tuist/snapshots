// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TuistSnapshots",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // Linked by the app: view modifiers that configure a preview's snapshot.
        .library(name: "TuistSnapshots", targets: ["TuistSnapshots"]),
        // Linked by a test target: renders every preview and exports it for Tuist.
        .library(name: "TuistSnapshotsTesting", targets: ["TuistSnapshotsTesting"]),
    ],
    targets: [
        .target(name: "TuistSnapshots"),
        .target(name: "TuistSnapshotsTesting", dependencies: ["TuistSnapshots"]),
        .testTarget(name: "TuistSnapshotsTestingTests", dependencies: ["TuistSnapshotsTesting"]),
    ]
)
