import DeveloperToolsSupport
import SwiftUI

/// A preview found in the test process: a `#Preview` or one of a `PreviewProvider`'s previews.
public struct SnapshotPreview {
    /// The image's name without extension, unique among the previews, such as `ProfileView.Dark`.
    public let name: String
    /// The file or `PreviewProvider` type the preview is declared in, such as `ProfileView`.
    public let group: String
    /// The name given to the preview, if any.
    public let displayName: String?
    /// For a `#Preview`, the file it is declared in, such as `MyApp/ProfileView.swift`.
    public let fileID: String?
    /// For a `#Preview`, the line it is declared on.
    public let line: Int?

    let make: @MainActor () throws -> ResolvedPreview
}

enum SnapshotPreviewError: LocalizedError {
    case noContent(String)

    var errorDescription: String? {
        switch self {
        case let .noContent(name): "The preview \(name) has no view, view controller, or SwiftUI content to render."
        }
    }
}

/// Finds the previews compiled into the process.
@MainActor
enum PreviewCatalog {
    /// Every preview, named so that file and test names are unique.
    static func previews() -> [SnapshotPreview] {
        var seen: [String: Int] = [:]
        return (macroPreviews() + providerPreviews()).map { preview in
            let base = fileName(preview.name)
            let count = seen[testName(base), default: 0] + 1
            seen[testName(base)] = count
            return preview.renamed(count == 1 ? base : "\(base)_\(count)")
        }
    }

    /// Keeps letters, digits, `.`, `-`, and `_`, so the name works as a file name everywhere.
    nonisolated static func fileName(_ name: String) -> String {
        String(name.map { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) ? $0 : "_" })
    }

    nonisolated static func testName(_ name: String) -> String {
        "test_" + name.replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "-", with: "_")
    }

    /// A `#Preview` declaration: a `PreviewRegistry` type the macro generates.
    private struct MacroPreview {
        var fileID: String
        var line: Int
        var column: Int
        var displayName: String?
        var makePreview: @MainActor () throws -> Preview
    }

    /// `#Preview` declarations. Within a file, unnamed previews are numbered in source order, so a
    /// name survives edits elsewhere in the file.
    private static func macroPreviews() -> [SnapshotPreview] {
        var declarations: [MacroPreview] = []
        for type in ConformanceScanner.types(conformingTo: "PreviewRegistry") {
            guard let registry = type as? any PreviewRegistry.Type else { continue }
            declarations.append(macroPreview(registry))
        }
        declarations.sort { ($0.fileID, $0.line, $0.column) < ($1.fileID, $1.line, $1.column) }

        var previews: [SnapshotPreview] = []
        let files = Dictionary(grouping: declarations) { $0.fileID }
        for fileID in files.keys.sorted() {
            let declarations = files[fileID]!
            let group = sourceFileName(fileID)
            let unnamedCount = declarations.filter { $0.displayName == nil }.count
            var unnamedIndex = 0
            for declaration in declarations {
                let label: String
                if let displayName = declaration.displayName {
                    label = displayName
                } else {
                    unnamedIndex += 1
                    label = unnamedCount == 1 ? "Preview" : "Preview_\(unnamedIndex)"
                }
                let name = "\(group).\(label)"
                let makePreview = declaration.makePreview
                previews.append(SnapshotPreview(
                    name: name,
                    group: group,
                    displayName: declaration.displayName,
                    fileID: fileID,
                    line: declaration.line
                ) {
                    let preview = try makePreview()
                    guard let content = PreviewReflection.content(of: preview) else {
                        throw SnapshotPreviewError.noContent(name)
                    }
                    let traits = PreviewReflection.traits(of: preview)
                    return ResolvedPreview(content: content, layout: traits.layout, landscape: traits.landscape)
                })
            }
        }
        return previews
    }

    /// Generic, so closures capture the concrete registry type rather than an existential.
    private static func macroPreview<Registry: PreviewRegistry>(_: Registry.Type) -> MacroPreview {
        let displayName = (try? Registry.makePreview())
            .flatMap { PreviewReflection.field(of: $0, named: "displayName") as? String }
        return MacroPreview(
            fileID: Registry.fileID,
            line: Registry.line,
            column: Registry.column,
            displayName: displayName,
            makePreview: { try Registry.makePreview() }
        )
    }

    /// The previews of `PreviewProvider` types, read through SwiftUI's `_allPreviews`.
    private static func providerPreviews() -> [SnapshotPreview] {
        ConformanceScanner.types(conformingTo: "PreviewProvider")
            .compactMap { $0 as? any PreviewProvider.Type }
            .map { (provider: $0, name: typeName($0)) }
            .sorted { $0.name < $1.name }
            .flatMap { provider, typeName -> [SnapshotPreview] in
                let group = typeName.hasSuffix("_Previews") ? String(typeName.dropLast("_Previews".count)) : typeName
                let previews = provider._allPreviews
                let unnamedCount = previews.filter { $0.displayName == nil }.count
                var unnamedIndex = 0
                return previews.enumerated().map { index, preview in
                    let label: String
                    if let displayName = preview.displayName {
                        label = displayName
                    } else {
                        unnamedIndex += 1
                        label = unnamedCount == 1 ? "Preview" : "Preview_\(unnamedIndex)"
                    }
                    return SnapshotPreview(
                        name: "\(group).\(label)",
                        group: group,
                        displayName: preview.displayName,
                        fileID: nil,
                        line: nil
                    ) {
                        // Previews are views in a graph, so read them again for each render.
                        let preview = provider._allPreviews[index]
                        let orientation = preview.interfaceOrientation
                        return ResolvedPreview(
                            content: .view(preview.content),
                            layout: preview.layout,
                            landscape: orientation == .landscapeLeft || orientation == .landscapeRight
                        )
                    }
                }
            }
    }

    /// `MyApp/Views/ProfileView.swift` → `ProfileView`.
    private static func sourceFileName(_ fileID: String) -> String {
        let file = fileID.split(separator: "/").last.map(String.init) ?? fileID
        return file.hasSuffix(".swift") ? String(file.dropLast(".swift".count)) : file
    }

    /// The type's name without its module, such as `Outer.Inner_Previews`.
    private static func typeName(_ type: Any.Type) -> String {
        String(reflecting: type).split(separator: ".").dropFirst().joined(separator: ".")
    }
}

extension SnapshotPreview {
    /// The XCTest method that renders the preview, such as `test_ProfileView_Dark`.
    var testName: String {
        PreviewCatalog.testName(name)
    }

    fileprivate func renamed(_ name: String) -> SnapshotPreview {
        SnapshotPreview(name: name, group: group, displayName: displayName, fileID: fileID, line: line, make: make)
    }
}
