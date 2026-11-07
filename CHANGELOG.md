# Changelog

## Unreleased

- Added Rex command launch support through its bundled CLI for tab, window, and current open modes.
- Use a dedicated Hopbar session when Rex has multiple attached sessions.
- Show command errors in an alert instead of only beeping and logging them.
- Reopen Rex through macOS when it is running without an app window, and wait for the window before sending commands.
- Attach the CLI connection to existing and newly created Rex sessions before using session APIs.
- Run window-mode commands in the terminal Rex creates with its new app window, avoiding an extra empty window and session.

## 0.2.0-preview - 2026-05-17

- Added Launch at Login support on macOS 13 or newer.
- Grouped config actions under a dedicated Config submenu.
- Added Ghostty command launch support for tab, window, and current open modes.
- Updated Automation permission text for Ghostty.

## 0.1.0-preview - 2026-05-17

- Initial preview release.
- Added a native Swift/AppKit menu bar launcher with no Dock icon.
- Added minimal JSON configuration at `~/.hopbar.json`.
- Added iTerm and Terminal command launch support.
- Added URL menu item support.
- Added drag-to-Applications preview DMG packaging.
- Added ad-hoc signing for preview builds.
