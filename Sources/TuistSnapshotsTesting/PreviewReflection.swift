import DeveloperToolsSupport
import SwiftUI
#if canImport(UIKit)
    import UIKit

    typealias PlatformView = UIView
    typealias PlatformViewController = UIViewController
#elseif canImport(AppKit)
    import AppKit

    typealias PlatformView = NSView
    typealias PlatformViewController = NSViewController
#endif

/// What a preview renders.
enum PreviewContent {
    case view(AnyView)
    case platformView(PlatformView)
    case platformViewController(PlatformViewController)
}

/// A preview's content and the traits that decide how it is rendered.
struct ResolvedPreview {
    var content: PreviewContent
    var layout: PreviewLayout = .device
    var landscape = false
}

/// Reads `#Preview` values through reflection.
///
/// `DeveloperToolsSupport.Preview` keeps its content in SDK-private types: a source such as
/// `DefaultPreviewSource<ViewPreviewBody>`, which stores a closure that makes the body. Their
/// fields are visible to `Mirror`, and a closure is called through its runtime type, so no
/// private declarations are needed.
enum PreviewReflection {
    /// The traits a `#Preview` declares, such as `.sizeThatFitsLayout` or `.landscapeLeft`.
    static func traits(of preview: Preview) -> (layout: PreviewLayout, landscape: Bool) {
        var layout = PreviewLayout.device
        var landscape = false
        for trait in children(of: field(of: preview, named: "traits") ?? [Any]()) {
            for value in [trait] + children(of: trait) {
                if let value = value as? PreviewLayout { layout = value }
                // `.landscapeLeft` and the like store an SDK-private `PreviewInterfaceOrientation`.
                if String(describing: type(of: value)) == "PreviewInterfaceOrientation" {
                    landscape = String(describing: value).hasPrefix("landscape")
                }
            }
        }
        return (layout, landscape)
    }

    @MainActor static func content(of preview: Preview) -> PreviewContent? {
        guard let dataSource = field(of: preview, named: "dataSource") else { return nil }
        // `dataSource` is an enum whose payload is the source.
        let source = children(of: dataSource).first ?? dataSource
        return renderableContent(in: source, depth: 0)
    }

    /// Looks through a source's fields for a view, view controller, or a closure that makes one.
    @MainActor private static func renderableContent(in value: Any, depth: Int) -> PreviewContent? {
        if let content = content(value) { return content }
        guard depth < 6 else { return nil }
        for child in children(of: value) {
            if let content = renderableContent(in: child, depth: depth + 1) { return content }
            if let result = callClosure(child), let content = renderableContent(in: result, depth: depth + 1) {
                return content
            }
        }
        return nil
    }

    @MainActor private static func content(_ value: Any) -> PreviewContent? {
        if let viewController = value as? PlatformViewController { return .platformViewController(viewController) }
        if let view = value as? PlatformView { return .platformView(view) }
        if let view = value as? any View { return .view(AnyView(view)) }
        return nil
    }

    static func field(of value: Any, named name: String) -> Any? {
        Mirror(reflecting: value).children.first { $0.label == name }?.value
    }

    private static func children(of value: Any) -> [Any] {
        Mirror(reflecting: value).children.map(\.value)
    }

    /// Calls a closure that takes no arguments and returns a type only known at runtime, such
    /// as `@MainActor () -> ViewPreviewBody`, by reading the result type from the function's
    /// metadata and opening it as a generic parameter.
    ///
    /// `as?` can't do this: in Swift 6 a `@MainActor` function type is implicitly `@Sendable`, and
    /// the runtime refuses to cast SwiftUI's non-`Sendable` closure to it. Sendability doesn't
    /// change a closure's representation, so the closure is read from the existential directly once
    /// its metadata shows the shape it is read as.
    @MainActor private static func callClosure(_ value: Any) -> Any? {
        let metadata = unsafeBitCast(type(of: value), to: UnsafeRawPointer.self)
        let wordSize = MemoryLayout<UInt>.size
        let functionKind: UInt = 0x302
        // https://github.com/swiftlang/swift/blob/main/include/swift/ABI/MetadataValues.h (FunctionTypeFlags)
        let parameterCountMask: UInt = 0xFFFF
        let conventionMask: UInt = 0xFF_0000
        let throwsFlag: UInt = 0x0100_0000
        let asyncFlag: UInt = 0x2000_0000
        let extendedFlags: UInt = 0x8000_0000
        guard metadata.load(as: UInt.self) == functionKind else { return nil }
        let flags = metadata.load(fromByteOffset: wordSize, as: UInt.self)
        // A Swift, synchronous function without parameters or extended flags (such as typed
        // throws or `@isolated(any)`, which change its representation).
        guard flags & (parameterCountMask | conventionMask | asyncFlag | extendedFlags) == 0 else { return nil }
        let resultType = unsafeBitCast(
            metadata.load(fromByteOffset: 2 * wordSize, as: UnsafeRawPointer.self),
            to: Any.Type.self
        )
        // A closure fits inline in an existential's buffer, at its start.
        func call<Result>(_: Result.Type) -> Any? {
            withUnsafeBytes(of: value) { buffer in
                if flags & throwsFlag != 0 {
                    return try? buffer.load(as: (@MainActor () throws -> Result).self)()
                }
                return buffer.load(as: (@MainActor () -> Result).self)()
            }
        }
        return _openExistential(resultType, do: call)
    }
}
