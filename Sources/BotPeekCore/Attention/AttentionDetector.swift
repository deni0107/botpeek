import Foundation

/// Decides which bots genuinely need the user.
///
/// Signals, strongest first:
/// 1. The roster's `awaitingUserResponse` field is set. This is the field
///    Grok Bot itself uses to mark a bot as blocked on the user.
/// 2. The bot's cached conversation ends with an unanswered question, approval
///    or form (`ConversationRequestParser`). Grok Bot 0.78 records questions
///    asked in chat only here.
/// 3. Optionally, the bot's sidebar label says it is waiting for the user
///    (read through Accessibility). Used only when neither of the above has
///    anything, e.g. while the caches have not been rewritten yet.
///
/// Never a trigger: unread messages, unread counts, working/progress states,
/// finished tasks, or questions the user has already answered or moved past.
public enum AttentionDetector {
    public static func snapshot(
        roster: [Bot],
        conversations: [BotID: ConversationRequestParser.OpenRequest] = [:],
        sidebar: [SidebarEntry]?,
        observedAt: Date,
        isComplete: Bool = true
    ) -> StatusSnapshot {
        let visible = roster.filter { !$0.isHiddenFromSidebar }
        let identities = visible.map(\.identity)
        var observations: [AttentionObservation] = []

        for bot in visible {
            if let payload = bot.awaitingUserResponse, !payload.isEmptySignal {
                observations.append(AttentionObservation(
                    bot: bot.identity,
                    fingerprint: "r:" + AwaitingRequestParser.fingerprint(of: payload),
                    content: AwaitingRequestParser.parse(payload),
                    source: .roster
                ))
                continue
            }
            if let open = conversations[bot.id] {
                observations.append(AttentionObservation(
                    bot: bot.identity,
                    fingerprint: "c:" + open.fingerprint,
                    content: open.content,
                    source: .conversation
                ))
                continue
            }
            guard let sidebar,
                  case .unique(let entry) = BotIdentityMatcher.match(bot: bot.identity, roster: identities, sidebar: sidebar),
                  let status = SidebarParser.statusText(of: entry, botName: bot.name),
                  SidebarParser.statusIndicatesAttention(status)
            else { continue }
            observations.append(AttentionObservation(
                bot: bot.identity,
                fingerprint: "a:" + StableHash.fnv1a(status.lowercased()),
                content: .opaque,
                source: .accessibility
            ))
        }
        return StatusSnapshot(observedAt: observedAt, bots: identities, attention: observations, isComplete: isComplete)
    }
}
