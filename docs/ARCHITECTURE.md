# Architecture

```
Sources/
  BotPeekCore/   Foundation-only logic, covered by the tests
    Grok/          reading Grok Bot's data and Accessibility tree
    Attention/     detecting, deduplicating and queueing requests
    Reply/         routing and validating replies
    Presentation/  placement and animation plans
    Settings/, Model/, Demo/, Diagnostics/
  BotPeek/       the macOS app (AppKit + SwiftUI)
    Grok/          live integration and Accessibility driver
    Character/     floating panel, character and speech bubble
    Avatar/        avatar rendering
    App/           app model, menu bar, settings, onboarding
```

```
Grok Bot data ─> AttentionDetector ─> AttentionEventManager ─> AppModel ─> CharacterWindowManager
                                                                  ▲               │
                                    ReplyService <─ ReplyCoordinator <── SpeechBubble
```

## Key decisions

- **Attention comes from Grok Bot's data,** never from unread counts or text heuristics
  alone. A signal must persist for 0.5 s before a character appears.
- **Incomplete reads never resolve a request,** so a file mid-write can't hide a question.
- **Requests are deduplicated by fingerprint;** dismissed ones are remembered as hashes.
- **One active character, newest first.** Others wait in a stack along the edge.
- **The panel never activates BotPeek.** It's a non-activating `NSPanel` that takes key
  focus only while you type, and ignores the mouse outside the character and bubble.
