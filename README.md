# Hopbar

Native lightweight macOS menu bar launcher written in Swift/AppKit.

Hopbar lives only in the macOS menu bar. It reads a small JSON file, builds a nested menu, opens URLs, and runs commands in iTerm, Terminal, Ghostty, or Rex.

## Install Preview DMG

Download `Hopbar-0.2.0-preview.dmg` from a release, open it, drag `Hopbar.app` to `Applications`, then launch Hopbar from `Applications`.

Current preview builds are ad-hoc signed, not Apple Developer ID notarized. If macOS blocks the first launch, use right-click -> Open.

## Build Locally

```sh
make app
open "dist/Hopbar.app"
```

## Preview DMG

```sh
make dmg
open "dist/Hopbar-0.2.0-preview.dmg"
```

Verify local artifacts:

```sh
make verify
```

## Config

On first launch, Hopbar creates `~/.hopbar.json`.

```json
{
  "terminal": "iterm",
  "open": "tab",
  "items": [
    { "title": "Prod SSH", "command": "ssh user@prod.example.com" },
    { "title": "Docs", "url": "https://example.com" },
    {
      "title": "Local",
      "items": [
        { "title": "Logs", "command": "tail -f /var/log/system.log", "open": "window" }
      ]
    }
  ]
}
```

- `terminal`: `iterm`, `terminal`, `ghostty`, or `rex`; default is `iterm`.
- `open`: `tab`, `window`, or `current`; default is `tab`.
- Each item must define exactly one of `command`, `url`, or `items`.
- `terminal` and `open` can be overridden per command item or group.

Hopbar uses its own minimal JSON format.

## Permissions

Hopbar uses Apple Events to run commands in iTerm, Terminal, or Ghostty. macOS may ask for Automation permission on first use.

Ghostty command execution requires Ghostty 1.3.0 or newer.

For Rex, set `"terminal": "rex"` and enable **Remote Control** in [Rex settings](https://www.superlogical.com/rex/docs/reference/mac-settings#client-info) (**Server → Client Info**, or **Rex Server** in older builds). Hopbar finds the CLI inside the registered Rex app (including Rex Beta); no PATH setup is needed. `tab` creates a terminal tab, `current` sends the command to the focused terminal when the target is clear, and `window` opens a new app window. If no session exists, Hopbar creates one. When several sessions are attached and Rex cannot identify a single target, Hopbar creates or reuses a dedicated session named `Hopbar` for `tab` and `current`.

Hopbar asks macOS to open Rex when needed. If Rex restores an existing window at launch, `window` creates a fresh tab in that window so it doesn't send input to a terminal you already had open.

Use `current` only when the focused terminal is at an idle shell prompt: Rex receives the command as terminal input. Avoid opening or closing Rex windows while Hopbar is resolving a new window; Rex's New Window action does not return a session ID.

Terminal tab mode uses System Events to create a new tab, so macOS may also ask for Accessibility permission.

Launch at login uses Apple's native login item API and is available on macOS 13 or newer.

## Development

Install Lua (`brew install lua`) before running the tests. The Rex tests use a simulated Rex server and don't require the app.

```sh
swift test
make dmg
make verify
```

Generated artifacts are written to `dist/` and are not committed.

## Releases

Preview releases are built by GitHub Actions from `v*` tags. The workflow uploads the preview DMG and `SHA256SUMS` to the GitHub Release.

```sh
git tag v0.2.0-preview
git push origin v0.2.0-preview
```

Preview release artifacts are ad-hoc signed and not Apple Developer ID notarized.

## License

MIT
