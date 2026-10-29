# Architecture

```
Sources/
  BotPeekCore/            Platform-independent logic (Foundation only). Tested on Linux + macOS.
    Model/                Bot, BotIdentity, AvatarDescriptor, AttentionContent, JSONValue
    Grok/                 GrokBotPaths, RosterParser/Store, AsarArchive, GrokAvatarScript, AwaitingRequestParser,
                          AXNodeSnapshot + SidebarParser + BotIdentityMatcher,
                          TranscriptParser + DeliveryVerifier, Integration protocols
    Attention/            AttentionDetector, AttentionEventManager, RequestQueue
    Reply/                Reply types, ReplyService protocol, ReplyCoordinator
    Presentation/         PanelPlacement, AnimationPlan, CharacterStateMachine
    Settings/             BotPeekSettings, SettingsStore, PersistentDismissedStore
    Demo/                 DemoIntegration (clearly labelled sample bots)
    Diagnostics/          DiagnosticsLog (privacy-preserving)
  BotPeek/                The macOS app (AppKit + SwiftUI), guarded by #if canImport(AppKit)
    Grok/                 AXTree, GrokAccessibilityDriver, LiveGrokIntegration
    Avatar/               GrokAvatarRenderer (Grok Bot's own artwork), AvatarSilhouette fallback, BotAvatarView
    Character/            CharacterPanel, CharacterWindowManager, StageModel, views
    App/                  AppModel, AppDelegate, StatusItemController, Settings, Onboarding
```

## The components named in the brief

| Component | Where |
| --- | --- |
| `BotDiscoveryService` | protocol in `Integration.swift`; roster via `RosterStore` |
| `BotStatusMonitor` | protocol; `LiveGrokIntegration.currentSnapshot` + `AttentionDetector` |
| `AvatarProvider` | protocol; `AvatarResolver` + `BotAvatarView` |
| `AttentionEventManager` | `Attention/AttentionEventManager.swift` |
| `ConversationProvider` | protocol; `GrokAccessibilityDriver` + `TranscriptParser` |
| `ReplyService` | protocol; `GrokReplyService`, `DemoIntegration` |
| `CharacterWindowManager` | `Character/CharacterWindowManager.swift` |
| `AnimationCoordinator` | same file; plans from `AnimationPlan` |
| `PreferencesManager` | `SettingsStore` + `AppModel.settings` |

## Data flow

```
Grok Bot roster file ─┐                     ┌─> StatusSnapshot ─> AttentionEventManager
Grok Bot sidebar (AX) ┴─> AttentionDetector ┘        (confirm, dedupe, queue, resolve)
                                                                │ events
                                                                ▼
                         AppModel ── presentable queue ──> CharacterWindowManager
                            ▲                                   │ StageModel → SwiftUI
                            │ DeliveryState                     ▼
                     ReplyCoordinator <── Reply ── SpeechBubble (choices / text / approval)
                            │ validated, routed by BotID
                            ▼
                     ReplyService (GrokAccessibilityDriver: exact match → heading check → act → verify)
```

## Key decisions

- **Attention comes from Grok Bot's own `awaitingUserResponse` flag**, not from text
  heuristics. Unread counts and "working" labels are never triggers.
- **A signal must persist** (0.5 s, i.e. two reads) before a character appears, and
  nothing new appears or disappears for 8 s after wake.
- **Incomplete reads never resolve requests**, so a missing file mid-write can't hide a
  real question.
- **Deduplication by fingerprint** of the request's identity and readable content (not
  timestamps). Dismissed fingerprints are remembered as hashes across restarts.
- **One character at a time.** Switching between bots exits and re-enters; a new
  question from the same bot swaps the bubble in place.
- **The panel never activates BotPeek.** It's a non-activating `NSPanel` at floating
  level on all Spaces; it becomes key only while typing, then focus is handed back.
- **Click-through**: SwiftUI reports the character and bubble frames; the panel
  ignores the mouse everywhere else.
- **Swift 5 language mode** keeps the AppKit code simple to build on CI; core logic
  is concurrency-safe by construction (main-actor coordinator, value types).
