# Changelog

All notable changes are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.2] - 2026-11-03

### Added

- A custom Beam app icon, built from a vector source with a reproducible `.icns` pipeline.

## [0.1.1] - 2026-11-03

First signed and notarized release. Apple Silicon only.

### Added

- Developer ID signed, notarized, stapled DMG; macOS opens it without the unidentified-developer warning.
- Release checksums, SHA-256 verification, and SLSA provenance for the DMG.
- The copy bar now shows the current file and the overall queue total as separate lines.
- The toolbar ring and VoiceOver use the same overall fraction.

### Fixed

- Finished files stay in the copy total until the queue is empty, so the bar no longer resets to the next file.
- The copy bar's bar and byte text now use the same total.

## [0.1.0] - 2026-10-30

First pre-release. Ad-hoc signed, Apple Silicon only; not yet notarized.

### Added

- Shortcut to the phone's `Movies/PrimeCam` folder, shown first with PrimeCam's mark when it exists.
- Copy progress bar at the bottom of the browser window, with the current file, bytes copied, and Stop.
- Clicking the Dock icon with no window open now opens one.
- `-DemoOnly YES` launch option that opens the Demo Phone without touching USB.
- Finder-style browser for an Android phone over MTP, with sidebar, sortable list, and path bar.
- Drag files from the phone to Finder and from Finder to the phone.
- Transfer queue with progress, Stop, and Retry.
- Conflict prompts (Replace or Merge, Keep Both, Skip) with Apply to All.
- Rename, new folder, and delete on the phone.
- Demo Phone for trying the app without a device.

[Unreleased]: https://github.com/ryabinski-labs/droplane/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/ryabinski-labs/droplane/releases/tag/v0.1.2
[0.1.1]: https://github.com/ryabinski-labs/droplane/releases/tag/v0.1.1
[0.1.0]: https://github.com/ryabinski-labs/droplane/releases/tag/v0.1.0
