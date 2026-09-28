# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Calendar Versioning](https://calver.org/) (`vYY.MM.DD.N`).

## [v26.09.28.2] - 2026-09-28

### Added
- Auto-scrolling in `SelectionColumn` using `ScrollViewReader` so the active selection (e.g. 192 kHz) is centered and visible on appear and change.
- High-resolution screenshots in `docs/` (`screenshot.png` and `menubar-popup.png`) embedded in `README.md`.
- `CHANGELOG.md` adhering to Keep a Changelog and CalVer specifications.
- Expanded `.gitignore` covering macOS system files, Xcode artifacts, SwiftPM metadata, and secret/env files.
- `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` in GitHub Actions CI workflow to ensure Node 24 runtime compatibility.
- App bundle build step in CI workflow.

### Changed
- Improved `install-app.sh` legacy watcher cleanup logic to be silent unless a legacy plist exists.
- Updated app bundle versioning to align with CalVer.

## [v26.09.28.1] - 2026-09-28

### Added
- Initial standalone native macOS menu bar app for Audio Format Guard.
- Hardware-agnostic CoreAudio output device format detection and persistence.
- Three-column linked format editor for sample rate, bit depth, and channel count.
- Automatic restore support on device reconnection and capability change events.
- Shell scripts for building, installing, and uninstalling login service (`build-app.sh`, `install-app.sh`, `uninstall-app.sh`).
- Project architecture documentation in `ARCHITECTURE.md`.
