# Contributing to BotPeek

BotPeek is small and focused: little characters that appear only when a Grok Bot bot
needs you, and disappear once you've helped.

It is a spare-time project, provided as is. Issues and pull requests are welcome, but
there's no promise of a reply, a fix or a release schedule. The surest way to get
something fixed is to open a pull request. Every pull request is reviewed by the
maintainer before it is merged.

## Ideas for contributions

- **Avatar accuracy:** BotPeek draws built-in avatars with Grok Bot's own renderer and
  falls back to its own drawings (`Sources/BotPeek/Avatar/AvatarShapes.swift`).
  Screenshots of a wrong or fallback avatar next to Grok Bot's help us fix both.
- **Grok Bot updates:** a Grok Bot release can break detection or replies. `BotPeek --check`
  shows what changed; include its output and your Grok Bot version in an issue or PR.

## Development

```bash
swift test                 # core tests + app build
swift run BotPeek          # run the menu bar app from source
```

macOS ties the Accessibility permission to an ad-hoc-signed app's exact build, so
every rebuild needs it granted again. Sign with any certificate in your keychain
(`security find-identity -v -p codesigning`) and the permission survives rebuilds:

```bash
DEVELOPER_ID_APPLICATION="Apple Development: Your Name (TEAMID)" ./scripts/build-app.sh
```

- `BotPeekCore` must stay Foundation-only, free of AppKit and SwiftUI. Put decisions there
  and test them; keep `Sources/BotPeek` (AppKit/SwiftUI) thin.
- Every Grok Bot-specific assumption belongs in `GrokBotApp`, `RosterParser`,
  `SidebarParser`, `TranscriptParser` or `ConversationRequestParser`, with a test and a note in docs/INTEGRATION.md.
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
2. Add or update tests; `swift test` must pass. CI runs on macOS (Apple silicon and Intel).
3. Describe what you verified, and on what (Mac model, macOS, Grok Bot version), in the PR template.
