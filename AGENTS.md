# AGENTS.md

## Project

Hopbar is a lightweight native macOS menu bar launcher written in Swift/AppKit.
It reads `~/.hopbar.json`, builds a nested status bar menu, opens URLs, and runs commands in iTerm or Terminal.

## Git

- Do not create commits unless the user explicitly asks for a commit.
- Do not push unless the user explicitly asks for a push.

## Commands

- Run tests: `swift test`
- Build app bundle: `make app`
- Build preview DMG: `make dmg`
- Verify preview artifacts: `make verify`
- Clean generated artifacts: `make clean`
- Create a preview release locally: `make dmg && make verify`

## Release Model

- Current builds are ad-hoc signed preview builds.
- Preview DMGs are not Apple Developer ID notarized.
- Do not describe preview DMGs as fully trusted production releases until Developer ID signing and notarization are added.
- Generated artifacts belong in `dist/` and `.build/`; do not commit them.
- GitHub release artifacts are produced by `.github/workflows/release.yml` on `v*` tags.

## Code Guidelines

- Keep the app AppKit-only and menu-bar-only.
- Do not add SwiftUI, storyboards, XIBs, or preference windows unless explicitly requested.
- Preserve the minimal JSON config model.
- Keep command execution isolated in `CommandRunner`.
- Keep launch-at-login behavior isolated in `LoginItemManager`.
- Keep config parsing and validation isolated in `ConfigStore` and `MenuModel`.
- Use repo-native SVG/ICNS assets for icons; do not depend on generated bitmap-only assets.

## Verification

Before claiming release readiness, run:

```sh
swift test
make dmg
make verify
```

If signing/notarization changes are made later, also verify:

```sh
codesign --verify --deep --strict --verbose=2 dist/Hopbar.app
spctl --assess --type execute --verbose=4 dist/Hopbar.app
stapler validate dist/Hopbar.app
```
