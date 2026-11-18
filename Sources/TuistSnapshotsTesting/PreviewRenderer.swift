import SwiftUI
import TuistSnapshots

/// A rendered preview.
struct Snapshot {
    var png: Data
    var width: Int
    var height: Int
    /// Whether it rendered dark, such as with `preferredColorScheme(.dark)`.
    var isDark: Bool
    /// From `snapshotDiffThreshold(_:)`.
    var diffThreshold: Double?
}

enum PreviewRenderError: LocalizedError {
    case emptySize(String)
    case encoding(String)

    var errorDescription: String? {
        switch self {
        case let .emptySize(name): "The preview \(name) rendered with no width or height."
        case let .encoding(name): "The preview \(name) couldn't be encoded as a PNG."
        }
    }
}

/// Collects preferences a SwiftUI preview sets while it renders.
private final class PreferenceBox: @unchecked Sendable {
    var diffThreshold: Double?
}

extension PreviewContent {
    fileprivate func observingPreferences(_ box: PreferenceBox) -> PreviewContent {
        guard case let .view(view) = self else { return self }
        return .view(AnyView(view.onPreferenceChange(SnapshotDiffThresholdKey.self) { box.diffThreshold = $0 }))
    }
}

/// Waits briefly so SwiftUI can apply state set in `onAppear` and `task` before the image is taken.
@MainActor private func settle() {
    for _ in 0 ..< 2 {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}

#if canImport(UIKit)
    import UIKit

    /// Renders previews in a window, so UIKit content, safe areas, and the trait environment
    /// behave as they do in the app.
    @MainActor
    final class PreviewRenderer {
        private let window: UIWindow
        /// Without a host app there is no scene to show the window in: it is then drawn offscreen.
        private let isOnScreen: Bool

        private static func isDeviceLayout(_ layout: PreviewLayout) -> Bool {
            switch layout {
            case .fixed, .sizeThatFits: false
            default: true
            }
        }

        init() {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            if let scene {
                window = UIWindow(windowScene: scene)
                isOnScreen = true
            } else {
                window = UIWindow(frame: UIScreen.main.bounds)
                isOnScreen = false
            }
            window.windowLevel = .statusBar + 1
        }

        func render(_ preview: ResolvedPreview, name: String) throws -> Snapshot {
            let box = PreferenceBox()
            let (controller, sizing) = viewController(
                for: preview.content.observingPreferences(box),
                ignoresSafeArea: !Self.isDeviceLayout(preview.layout)
            )
            let screen = window.screen.bounds.size
            let deviceSize = preview.landscape
                ? CGSize(width: max(screen.width, screen.height), height: min(screen.width, screen.height))
                : CGSize(width: min(screen.width, screen.height), height: max(screen.width, screen.height))

            // Light unless the preview asks otherwise (`preferredColorScheme` sets the window's
            // style), whatever the simulator's appearance.
            window.overrideUserInterfaceStyle = .light
            controller.traitOverrides.verticalSizeClass = preview.landscape ? .compact : .regular
            window.rootViewController = controller
            window.frame = CGRect(origin: .zero, size: deviceSize)
            window.isHidden = false
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            settle()

            let size = size(of: sizing, layout: preview.layout, deviceSize: deviceSize)
            guard size.width >= 1, size.height >= 1 else { throw PreviewRenderError.emptySize(name) }
            window.frame = CGRect(origin: .zero, size: size)
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            settle()

            let format = UIGraphicsImageRendererFormat()
            format.scale = window.screen.scale
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
                if isOnScreen {
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                } else {
                    window.layer.render(in: context.cgContext)
                }
            }
            let isDark = controller.traitCollection.userInterfaceStyle == .dark
            window.isHidden = true
            window.rootViewController = nil

            guard let png = image.pngData(), let cgImage = image.cgImage else { throw PreviewRenderError.encoding(name) }
            return Snapshot(
                png: png, width: cgImage.width, height: cgImage.height, isDark: isDark, diffThreshold: box.diffThreshold
            )
        }

        /// The controller to show, and the view whose size a size-to-fit preview takes.
        private func viewController(for content: PreviewContent, ignoresSafeArea: Bool) -> (UIViewController, Sizing) {
            switch content {
            case let .view(view):
                let controller = UIHostingController(rootView: view)
                controller.view.backgroundColor = .systemBackground
                // Like Xcode's canvas, only a device-sized preview has safe areas.
                if ignoresSafeArea { controller.safeAreaRegions = [] }
                return (controller, .hosting(controller))
            case let .platformViewController(controller):
                return (controller, .view(controller.view))
            case let .platformView(view):
                let controller = UIViewController()
                controller.view.backgroundColor = .systemBackground
                view.frame = controller.view.bounds
                view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                controller.view.addSubview(view)
                return (controller, .view(view))
            }
        }

        private enum Sizing {
            case hosting(UIHostingController<AnyView>)
            case view(UIView)
        }

        private func size(of sizing: Sizing, layout: PreviewLayout, deviceSize: CGSize) -> CGSize {
            switch layout {
            case let .fixed(width, height):
                return CGSize(width: width, height: height)
            case .sizeThatFits:
                // Fits the device's width, like Xcode's canvas.
                let fitting = switch sizing {
                case let .hosting(controller):
                    controller.sizeThatFits(in: CGSize(width: deviceSize.width, height: .greatestFiniteMagnitude))
                case let .view(view):
                    view.systemLayoutSizeFitting(
                        UIView.layoutFittingCompressedSize,
                        withHorizontalFittingPriority: .fittingSizeLevel,
                        verticalFittingPriority: .fittingSizeLevel
                    )
                }
                return CGSize(width: ceil(min(fitting.width, deviceSize.width)), height: ceil(fitting.height))
            default:
                return deviceSize
            }
        }
    }

#elseif canImport(AppKit)
    import AppKit

    /// Renders previews in an offscreen window, which `preferredColorScheme` sets the appearance of.
    /// A Mac has no device size, so `.device` previews size to fit.
    @MainActor
    final class PreviewRenderer {
        func render(_ preview: ResolvedPreview, name: String) throws -> Snapshot {
            let box = PreferenceBox()
            let view: NSView
            switch preview.content.observingPreferences(box) {
            case let .view(content):
                var content = content
                if case let .fixed(width, height) = preview.layout {
                    content = AnyView(content.frame(width: width, height: height))
                }
                let hosting = NSHostingView(rootView: content)
                hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
                view = hosting
            case let .platformViewController(controller):
                view = controller.view
            case let .platformView(platformView):
                view = platformView
            }
            if case let .fixed(width, height) = preview.layout {
                view.frame.size = CGSize(width: width, height: height)
            } else if view.frame.isEmpty {
                view.frame.size = view.fittingSize
            }
            guard view.bounds.width >= 1, view.bounds.height >= 1 else { throw PreviewRenderError.emptySize(name) }

            let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            settle()
            defer { window.contentView = nil }

            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw PreviewRenderError.encoding(name)
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw PreviewRenderError.encoding(name)
            }
            let isDark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return Snapshot(
                png: png, width: bitmap.pixelsWide, height: bitmap.pixelsHigh, isDark: isDark,
                diffThreshold: box.diffThreshold
            )
        }
    }
#endif
