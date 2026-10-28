# Changelog

## 0.1.0 — unreleased (beta)

First public beta. Developed without a Mac; native behavior and the live Grok Bot
integration await verification by beta testers.

- Discovers Grok Bot bots, names and avatars (built-in shapes and colors, uploaded images) from Grok Bot's local data, read-only
- Shows a character only when a bot is waiting for the user (`awaitingUserResponse`, optional sidebar signal); never for unread, progress or finished states
- Confirmation delay, fingerprint deduplication, wake grace period, and resolution when answered elsewhere
- Speech bubble with multiple-choice answers, free-text replies, opt-in two-step inline approvals and "Open in Grok Bot"
- Reply delivery through Accessibility with exact bot matching, heading checks, draft protection, clipboard and focus restoration, and verification before "Delivered"
- Queue for several bots, snooze, dismiss, menu-bar list
- Right, bottom or left edge; multiple displays, Spaces and full screen; sizes; lively/subtle/minimal animation; Reduce Motion
- Settings, first-run onboarding, Accessibility diagnostics, privacy-preserving diagnostics export, `--version` and `--check`
- Demo mode with clearly labelled sample bots
- Browser-based design simulator
- CI on Linux and macOS (Apple silicon and Intel); universal DMG/ZIP releases with SHA-256 checksums; optional signing and notarization
