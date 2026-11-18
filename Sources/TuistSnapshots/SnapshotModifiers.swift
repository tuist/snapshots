import SwiftUI

extension View {
    /// The share of pixels, from 0 to 1, that may differ from the baseline before Tuist reports
    /// this preview's snapshot as changed. Use it for content that renders slightly differently
    /// between runs, such as blurs or gradients.
    ///
    /// ```swift
    /// #Preview {
    ///     ProfileHeader().snapshotDiffThreshold(0.01)
    /// }
    /// ```
    public func snapshotDiffThreshold(_ threshold: Double) -> some View {
        preference(key: SnapshotDiffThresholdKey.self, value: threshold)
    }
}

/// Carries `snapshotDiffThreshold(_:)` to the renderer.
public struct SnapshotDiffThresholdKey: PreferenceKey {
    public static let defaultValue: Double? = nil

    public static func reduce(value: inout Double?, nextValue: () -> Double?) {
        value = nextValue() ?? value
    }
}
