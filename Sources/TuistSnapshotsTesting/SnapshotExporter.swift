import Foundation

/// Writes rendered previews where `tuist snapshots upload` reads them: a PNG and a JSON file
/// with the same name, in the format Sentry's snapshot uploads use (`display_name`, `group`,
/// `tags`, `diff_threshold`).
struct SnapshotExporter {
    /// `tuist test --snapshots` and `tuist xcodebuild test --snapshots` set
    /// `TEST_RUNNER_SNAPSHOTS_EXPORT_DIR`, which xcodebuild passes to the test process without
    /// its prefix.
    static let directoryVariable = "SNAPSHOTS_EXPORT_DIR"
    /// Lists every preview, so the previews a filtered run doesn't render count as skipped
    /// rather than removed.
    static let allImageNamesFile = "tuist-all-image-names.txt"

    let directory: URL

    init?(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let path = environment[Self.directoryVariable], !path.isEmpty else { return nil }
        directory = URL(fileURLWithPath: path, isDirectory: true)
    }

    func writeAllImageNames(_ names: [String]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let contents = names.map { "\($0).png" }.joined(separator: "\n") + "\n"
        try Data(contents.utf8).write(to: directory.appendingPathComponent(Self.allImageNamesFile), options: .atomic)
    }

    func write(_ snapshot: Snapshot, of preview: SnapshotPreview, tags: [String: String]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try snapshot.png.write(to: directory.appendingPathComponent("\(preview.name).png"), options: .atomic)
        try Self.sidecar(for: preview, diffThreshold: snapshot.diffThreshold, tags: tags)
            .write(to: directory.appendingPathComponent("\(preview.name).json"), options: .atomic)
    }

    static func sidecar(for preview: SnapshotPreview, diffThreshold: Double?, tags: [String: String]) throws -> Data {
        var json: [String: Any] = [
            "display_name": preview.displayName ?? preview.name,
            "group": preview.group,
            "tags": tags,
        ]
        if let diffThreshold { json["diff_threshold"] = diffThreshold }
        var context: [String: Any] = [:]
        if let fileID = preview.fileID { context["file_id"] = fileID }
        if let line = preview.line { context["line"] = line }
        if !context.isEmpty { json["context"] = context }
        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    }
}
