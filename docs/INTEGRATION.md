# How BotPeek talks to Grok Bot

Grok Bot has **no public API, event stream or URL scheme** for third-party apps
(checked against the official docs at docs.x.ai/grok-bot and cursor.com/docs/grok-bot
in October 2026). BotPeek therefore combines two local techniques that community
projects have already proven, and keeps each behind an interface so it can be
swapped for an official API if one appears.

| Need | Technique | Source of the technique | Status |
| --- | --- | --- | --- |
| Discover bots, names, ids | Read Grok Bot's roster cache (read-only) | djui/grokbot, grokbot-widget | **Verified** with Grok Bot 0.78.1 |
| Built-in avatar shape/color | `avatarShape`, `avatarColor` roster fields | djui/grokbot | **Verified** with Grok Bot 0.78.1 |
| Uploaded avatar | `avatarPhoto.key` → `roster-avatars/<key>` | grokbot-widget | Proven by others; **not yet verified by BotPeek on a real Mac** |
| Needs-attention signal | `awaitingUserResponse` roster field | djui/grokbot | Same; not set by Grok Bot 0.78.1 for questions asked in chat |
| Open questions, approvals, forms | Latest entry of the bot's cached conversation (read-only) | BotPeek | **Verified** detection with Grok Bot 0.78.1 |
| Secondary attention signal | Sidebar label "…, Waiting for you" via Accessibility | djui/grokbot | Same |
| Read question & choices | Accessibility tree of Grok Bot's window | grok-bot-mcp | Same |
| Answer a multiple-choice question | Press the choice button via Accessibility, nudging until it is sent | grok-bot-mcp | **Verified** in the background with Grok Bot 0.78.1 |
| Send a text reply | Set "Prompt"'s text via Accessibility, press "Send message" (fallback: focus, paste, Return; restore clipboard) | BotPeek (fallback: grok-bot-mcp) | **Verified** in the background with Grok Bot 0.78.1 |
| Approve / deny | Press the exact approve/deny button, after explicit confirmation | BotPeek | Off by default; **verified** for Approve/Deny answer buttons with Grok Bot 0.78.1 |

> **Verification status:** The parsing and decision logic is covered by automated tests
> that run in CI on Linux and macOS. On a real Mac with Grok Bot 0.78.1, bot discovery,
> built-in avatars, detecting questions asked with answer buttons, choice and typed
> replies in the background, and inline approvals of Approve/Deny buttons are verified
> end-to-end. **Plain-text questions, uploaded avatars and other Grok Bot versions still
> need testers.** See [BETA_TESTING.md](BETA_TESTING.md) to help verify them.

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

- Conversations: the file whose key is `<account>.transcript.replicas.<bot id>`,
  for the same account as the roster. BotPeek reads it only to see whether the
  conversation's latest entry is a request still waiting for you:

  ```json
  { "schemaVersion": 1, "value": { "entries": [ …,
    { "kind": "send-message", "id": "t3s0", "timestampMs": 1730000000000,
      "message": { "type": "widget", "widget": { "prompt": "…",
        "options": [ { "label": "…", "value": "…" } ],
        "allowCustom": true, "multiSelect": false } } } ] } }
  ```

  A question is answered once Grok Bot adds `respondedValue`, `widgetSkipped` or
  `widgetDismissed` to it, or once anyone moves the conversation on (you write,
  or the bot posts again; messages between bots don't count). `auto-review-approval`
  entries are open while their `status` is pending; `user-form` entries until they
  get a `formResolution`. Approvals and forms are answered in Grok Bot only, so
  passwords and codes never pass through BotPeek. Single-choice questions show
  their options as buttons; multi-select ones as checkboxes, sent together as one
  typed reply ("Mon, Tue"); multi-step ones list the options and take a typed answer.

  Bots also ask in ordinary messages (`"message": { "type": "text", "content": "…" }`),
  which Grok Bot doesn't mark as waiting. BotPeek treats such a message as a
  question when it is the latest turn, its last sentence ends in "?" and it isn't a
  sign-off ("Anything else?"), and only after the bot has been quiet for 8 seconds,
  so a bot that keeps talking doesn't pop up. Settings → General can turn this off.
  Message text stays in memory and is never written anywhere.
- `roster-avatars/<key>` — uploaded profile images.
- `desktop-status.json` — `{ "pid", "signedIn", "appVersion" }` written by the
  running app. BotPeek trusts it only if that process is alive.

BotPeek never writes to this folder, never reads anything else in it, and never
reads credentials.

### Built-in avatar artwork

Grok Bot has no image files for its built-in avatars: its renderer turns a shape
name, pose, eyes and palette into an SVG in JavaScript. At launch BotPeek:

1. Finds Grok Bot (`com.anysphere.sand`) and checks its code signature
   (`anchor apple generic` + bundle ID). The signature also seals `app.asar`.
2. Reads `Contents/Resources/app.asar`'s index and the renderer module under
   `dist/renderer/assets/` (`AsarArchive`). Nothing is extracted to disk.
3. Rewrites that ES module and its bundler runtime into one classic script
   (`GrokAvatarScript`). Minified names change per release, so the renderer, the
   shape-alias function (`blob` → `sphere`) and the gradient table are found by
   the shape of their code.
4. Runs it in a bare JavaScriptCore context (no DOM, files or network), renders
   two avatars as a self-test, then caches one `NSImage` per shape and color.

If any step fails, BotPeek draws its own avatars and Settings → Connection says
why. Verified against Grok Bot 0.78.1. `BotPeek --render-avatars <folder>` writes
every shape and each roster bot's avatar as PNGs for a quick visual check. Avatar keys are validated as 32 hex characters so a malformed
roster can't point BotPeek at another file.

**Unknowns:** Grok Bot 0.78.1 leaves `awaitingUserResponse` empty even while a bot
waits on a question, so BotPeek relies on the conversation cache above. The
payload's structure, for versions that do set it, has not been published. `AwaitingRequestParser` looks for common fields (`question`, `prompt`,
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
  buttons in that group are the choices. Grok Bot 0.78.1 has no dismiss button:
  the choices are buttons directly inside a group described with the question
  text, often next to a `Custom answer` text area. BotPeek reads that form only
  from the newest message, because older unanswered questions keep working
  buttons after the bot has moved on.
- Pressing: while Grok Bot is in the background, 0.78.1 acts on a pressed button
  only when the next Accessibility action arrives, so a sidebar press would open
  the previously pressed bot. BotPeek follows every press, 100 ms later, with a
  harmless `AXScrollToVisible` on the same element to make it take effect. The
  same goes for the work a press starts: Grok Bot shows an answer at once
  ("Your answer") but sends it only while Accessibility actions keep arriving,
  so BotPeek keeps nudging the message box until it sees the reply in the
  conversation, and for two seconds after. Grok Bot also writes its caches less
  often in the background, so a new question can take a minute or two to show
  up while Grok Bot is hidden.
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
- Text replies are sent in the background by default: BotPeek sets the message
  box's text through Accessibility, waits for Grok Bot's `Send message` button
  (it appears only once there is text), and presses it. If Grok Bot ignores the
  text, BotPeek clears the box and says so; Settings → Advanced → Reply delivery
  can switch to pasting, which brings Grok Bot forward for about a second and then
  returns to the previous app.

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
