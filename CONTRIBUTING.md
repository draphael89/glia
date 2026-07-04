# Contributing to Glia

Thanks for wanting to help. Glia is deliberately small — a native window into
a [gbrain](https://github.com/garrytan/gbrain). The bar for merging is:
does it make the brain more tangible, more beautiful, or faster — without
growing the maintenance surface?

## Ground rules

- **Native only.** No web views, no Electron, no JS runtimes. The canvas is
  Metal; the chrome is SwiftUI. This is the project's identity.
- **Read-only by design (v1).** Glia observes the brain; it does not write
  to it. Write features need a very strong case.
- **Performance is a feature.** The README publishes a perf budget. PRs that
  regress GPU frame time or idle cost need to say so and why it's worth it.
- **Swift 6 strict concurrency stays on.** No `@unchecked Sendable` without
  a comment explaining the invariant.

## Dev setup

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Glia.xcodeproj -scheme Glia -configuration Release build
xcodebuild test -project Glia.xcodeproj -scheme Glia -destination 'platform=macOS'
```

Point Glia at data: either a real gbrain export at `~/.gbrain/viz/graph.json`
or any JSON matching the shape in the README.

### The snapshot loop

Visual work iterates through deterministic offscreen renders — no clicking:

```bash
APP=…/Glia.app/Contents/MacOS/Glia
GLIA_SNAPSHOT=/tmp/a.png $APP                          # overview
GLIA_SNAPSHOT=/tmp/b.png GLIA_SNAPSHOT_FOCUS=slug $APP # focus mode
GLIA_SNAPSHOT=/tmp/c.png GLIA_SNAPSHOT_REPLAY=0.5 $APP # replay state
```

Attach before/after snapshots to any PR that changes pixels.

## Good first issues

- Additional `BrainSource` adapters behind the existing protocol
- Label collision tuning at mid-zoom densities
- Localization scaffolding
- Reduce Transparency support (we honor Reduce Motion already)
