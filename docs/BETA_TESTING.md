# Beta testing BotPeek

BotPeek's bot discovery, avatars, question detection, answers (choices, multi-select and
typed replies) and inline approvals have been checked on one Mac (macOS 26, Grok Bot
0.78.1). Plain-text questions, animations, and other macOS and Grok Bot versions **need
volunteers to verify them**. Thank you for helping!

You need: a Mac with macOS 14 (Sonoma) or newer, and ideally the Grok Bot desktop
app signed in with at least one bot. Without Grok Bot you can still test the UI in
demo mode.

## 1. Install

1. Download the latest `.dmg` from [Releases](https://github.com/DenisDule/botpeek/releases).
2. Optional: verify the checksum in Terminal: `shasum -a 256 ~/Downloads/BotPeek-*.dmg`
   and compare with the release notes.
3. Open the DMG and drag **BotPeek** into **Applications**.
4. Open BotPeek from Applications. Beta builds are not notarized, so macOS may say
   it can't verify the developer. Click **Done**, then open **System Settings →
   Privacy & Security**, scroll down and click **Open Anyway** next to BotPeek.
   Please don't disable Gatekeeper globally.

## 2. Test plan

Mark each item ✅ / ❌ / ➖ (not tested) in your report.

### A. Demo mode (no Grok Bot needed)
- [ ] Menu bar → **Demo Mode**. After ~2 s "Research Bot" peeks out with a **DEMO** badge.
- [ ] The rest of the screen stays clickable around the character (click-through).
- [ ] Click the character → choices appear; pick one → "Delivered", a little celebration, it leaves.
- [ ] Travel Planner: type a reply, press Return. Then try a reply containing `#fail` → a clear error.
- [ ] Ops Bot: approval opens in Grok Bot by default. Turn on Settings → General →
      "Approve or deny inline", replay the demo, check the two-step confirmation.
- [ ] With several waiting, the "1 of 3" switcher works; **Later → Snooze / Dismiss** work;
      dismissed items stay in the menu bar list.
- [ ] Writer and Inbox Bot (unread updates) **never** pop up.
- [ ] Settings → Appearance: each edge (right/bottom/left), sizes, animation levels, reduce motion.
- [ ] System Settings → Accessibility → Display → Reduce motion: characters fade instead of sliding.
- [ ] Light and dark mode; a second display; a full-screen app; switching Spaces.
- [ ] While typing a reply in BotPeek, the app you were using stays in front, and focus returns after.

### B. Real Grok Bot (most valuable)
- [ ] Settings → Connection shows Grok Bot installed/running/signed in and the right bot count.
- [ ] Avatars match Grok Bot: built-in shapes and colors, uploaded photos, transparent images.
      **Please attach a screenshot comparing both** — the built-in shapes are BotPeek's own
      drawings and we need your help to make them match.
- [ ] Ask a bot something that makes it ask you a question, both with answer buttons and
      in a plain message ("ask me in plain text…"). Does the character appear?
      How long after Grok Bot shows it?
- [ ] Ordinary progress, finished tasks and unread messages do **not** trigger a character.
- [ ] Grant Accessibility (Settings → Connection → Grant Access). Does the bubble show the
      real question text and choices?
- [ ] Answer a multiple-choice question from BotPeek. Did the right bot get the right answer?
- [ ] Send a free-text reply. Did it land in the right conversation? Was your clipboard restored?
      Did focus return to your previous app?
- [ ] Answer a question directly in Grok Bot instead: the character should leave by itself.
- [ ] Two bots waiting at once: correct names/avatars/questions for each.
- [ ] Put the Mac to sleep with a question pending, wake it: no duplicate or stale popups.
- [ ] Quit and reopen Grok Bot; quit and reopen BotPeek.

## 3. Capture diagnostics

Diagnostics contain events, error codes and counts — **never message text or bot names**.

- **In the app:** menu bar icon → **Export Diagnostics…** and attach the file.
- **Status check in Terminal:**

  ```bash
  /Applications/BotPeek.app/Contents/MacOS/BotPeek --check
  ```

- **System log** (more detail, last 30 minutes):

  ```bash
  log show --last 30m --predicate 'subsystem == "io.github.denisdule.botpeek"' --info --debug
  ```

Please also include your macOS version, Mac model (Apple silicon or Intel) and Grok Bot
version (Grok Bot → About).

## 4. Report

Open a [Beta test report](https://github.com/DenisDule/botpeek/issues/new?template=beta_report.yml).
Check screenshots for private information (bot names, message text) before attaching.
Report security problems privately as described in [SECURITY.md](../SECURITY.md).

## Known limitations of beta builds

- Not notarized, so macOS asks for confirmation on first launch.
- Ad-hoc signed: after each update macOS treats BotPeek as a new app, so you need to
  turn Accessibility on again (remove the old BotPeek entry with "–" first).
- Built-in avatar shapes are approximations drawn by BotPeek from the shape name.
- English-language Grok Bot UI assumed for reading the conversation (sender "You").
