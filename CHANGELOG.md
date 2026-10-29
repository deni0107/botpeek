# Changelog

## 0.1.0 — unreleased (beta)

First public beta. Bot discovery, avatars, question detection and multiple-choice answers
are checked on a real Mac with Grok Bot 0.78.1; typed replies and inline approvals await
verification by beta testers.

- Detects questions, approvals and forms from Grok Bot's cached conversations: Grok Bot 0.78.1 doesn't set `awaitingUserResponse` for questions asked in chat. Approvals and forms open in Grok Bot only
- Opens the right conversation when Grok Bot is in the background (0.78.1 applied each Accessibility press one press late) and recognizes 0.78.1's inline answer buttons
- Opening a request in Grok Bot snoozes its character, so it doesn't hover while you answer there; it resolves when Grok Bot marks it done
- Typed replies are sent in the background by default, without bringing Grok Bot forward; pasting is the fallback in Settings
- `--probe-open <bot log tag>` shows each step of opening a bot's conversation, without names
- Never replies to an already-open conversation when another bot has the same name

- Discovers Grok Bot bots, names and avatars (built-in shapes and colors, uploaded images) from Grok Bot's local data, read-only
- Draws built-in avatars with Grok Bot's own renderer, loaded from the signed, installed Grok Bot at launch; BotPeek's drawings are the fallback. All 26 Grok Bot shapes (incl. `pumpkin`, `leaf`, `shield`…) and its 11 colors and gradients (incl. `violet`, `magenta`) are recognized
- `--render-avatars <folder>` writes every avatar as PNGs for a visual check
- Shows a character only when a bot is waiting for the user (`awaitingUserResponse`, optional sidebar signal); never for unread, progress or finished states
- Confirmation delay, fingerprint deduplication, wake grace period, and resolution when answered elsewhere
- Speech bubble with multiple-choice answers, free-text replies, opt-in two-step inline approvals and "Open in Grok Bot"
- Reply delivery through Accessibility with exact bot matching, heading checks, draft protection and verification before "Delivered"
- Queue for several bots, newest first, with the others peeking out in a stack beside the active character (hover for name and wait time, click to switch); snooze, dismiss, menu-bar list with wait times
- Bubble tucks away after 30 s idle, gentle reminder wiggles, quick snooze/dismiss on hover
- Keyboard: ⌃⌥B global shortcut, 1–9 for answers, ⌘[ ⌘] ⌘L ⌘D ⌘O in the bubble
- Drag the character along the edge; it follows the pointer to another display
- Pause characters from the menu bar; hide from screenshots and screen sharing (best effort)
- Right, bottom or left edge; multiple displays, Spaces and full screen; sizes; lively/subtle/minimal animation; Reduce Motion
- Settings, first-run onboarding, Accessibility diagnostics, privacy-preserving diagnostics export, `--version` and `--check`
- Demo mode with clearly labelled sample bots
- Browser-based design simulator
- CI on Linux and macOS (Apple silicon and Intel); universal DMG/ZIP releases with SHA-256 checksums; optional signing and notarization
