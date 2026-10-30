# Contributing

BotPeek is a spare-time project, provided as is. Issues and pull requests are welcome,
but there's no promise of a reply or a fix. Every pull request is reviewed before merging.

## Development

```bash
swift test          # run the tests
swift run BotPeek   # run the app
```

macOS resets the Accessibility permission on every ad-hoc-signed rebuild. To keep it,
sign with a certificate from your keychain:

```bash
DEVELOPER_ID_APPLICATION="Apple Development: Your Name (TEAMID)" ./scripts/build-app.sh
```

## Guidelines

- Keep `BotPeekCore` free of AppKit and SwiftUI, and put tested logic there.
- Keep Grok Bot-specific assumptions in the `Grok/` parsers, with a test.
- No network calls, analytics or stored message text. Logs never contain bot names or
  message content.
- Never show *Delivered* without confirming the reply, and never guess which bot to reply to.
- Only add code under an MIT-compatible license, credited in THIRD_PARTY_NOTICES.md.
