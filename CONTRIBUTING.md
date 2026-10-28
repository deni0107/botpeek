# Contributing to BotPeek

Thanks for helping! BotPeek is small and focused: little characters that appear only
when a Grok Bot bot needs you, and disappear once you've helped.

## Ways to help

- **Beta testing on a Mac** is the most valuable contribution right now. See
  [docs/BETA_TESTING.md](docs/BETA_TESTING.md).
- **Avatar accuracy:** screenshots comparing a Grok Bot avatar with BotPeek's drawing
  (`Sources/BotPeek/Avatar/AvatarShapes.swift`) help us match the built-in shapes.
- **Grok Bot updates:** if a Grok Bot release breaks detection or replies, open an issue
  with `BotPeek --check` output and your Grok Bot version.

## Development

```bash
swift test                 # core + app build; works on macOS
swift run BotPeek          # run the menu bar app from source (macOS)
```

Without a Mac you can run the core tests in Docker:

```bash
docker run --rm -v "$PWD:/src" -w /src swift:6.0-jammy swift test
```

- `BotPeekCore` must stay Foundation-only so it builds on Linux. Put decisions there
  and test them; keep `Sources/BotPeek` (AppKit/SwiftUI) thin.
- Every Grok Bot-specific assumption belongs in `GrokBotApp`, `RosterParser`,
  `SidebarParser` or `TranscriptParser`, with a test and a note in docs/INTEGRATION.md.
- Match the surrounding style: small types, clear names, comments that explain *why*.

## Ground rules

- **Privacy:** no analytics, telemetry, network calls or storage of message text. Logs
  use `BotID.logTag`, never names or content.
- **Honesty:** never show "Sent"/"Delivered" without verification; never claim support for
  something that isn't verified. Fall back to "Open in Grok Bot".
- **Safety:** never write to Grok Bot's files, read credentials, call private endpoints,
  create bots or conversations, or guess which bot to reply to.
- **Licensing:** only add code under an MIT-compatible license, with attribution in
  THIRD_PARTY_NOTICES.md. No third-party artwork.

## Pull requests

1. Fork, branch from `main`, and keep the change focused.
2. Add or update tests; `swift test` must pass. CI runs on Linux and macOS (Apple silicon and Intel).
3. Describe what you verified, and on what (Mac model, macOS, Grok Bot version), in the PR template.
