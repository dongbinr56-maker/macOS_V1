# Contributing

## Development Environment

- macOS 14 or later
- Xcode 16 or later
- Swift 6 toolchain

## First Run

1. Open `AIWebUsageMonitor.xcodeproj` in Xcode, or use `swift build` for a CLI build check.
2. Run the app and add at least one Codex, Claude, or Cursor session from the menu bar settings screen.
3. Verify the target site still exposes the usage text or quota cards expected by the scraper.

## Useful Commands

```bash
swift build
swift test
./scripts/build_app.sh
```

## Documentation

Behavior changes must update the matching document.

- User-facing overview: `README.md`
- Architecture and data flow: `docs/ARCHITECTURE.md`
- Pixel Office rules and movement: `docs/PIXEL_OFFICE.md`
- Build, CI, and troubleshooting: `docs/OPERATIONS.md`

## Pull Request Checklist

Before opening a PR, make sure all of the following are true:

- The project builds with `swift build`
- The test suite passes with `swift test`
- The app bundle still builds with `./scripts/build_app.sh`
- UI changes were checked in the menu bar popover for both `Office` and `List` modes
- README and the relevant file under `docs/` were updated when behavior changed

## Scraper Changes

This project depends on production web UI markup from Codex, Claude, and Cursor.

- Keep selector logic defensive and text-hint based where possible.
- Include the failing text snippet or a redacted DOM excerpt when you fix a scraper regression.
- Avoid shipping platform-specific fixes without checking the fallback paths in `PlatformScraper.swift`.

## Issues

- Use the bug template for scraper regressions, parsing failures, login issues, and menu bar crashes.
- Use the feature template for new platform support, UI improvements, or workflow requests.

## Scope

Please keep pull requests focused. A PR that changes both scraper logic and a large UI refactor is much harder to review and verify.
