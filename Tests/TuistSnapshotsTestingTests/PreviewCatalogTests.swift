import SwiftUI
import Testing
import TuistSnapshots
@testable import TuistSnapshotsTesting

private struct Badge: View {
    var body: some View {
        Text("Badge").padding().background(Color.red)
    }
}

#Preview("Named", traits: .sizeThatFitsLayout) {
    Badge().snapshotDiffThreshold(0.25)
}

#Preview {
    Text("First unnamed")
}

#Preview {
    Text("Second unnamed")
}

#Preview("Fixed", traits: .fixedLayout(width: 120, height: 40)) {
    Text("Fixed")
}

#Preview("Landscape", traits: .landscapeRight) {
    Text("Landscape")
}

struct LegacyBadge_Previews: PreviewProvider {
    static var previews: some View {
        Badge().previewDisplayName("Legacy")
        Badge().preferredColorScheme(.dark)
    }
}

@MainActor
@Suite struct PreviewCatalogTests {
    @Test func finds_macro_and_provider_previews_with_stable_names() {
        let names = PreviewCatalog.previews().map(\.name)

        #expect(names == [
            "PreviewCatalogTests.Named",
            "PreviewCatalogTests.Preview_1",
            "PreviewCatalogTests.Preview_2",
            "PreviewCatalogTests.Fixed",
            "PreviewCatalogTests.Landscape",
            "LegacyBadge.Legacy",
            "LegacyBadge.Preview",
        ])
    }

    @Test func renders_previews_with_their_traits_and_settings() throws {
        let previews = Dictionary(uniqueKeysWithValues: PreviewCatalog.previews().map { ($0.name, $0) })
        let renderer = PreviewRenderer()
        func render(_ name: String) throws -> (ResolvedPreview, Snapshot) {
            let resolved = try #require(previews[name]).make()
            return (resolved, try renderer.render(resolved, name: name))
        }

        let (named, namedSnapshot) = try render("PreviewCatalogTests.Named")
        #expect(PreviewSnapshotTestCase.tags(named, snapshot: namedSnapshot) == ["layout": "size_that_fits"])
        #expect(namedSnapshot.diffThreshold == 0.25)
        #expect(namedSnapshot.png.starts(with: [0x89, 0x50, 0x4E, 0x47]))

        let (fixed, fixedSnapshot) = try render("PreviewCatalogTests.Fixed")
        #expect(PreviewSnapshotTestCase.tags(fixed, snapshot: fixedSnapshot) == ["layout": "fixed_120x40"])
        let scale = fixedSnapshot.width / 120
        #expect(scale >= 1)
        #expect(fixedSnapshot.width == 120 * scale && fixedSnapshot.height == 40 * scale)
        #expect(fixedSnapshot.diffThreshold == nil)

        let landscape = try #require(previews["PreviewCatalogTests.Landscape"]).make()
        #expect(landscape.landscape)
        #expect(!(try #require(previews["PreviewCatalogTests.Named"]).make().landscape))

        let (_, lightSnapshot) = try render("LegacyBadge.Legacy")
        #expect(!lightSnapshot.isDark)
        let (dark, darkSnapshot) = try render("LegacyBadge.Preview")
        #expect(PreviewSnapshotTestCase.tags(dark, snapshot: darkSnapshot) == ["color_scheme": "dark"])
    }

    @Test func names_files_and_tests_safely() {
        #expect(PreviewCatalog.fileName("Profile/Header – Dark") == "Profile_Header___Dark")
        #expect(PreviewCatalog.testName("Profile.Header-Dark") == "test_Profile_Header_Dark")
    }
}
