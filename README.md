# Tuist Snapshots

Turns your SwiftUI previews into snapshot tests. Every `#Preview` and `PreviewProvider` in your app
renders as its own XCTest test, and [Tuist](https://tuist.dev) compares the images with their
baselines, so pull requests show the visual changes they make for review. There are no reference
images to record or keep in Git.

## Installation

Add the package to your project:

```swift
.package(url: "https://github.com/tuist/snapshots", from: "0.1.0")
```

- Link `TuistSnapshotsTesting` from a unit test target hosted by your app. It finds the previews
  of the app and of the frameworks it links.
- Optionally link `TuistSnapshots` from your app, for the modifiers that configure a snapshot.

## Usage

Add one test class:

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

Then run the tests with Tuist, which uploads the images and compares them with the baseline:

```bash
# Projects Tuist generates
tuist test --snapshots

# Any Xcode project
tuist xcodebuild test --snapshots -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 17'
```

The run fails when images changed and nobody has approved the changes yet. Review and approve them
in the Tuist dashboard, or with the Approve button on the pull request's check.

Without `--snapshots`, each test attaches its image to the test result instead.

### What gets rendered

| Preview | Image name |
| --- | --- |
| `#Preview("Dark") { … }` in `ProfileCard.swift` | `ProfileCard.Dark` |
| `#Preview { … }`, the only unnamed one in the file | `ProfileCard.Preview` |
| Several unnamed `#Preview`s | `ProfileCard.Preview_1`, `ProfileCard.Preview_2`, … in source order |
| `Badge_Previews: PreviewProvider` with `.previewDisplayName("New")` | `Badge.New` |

- Images are grouped by the file a `#Preview` is declared in, or by the `PreviewProvider` type.
- Each preview is a test named after its image, such as `test_ProfileCard_Dark`, so you can run a
  few with `-only-testing`. The others are reported as skipped rather than removed.
- SwiftUI views, UIKit views, and view controllers are supported.
- These traits are honored: `.sizeThatFitsLayout`, `.fixedLayout(width:height:)`,
  `.landscapeLeft`/`.landscapeRight`, and the matching `PreviewProvider` modifiers.
  `preferredColorScheme(.dark)` renders dark. Everything else renders light at the simulator's
  device size.

### Configuring a snapshot

```swift
import TuistSnapshots

#Preview {
    // Up to 2% of the pixels may differ before the snapshot counts as changed.
    GradientHeader().snapshotDiffThreshold(0.02)
}
```

To leave previews out, override `includes(_:)`:

```swift
final class PreviewSnapshotTests: PreviewSnapshotTestCase {
    override class func includes(_ preview: SnapshotPreview) -> Bool {
        preview.group != "DebugMenu"
    }
}
```

## How it works

- **Finding previews.** Swift records every protocol conformance in the binary
  (`__swift5_proto`). The library reads those records for the app's images, the system's excluded,
  to find the `PreviewRegistry` types the `#Preview` macro generates and the `PreviewProvider`
  types.
- **Reading a preview's content.** It uses reflection, so no private SDK declarations or prebuilt
  binaries are needed.
- **Rendering.** Each preview renders in a window on the simulator, so UIKit content, safe areas,
  and trait changes behave as in the app.
- **Exporting.** When `SNAPSHOTS_EXPORT_DIR` is set (`tuist … --snapshots` sets
  `TEST_RUNNER_SNAPSHOTS_EXPORT_DIR`), it writes each image there as a PNG. Next to it goes a JSON
  file with `display_name`, `group`, `tags` and `diff_threshold`. It also writes
  `tuist-all-image-names.txt`, which lists every preview. `tuist snapshots upload <dir>` reads that
  format, so you can also upload the directory yourself.

## Requirements

iOS 17 or macOS 14. Built with Swift 6 tools (Xcode 16 or later); tested with Xcode 27.

## Example

[`Examples/PreviewsApp`](Examples/PreviewsApp) is an app with SwiftUI, UIKit, and
`PreviewProvider` previews. Run it with `tuist generate` and `tuist xcodebuild test --snapshots`.

## Acknowledgements

This library builds on the ideas of [SnapshotPreviews](https://github.com/getsentry/SnapshotPreviews),
created by Emerge Tools and now maintained by Sentry. The approach comes from it:

- finding previews through the binary's conformance records;
- adding one XCTest test per preview at runtime;
- exporting PNGs with JSON metadata to `SNAPSHOTS_EXPORT_DIR`.

We kept its export format, so images rendered by either library upload to Tuist the same way.
Thank you to its authors.

## License

MIT
