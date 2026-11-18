import Foundation
import Testing
@testable import TuistSnapshotsTesting

@MainActor
@Suite struct SnapshotExporterTests {
    @Test func reads_the_directory_from_the_environment() {
        #expect(SnapshotExporter(environment: [:]) == nil)
        #expect(SnapshotExporter(environment: ["SNAPSHOTS_EXPORT_DIR": ""]) == nil)
        #expect(SnapshotExporter(environment: ["SNAPSHOTS_EXPORT_DIR": "/tmp/out"])?.directory.path == "/tmp/out")
    }

    @Test func writes_images_with_sentry_format_sidecars() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = try #require(SnapshotExporter(environment: ["SNAPSHOTS_EXPORT_DIR": directory.path]))
        let preview = SnapshotPreview(
            name: "ProfileView.Dark", group: "ProfileView", displayName: "Dark",
            fileID: "App/ProfileView.swift", line: 12
        ) { fatalError() }

        try exporter.writeAllImageNames(["ProfileView.Dark", "ProfileView.Preview"])
        try exporter.write(
            Snapshot(png: Data([1, 2, 3]), width: 1, height: 1, isDark: true, diffThreshold: 0.1),
            of: preview,
            tags: ["color_scheme": "dark"]
        )

        #expect(try String(contentsOf: directory.appendingPathComponent("tuist-all-image-names.txt"), encoding: .utf8)
            == "ProfileView.Dark.png\nProfileView.Preview.png\n")
        #expect(try Data(contentsOf: directory.appendingPathComponent("ProfileView.Dark.png")) == Data([1, 2, 3]))
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("ProfileView.Dark.json")))
                as? [String: Any]
        )
        #expect(json["display_name"] as? String == "Dark")
        #expect(json["group"] as? String == "ProfileView")
        #expect(json["tags"] as? [String: String] == ["color_scheme": "dark"])
        #expect(json["diff_threshold"] as? Double == 0.1)
        #expect(json["context"] as? [String: AnyHashable] == ["file_id": "App/ProfileView.swift", "line": 12])
    }

    @Test func omits_the_threshold_and_falls_back_to_the_name() throws {
        let preview = SnapshotPreview(name: "Card.Preview", group: "Card", displayName: nil, fileID: nil, line: nil) {
            fatalError()
        }
        let json = try #require(
            try JSONSerialization.jsonObject(with: SnapshotExporter.sidecar(for: preview, diffThreshold: nil, tags: [:]))
                as? [String: Any]
        )
        #expect(json["display_name"] as? String == "Card.Preview")
        #expect(json["diff_threshold"] == nil)
        #expect(json["context"] == nil)
    }
}
