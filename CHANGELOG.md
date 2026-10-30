# Changelog

## 0.1.0 — unreleased (beta)

First public beta. Bot discovery, avatars, question detection, answers (choices, multi-select
and typed replies) and inline approvals are checked on a real Mac with Grok Bot 0.78.1.

### Bots and avatars

- Discovers Grok Bot bots, names and avatars (built-in shapes and colors, uploaded images) from Grok Bot's local data, read-only
- Draws built-in avatars with Grok Bot's own renderer, loaded from the signed, installed Grok Bot at launch; BotPeek's drawings are the fallback. All 26 Grok Bot shapes (incl. `pumpkin`, `leaf`, `shield`…) and its 11 colors and gradients (incl. `violet`, `magenta`) are recognized

### Detecting requests

- Shows a character only when a bot is waiting for the user; never for unread, progress or finished states
- Detects questions, approvals and forms from Grok Bot's cached conversations as well as the roster's `awaitingUserResponse` field (which Grok Bot 0.78.1 doesn't set for questions asked in chat), with an optional sidebar signal
- Shows questions bots ask in plain text once the bot has been quiet for a few seconds; sign-offs like "Anything else?" don't count. Settings → General can turn this off
- A question appears about 0.1 s after Grok Bot saves it
- Confirmation delay, fingerprint deduplication, wake grace period, and resolution when answered elsewhere

### Answering

- Speech bubble with multiple-choice answers, multi-select checkboxes, free-text replies, opt-in two-step inline approvals and "Open in Grok Bot"
- Typed replies and answer buttons are delivered through Accessibility in the background, without bringing Grok Bot forward; pasting is the fallback in Settings
- *Delivered* is shown only after BotPeek sees the reply in the right conversation, usually within about a second
- Exact bot matching, heading checks and draft protection; never replies to an open conversation when another bot has the same name
- Sign-in forms and approvals open in Grok Bot, which snoozes the character until Grok Bot marks them done

### Characters and queue

- Queue for several bots, newest first, with the others peeking out in a stack beside the active character (hover for name and wait time, click to switch); snooze, dismiss, menu-bar list with wait times
- Bubble tucks away after 30 s idle, gentle reminder wiggles, quick snooze/dismiss on hover
- Long questions and option labels scroll inside the bubble
- Drag the character along the edge; it follows the pointer to another display
- Right, bottom or left edge; multiple displays, Spaces and full screen; sizes; lively/subtle/minimal animation; Reduce Motion
- Pause characters from the menu bar; hide from screenshots and screen sharing (best effort)

### Keyboard and accessibility

- ⌃⌥B global shortcut, 1–9 for answers, ⌘[ ⌘] ⌘L ⌘D ⌘O in the bubble; closing the bubble gives the keyboard back to the app you were using
- VoiceOver, Voice Control and Switch Control can open a request from the character and switch to waiting bots

### App and tooling

- Settings, first-run onboarding, Accessibility diagnostics and privacy-preserving diagnostics export
- Demo mode with clearly labelled sample bots and its own queue, separate from your real requests
- `--version`, `--check`, `--probe-open <bot log tag>` and `--render-avatars <folder>` for troubleshooting
- Browser-based design simulator
- CI on macOS (Apple silicon and Intel); universal DMG/ZIP releases with SHA-256 checksums; optional signing and notarization
