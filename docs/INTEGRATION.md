# How BotPeek talks to Grok Bot

Grok Bot has **no public API, event stream or URL scheme** for third-party apps
(checked against the official docs at docs.x.ai/grok-bot and cursor.com/docs/grok-bot
in October 2026). BotPeek therefore combines two local techniques that community
projects have already proven, and keeps each behind an interface so it can be
swapped for an official API if one appears.

| Need | Technique | Source of the technique | Status |
| --- | --- | --- | --- |
| Discover bots, names, ids | Read Grok Bot's roster cache (read-only) | djui/grokbot, grokbot-widget | Proven by others; **not yet verified by BotPeek on a real Mac** |
| Built-in avatar shape/color | `avatarShape`, `avatarColor` roster fields | djui/grokbot | Same |
| Uploaded avatar | `avatarPhoto.key` → `roster-avatars/<key>` | grokbot-widget | Same |
| Needs-attention signal | `awaitingUserResponse` roster field | djui/grokbot | Same |
| Secondary attention signal | Sidebar label "…, Waiting for you" via Accessibility | djui/grokbot | Same |
| Read question & choices | Accessibility tree of Grok Bot's window | grok-bot-mcp | Same |
| Answer a multiple-choice question | Press the choice button via Accessibility | grok-bot-mcp | Same |
| Send a text reply | Focus "Prompt", paste, Return; restore clipboard | grok-bot-mcp | Same |
| Approve / deny | Press the exact approve/deny button, after explicit confirmation | BotPeek | Off by default; unverified |

> **Verification status:** BotPeek was developed without access to a Mac. The parsing
> and decision logic is covered by automated tests that run in CI on Linux and macOS,
> but **no part of the live Grok Bot integration has been tested end-to-end yet.**
> See [BETA_TESTING.md](BETA_TESTING.md) to help verify it.

## Local data (read-only)

Location: `~/Library/Application Support/Grok Bot/`

- `sand-client-persistence/*.blob` — a key-value cache. Each file name is the
  base32 (RFC 4648, lowercase, no padding) encoding of its key. The roster is the
  newest file whose key ends in `.roster.last-roster` (the prefix identifies the
  account). Contents (schema 4):

  ```json
  { "schemaVersion": 4,
    "value": { "rows": [
      { "id": "…", "name": "Research Bot", "description": "…",
        "avatarShape": "cloud", "avatarColor": "blue",
        "avatarPhoto": { "kind": "file", "key": "<32 hex chars>" },
        "awaitingUserResponse": { … } | null,
        "hasUnread": false, "unreadCount": 0,
        "lastActivityAt": 1730000000000, "isHiddenFromSidebar": false } ] } }
  ```

- `roster-avatars/<key>` — uploaded profile images.
- `desktop-status.json` — `{ "pid", "signedIn", "appVersion" }` written by the
  running app. BotPeek trusts it only if that process is alive.

BotPeek never writes to this folder, never reads anything else in it, and never
reads credentials. Avatar keys are validated as 32 hex characters so a malformed
roster can't point BotPeek at another file.

**Unknowns:** the structure of the `awaitingUserResponse` payload has not been
published. `AwaitingRequestParser` looks for common fields (`question`, `prompt`,
`message`, `options`, `choices`, `type`…) and falls back to "the bot is waiting"
plus reading the question from the conversation. Beta testers' `--check` output
(which contains no message text) tells us whether payloads are readable.

## Accessibility (Grok Bot's window)

Grok Bot (bundle id `com.anysphere.sand`) is an Electron app. Chromium only
exposes its web content to Accessibility after `AXManualAccessibility` is set on
the app element; BotPeek sets it once per Grok Bot process.

Landmarks used (from grok-bot-mcp):

- Sidebar: element whose description/title is `Bots`; each bot is an `AXButton`
  labelled `<name>` or `<name>, <status>`.
- Open conversation: the first `AXHeading` is the bot's name.
- Transcript: element described as `Conversation transcript`; each message is a
  group titled `<sender> <h:mm:ss AM>` (sender `You` for the user).
- Open question: a group containing a `Dismiss question` button; the other
  buttons in that group are the choices.
- Composer: `AXTextArea` described as `Prompt`.

### Safety rules BotPeek adds

- **Exact identity matching.** A bot is matched to its sidebar button only by exact
  name; duplicate names or no match → BotPeek refuses and offers "Open in Grok Bot".
  No prefix or fuzzy matching (grok-bot-mcp allows it; BotPeek does not).
- **Heading check.** Before acting, the opened conversation's heading must equal the
  bot's name; otherwise nothing is sent.
- **Never creates bots or conversations.** BotPeek only presses existing sidebar
  buttons and never uses "New chat".
- **Draft protection.** If Grok Bot's message box already contains text, BotPeek
  refuses to paste rather than overwrite the user's draft.
- **Keystrokes only when Grok Bot is frontmost**, checked right before typing.
- **Clipboard and focus restored.** Every pasteboard item/type is restored and the
  previously active app is re-activated.
- **No silent retries after an action reached Grok Bot.** If delivery can't be
  confirmed, BotPeek says so and points to Grok Bot instead of sending twice.
- **"Delivered" only after verification**: a new `You` message containing the reply
  appears, or the answered question disappears.

### Disruption

- Pressing a choice button works without bringing Grok Bot forward, but it does
  switch Grok Bot's visible conversation to that bot.
- Text replies briefly bring Grok Bot forward (about a second) to paste, then
  return to the previous app. An experimental "background" method sets the text
  through Accessibility and presses Send without activating Grok Bot; it is off by
  default because it is unverified.

## Options evaluated and not used

- **Cursor BDK `cursor-grokbot-agents` extension** (`@cursor/bdk` ≤ 0.2.x): provided
  `ask`, `check`, `list`, `interrupt` against an existing bot. Not used because it
  requires a bundled Node.js runtime and browser sign-in, its license is proprietary
  ("Cursor SDK License"), it has no event feed for "needs attention", it cannot press
  multiple-choice buttons, a mistyped bot name can create a new bot, and the extension
  is no longer present in BDK 0.4.0 (October 2026).
- **Grok Bot MCP server** (grok-bot-mcp): its techniques are reused natively in Swift
  instead of shipping Node.js and `osascript`.
- **Private network endpoints**: never used. BotPeek makes no network requests at all.

## When Grok Bot changes

All Grok Bot-specific strings live in `GrokBotApp`, `RosterParser`, `SidebarParser`
and `TranscriptParser`. A Grok Bot update that renames a label or changes the cache
shows up as: Settings → Connection warnings ("data format changed"), `--check`
output, and "Couldn't find…" errors with an "Open in Grok Bot" fallback. Nothing
fails silently and nothing is sent to the wrong place.
