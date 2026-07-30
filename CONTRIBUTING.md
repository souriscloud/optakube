# Contributing to OptaKube

Thanks for taking a look. Bug reports and small, focused pull requests are both welcome.

## Getting set up

```bash
git clone https://github.com/souriscloud/optakube.git
cd optakube
swift build
swift run          # launches the app
swift test         # runs the test suite
```

Requires macOS 14 (Sonoma) or later and Xcode 15.3+ (the package declares
`swift-tools-version: 5.10`). Opening `Package.swift` in Xcode and pressing ⌘R works too.

Note that `swift run` launches the raw binary rather than an app bundle. Sparkle
auto-update and user notifications are both disabled in that mode — they need a real
bundle and correctly no-op without one — so those two paths can only be exercised from a
packaged build.

## Before opening a pull request

- `swift build` and `swift test` both pass. CI runs them on macOS for every push.
- Add a note under `## [Unreleased]` in `CHANGELOG.md`.
- Don't bump versions or touch `appcast.xml`. Releases are maintainer-only: `scripts/release.sh`
  owns the version bump, signing, notarization, and the update feed. A pull request that
  edits the appcast would break auto-update for existing users.

## House style

The codebase has a consistent voice; matching it matters more than any rule below.

- **SwiftUI + `@Observable`.** No Combine.
- **`URLSession` only** for Kubernetes API calls — no third-party HTTP layer. `Yams`,
  `SwiftTerm`, and `Sparkle` are the only dependencies, and the bar for adding a fourth is
  high.
- **Async/await throughout**, with `@MainActor` for anything touching UI state.
- **Comments explain why, not what.** Most code needs none. Where a comment exists it's
  usually recording a non-obvious constraint — an API server behaviour, a SwiftUI quirk, a
  reason something is ordered the way it is. Please keep that standard rather than
  narrating the code.
- **Surface errors.** If an operation can fail in a way a user would notice, the user
  should be told, with the reason. A bare `try?` on anything that mutates cluster state is
  a bug, not a shortcut.

## Adding a resource type

There are 32, and they follow one shape. To add another:

1. Model in `Sources/OptaKube/Models/Resources/`, conforming to `K8sResource`.
2. A case in the `ResourceType` enum (`Models/ResourceType.swift`) — this drives the API
   group and path, the SF Symbol, the sidebar category, and `kind`.
3. Storage on `AppViewModel` plus a `case` in `AppViewModel+Resources.swift`'s list switch
   and `clearResources`.
4. A `case` in `AppViewModel+Watch.swift`'s `runWatch` so it gets live updates.
5. A table in `ResourceListView.swift` with a row wrapper conforming to `ResourceRow`.
6. A `*DetailContent` view in `Views/Detail/ResourceDetailContents.swift`, routed from
   `ResourceDetailView`.
7. Counting in `StatusBar.swift` and searching in `SpotlightSearch.swift`.

Steps 4, 6 and 7 are easy to forget, and forgetting them is what previously left two
thirds of the resource types without live updates, without a detail view, and invisible to
⌘K. If you add a type, add it everywhere.

## Reporting bugs

Use **Help ▸ Send Feedback** in the app — it pre-fills the version, macOS build, and
architecture. Or open an issue directly. Please don't attach kubeconfigs, tokens, or
certificate data.
