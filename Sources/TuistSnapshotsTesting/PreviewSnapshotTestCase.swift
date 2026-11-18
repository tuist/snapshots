import ObjectiveC
import SwiftUI
import XCTest

/// Renders every SwiftUI preview in the process as its own test.
///
/// Subclass it in a test target whose host app (or linked frameworks) declares the previews:
///
/// ```swift
/// import TuistSnapshotsTesting
///
/// final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
/// ```
///
/// Each preview becomes a test named `test_<image name>`, so it can be filtered with
/// `-only-testing`. When `SNAPSHOTS_EXPORT_DIR` is set, which `tuist test` and
/// `tuist xcodebuild test` do when they upload snapshots, the images are written there for Tuist to upload and
/// compare with their baselines. Otherwise each image is attached to its test result.
open class PreviewSnapshotTestCase: XCTestCase {
    /// Override to leave previews out, for example the ones of a module.
    @MainActor open class func includes(_ preview: SnapshotPreview) -> Bool {
        true
    }

    override open class var defaultTestSuite: XCTestSuite {
        if self != PreviewSnapshotTestCase.self {
            // XCTest asks for suites on the main thread.
            MainActor.assumeIsolated { addPreviewTests() }
        }
        return super.defaultTestSuite
    }

    @MainActor private static var previewsByTestName: [String: SnapshotPreview] = [:]
    @MainActor private static var renderer: PreviewRenderer?

    /// Adds a `test_<image name>` method per preview, which XCTest then runs like any other test.
    @MainActor private class func addPreviewTests() {
        let previews = PreviewCatalog.previews().filter(includes)
        if let exporter = SnapshotExporter() {
            do {
                try exporter.writeAllImageNames(previews.map(\.name))
            } catch {
                print("TuistSnapshots: couldn't write \(SnapshotExporter.allImageNamesFile): \(error)")
            }
        }
        let test: @convention(block) (PreviewSnapshotTestCase) -> Void = { testCase in
            MainActor.assumeIsolated { testCase.snapshotPreview() }
        }
        let implementation = imp_implementationWithBlock(test)
        for preview in previews {
            previewsByTestName[preview.testName] = preview
            class_addMethod(self, NSSelectorFromString(preview.testName), implementation, "v@:")
        }
    }

    /// Renders the preview this test was added for. XCTest names a test `-[Class test_Name]`.
    @MainActor private func snapshotPreview() {
        let testName = name.split(separator: " ").last.map { String($0.dropLast()) } ?? name
        guard let preview = Self.previewsByTestName[testName] else {
            return XCTFail("No preview for the test \(name).")
        }
        do {
            let resolved = try preview.make()
            let renderer = Self.renderer ?? PreviewRenderer()
            Self.renderer = renderer
            let snapshot = try renderer.render(resolved, name: preview.name)
            if let exporter = SnapshotExporter() {
                try exporter.write(snapshot, of: preview, tags: Self.tags(resolved, snapshot: snapshot))
            } else {
                let attachment = XCTAttachment(data: snapshot.png, uniformTypeIdentifier: "public.png")
                attachment.name = "\(preview.name).png"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    /// How the preview rendered, where it differs from the defaults.
    static func tags(_ preview: ResolvedPreview, snapshot: Snapshot) -> [String: String] {
        var tags: [String: String] = [:]
        if snapshot.isDark { tags["color_scheme"] = "dark" }
        if preview.landscape { tags["orientation"] = "landscape" }
        switch preview.layout {
        case .sizeThatFits: tags["layout"] = "size_that_fits"
        case let .fixed(width, height): tags["layout"] = "fixed_\(Int(width))x\(Int(height))"
        default: break
        }
        return tags
    }
}
