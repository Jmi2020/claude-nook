# Repository Guidelines

## Project Structure & Modules
- App sources live in `ClaudeNook/` (Swift, SwiftUI, AppKit). Assets in `ClaudeNook/Assets.xcassets`. Configuration and entitlement files are in `ClaudeNook/Resources/`.
- Hooks and networking logic are under `ClaudeNook/Services/` and `ClaudeNook/Core/`; UI components/views live in `ClaudeNook/UI/`.
- Xcode project file: `ClaudeNook.xcodeproj`. Scripts for setup/build/release are in `scripts/`.

## Build, Run, and Development
- Build (Debug): `xcodebuild -scheme ClaudeNook -configuration Debug build`.
- Build (Release): `xcodebuild -scheme ClaudeNook -configuration Release build`.
- Open in Xcode: `open ClaudeNook.xcodeproj`.
- Remote hook install (remote machine): `./scripts/setup/remote-setup.sh` (prompts for host/port/token).
- Local hook install is automatic on app launch via `HookInstaller`; no manual step needed.

## Coding Style & Naming
- Language: Swift 5+. Prefer SwiftUI patterns already present; follow existing file-level organization (Core/Services/UI separation).
- Naming: Types in UpperCamelCase, methods/properties in lowerCamelCase, enums singular. Keep filenames matching primary type.
- Formatting: Xcode defaults; aim for clear, small extensions and protocol-driven composition. Keep comments minimal and purposeful.

## Testing Guidelines
- No automated test target is currently present. Favor manual QA: launch app, verify notch UI, and exercise hook flows (local socket and TCP).
- When adding tests, mirror Swift/XCTest conventions; name tests `test<Behavior>` and place under a new `ClaudeNookTests` target.

## Commit & Pull Request Guidelines
- Commits: concise, imperative subject (e.g., `Add TCP timeout handling`, `Fix permission response parsing`). Group related changes; avoid noisy formatting-only commits unless isolated.
- Pull Requests: include a brief summary, testing notes (commands run, manual checks), and screenshots/GIFs for UI changes. Link issues when applicable and call out risks (signing, entitlements, network/bind changes).

## Security & Configuration Tips
- Tokens for remote access are user-specific; never commit them. Respect `.gitignore` (build products, Sparkle keys, CLAUDE.md).
- Default Unix socket path: `/tmp/claude-nook.sock`; TCP defaults to port `4851`. Environment overrides live in `~/.config/claude-nook/claude-nook.env`.
- For remote use, prefer localhost bind + SSH tunnel unless you trust the network. Rotate tokens after sharing.***
