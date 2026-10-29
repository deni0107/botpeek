#if canImport(AppKit)
import SwiftUI
import BotPeekCore

struct SpeechBubble: View {
    @ObservedObject var model: StageModel
    static let width: CGFloat = 312
    /// Room the panel leaves for the bubble; longer requests scroll inside it.
    static let maxHeight: CGFloat = 400

    var body: some View {
        let shape = BubbleShape(tail: model.bubbleTail, tailNearTop: model.growsDown)
        VStack(alignment: .leading, spacing: 10) {
            BubbleHeader(model: model)
            if let request = model.request {
                // The question and the answers scroll together when they don't
                // fit, so nothing is squeezed or cut off at the panel's edge.
                ScrollingContent {
                    VStack(alignment: .leading, spacing: 10) {
                        PromptText(text: request.content.displayPrompt, isExpanded: model.isExpanded)
                            .id(request.id)
                        if model.isExpanded {
                            // A fresh reply area per request: a draft never carries over to another bot.
                            ReplyArea(model: model, request: request)
                                .id(request.id)
                                .transition(.opacity)
                        } else {
                            Text(collapsedHint(for: request))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                DeliveryStatusView(model: model)
                if model.isExpanded {
                    BubbleFooter(model: model, request: request)
                }
            }
        }
        .background {
            if model.isExpanded { BubbleShortcuts(model: model) }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .padding(edgeInsetsForTail)
        .frame(width: Self.width, alignment: .leading)
        .background(
            VisualEffectBackground(material: .popover)
                .clipShape(shape)
        )
        .overlay(shape.stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
        .contentShape(shape)
        .onTapGesture {
            if !model.isExpanded { model.actions?.expand() }
        }
        .onHover { model.isHoveringBubble = $0 }
        .interactiveRegion()
        .animation(model.reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: model.isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Request from \(model.botName)")
        .accessibilityAction(named: "Snooze for \(model.snoozeMinutes) minutes") { model.actions?.snooze() }
        .accessibilityAction(named: "Dismiss") { model.actions?.dismiss() }
    }

    private var edgeInsetsForTail: EdgeInsets {
        let t = BubbleShape.tailSize
        switch model.bubbleTail {
        case .trailing: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: t)
        case .leading: return EdgeInsets(top: 0, leading: t, bottom: 0, trailing: 0)
        case .bottom: return EdgeInsets(top: 0, leading: 0, bottom: t, trailing: 0)
        }
    }

    private func collapsedHint(for request: AttentionRequest) -> String {
        let hint: String
        if request.content.grokBotOnlyReason != nil || model.replyUnavailableReason != nil {
            // Nothing can be answered here; don't promise a reply.
            hint = "Click for details"
        } else {
            switch request.content.kind {
            case .choice: hint = request.content.allowsMultipleChoices ? "Click to choose answers" : "Click to choose an answer"
            case .approval: hint = "Click to review"
            default: hint = "Click to reply"
            }
        }
        return model.shortcutHint.map { "\(hint) or press \($0)" } ?? hint
    }
}

/// Shows its content at its natural height, and scrolls once that is taller
/// than the space the bubble has left.
private struct ScrollingContent<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat?

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                })
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.automatic)
        .frame(maxHeight: contentHeight ?? .infinity)
        // Header, status and footer get their room first.
        .layoutPriority(-1)
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A small icon button with a comfortable click target.
private struct IconButton: View {
    let systemName: String
    let help: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(label)
    }
}

private struct BubbleHeader: View {
    @ObservedObject var model: StageModel

    var body: some View {
        HStack(spacing: 6) {
            Text(model.botName)
                .font(.system(.headline, design: .rounded))
                .lineLimit(1)
            if let since = model.request?.firstSeen {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(WaitTime.describe(since: since, now: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityLabel("Waiting \(WaitTime.describe(since: since, now: context.date))")
                }
            }
            if model.isDemo {
                Text("DEMO")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.9)))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .accessibilityLabel("Demo mode: sample bot, not your Grok Bot")
            }
            Spacer(minLength: 4)
            if let queue = model.queue, queue.count > 1 {
                HStack(spacing: 0) {
                    IconButton(systemName: "chevron.left", help: "Newer request (⌘[)", label: "Newer request") {
                        model.actions?.showPrevious()
                    }
                    Text("\(queue.index + 1) of \(queue.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    IconButton(systemName: "chevron.right", help: "Older request (⌘])", label: "Older request") {
                        model.actions?.showNext()
                    }
                }
                .controlSize(.small)
            }
            if !model.isExpanded && model.isHoveringBubble {
                // Quick actions without opening the reply.
                HStack(spacing: 0) {
                    IconButton(systemName: "moon.zzz", help: "Snooze for \(model.snoozeMinutes) minutes", label: "Snooze") {
                        model.actions?.snooze()
                    }
                    IconButton(systemName: "xmark", help: "Dismiss (stays in the menu bar)", label: "Dismiss") {
                        model.actions?.dismiss()
                    }
                }
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }
            if model.isExpanded {
                Button { model.actions?.collapse() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Close (the request stays pending)")
                .accessibilityLabel("Close")
            }
        }
        .frame(minHeight: 22)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PromptText: View {
    let text: String
    let isExpanded: Bool
    @State private var showsAll = false
    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .lineLimit(isExpanded ? (showsAll ? nil : 6) : 3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ShownHeightKey.self, value: proxy.size.height)
                })
                // The same text without a line limit, measured but not shown,
                // tells whether anything was cut off.
                .background(alignment: .topLeading) {
                    Text(text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hidden()
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: FullHeightKey.self, value: proxy.size.height)
                        })
                }
                .modifier(SelectableText(isEnabled: isExpanded))
            if isExpanded && (showsAll || fullHeight > shownHeight + 1) {
                Button(showsAll ? "Show less" : "Show full request") { showsAll.toggle() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .font(.system(.body, design: .rounded))
        .onPreferenceChange(ShownHeightKey.self) { shownHeight = $0 }
        .onPreferenceChange(FullHeightKey.self) { fullHeight = $0 }
    }
}

/// Selecting text only once the bubble is open: until then a click opens it.
private struct SelectableText: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled { content.textSelection(.enabled) } else { content }
    }
}

private struct ShownHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct FullHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ReplyArea: View {
    @ObservedObject var model: StageModel
    let request: AttentionRequest

    var body: some View {
        if let reason = request.content.grokBotOnlyReason {
            ReplyUnavailableView(model: model, reason: reason, isSecure: true)
        } else if let reason = model.replyUnavailableReason {
            ReplyUnavailableView(model: model, reason: reason, isSecure: false)
        } else {
            switch request.content.kind {
            case .approval:
                ApprovalView(model: model, request: request)
            case .choice where request.content.allowsMultipleChoices:
                MultiChoiceList(model: model, request: request)
            case .choice:
                ChoiceList(model: model, request: request)
            case .question, .handoff:
                Composer(model: model, placeholder: "Reply to \(request.bot.name)…")
            case .unknown:
                if request.content.source == .none {
                    QuestionLoader(model: model)
                }
                Composer(model: model, placeholder: "Reply to \(request.bot.name)…")
            }
        }
    }
}

/// One answer row: its number key, its label (wrapping as needed), and an
/// optional leading mark for multi-select.
private struct ChoiceRow: View {
    let index: Int
    let choice: AttentionChoice
    var mark: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let mark {
                Image(systemName: mark)
                    .foregroundStyle(mark.hasSuffix(".fill") ? Color.accentColor : .secondary)
            }
            Text("\(index + 1)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(choice.label)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = choice.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct ChoiceList: View {
    @ObservedObject var model: StageModel
    let request: AttentionRequest
    @State private var showsComposer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(request.content.choices.enumerated()), id: \.offset) { index, choice in
                Button {
                    model.actions?.send(.choice(choice))
                } label: {
                    ChoiceRow(index: index, choice: choice)
                }
                .buttonStyle(.plain)
                .disabled(model.delivery == .sending)
                .modifier(NumberKeyShortcut(index: index, isEnabled: !showsComposer))
                .accessibilityLabel("Answer \(choice.label)")
            }
            DifferentAnswer(model: model, showsComposer: $showsComposer)
        }
    }
}

/// "Choose all that apply": pick any number of options, then send them
/// together as one typed reply.
private struct MultiChoiceList: View {
    @ObservedObject var model: StageModel
    let request: AttentionRequest
    @State private var selected = Set<Int>()
    @State private var showsComposer = false

    var body: some View {
        let choices = request.content.choices
        VStack(alignment: .leading, spacing: 6) {
            Text("Choose all that apply")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                let isOn = selected.contains(index)
                Button {
                    if isOn { selected.remove(index) } else { selected.insert(index) }
                } label: {
                    ChoiceRow(index: index, choice: choice, mark: isOn ? "checkmark.square.fill" : "square")
                }
                .buttonStyle(.plain)
                .disabled(model.delivery == .sending)
                .modifier(NumberKeyShortcut(index: index, isEnabled: !showsComposer))
                .accessibilityLabel(choice.label)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
            HStack {
                DifferentAnswer(model: model, showsComposer: $showsComposer)
                Spacer()
                if !showsComposer {
                    Button(selected.isEmpty ? "Send" : "Send \(selected.count) selected") {
                        let labels = choices.indices.filter(selected.contains).map { choices[$0].label }
                        model.actions?.send(.text(labels.joined(separator: ", ")))
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty || model.delivery == .sending)
                }
            }
        }
    }
}

/// "Type a different answer", opening a message box in place.
private struct DifferentAnswer: View {
    @ObservedObject var model: StageModel
    @Binding var showsComposer: Bool

    var body: some View {
        if showsComposer {
            Composer(model: model, placeholder: "Type a different answer…")
        } else {
            Button("Type a different answer") { showsComposer = true }
                .buttonStyle(.link)
                .font(.caption)
        }
    }
}

private struct Composer: View {
    @ObservedObject var model: StageModel
    let placeholder: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit(send)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
                .disabled(model.delivery == .sending)
                .accessibilityLabel(placeholder)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.delivery == .sending)
            .help("Send to \(model.botName)")
            .accessibilityLabel("Send reply")
        }
        .onAppear {
            Task { @MainActor in focused = true }
        }
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, model.delivery != .sending else { return }
        model.actions?.send(.text(trimmed))
    }
}

/// Approvals show exactly what will be approved or denied and need two clicks.
private struct ApprovalView: View {
    @ObservedObject var model: StageModel
    let request: AttentionRequest
    @State private var pending: PendingApproval?

    struct PendingApproval: Equatable {
        var decision: ApprovalDecision
        var option: AttentionChoice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.canApproveInline {
                let approve = request.content.choices.first { ApprovalHeuristics.isApproveLabel($0.label) }
                let deny = request.content.choices.first { ApprovalHeuristics.isDenyLabel($0.label) }
                if let pending {
                    let approving = pending.decision == .approve
                    Text(approving
                         ? "Approve this request from \(request.bot.name)? BotPeek will press “\(pending.option.label)” in Grok Bot."
                         : "Deny this request from \(request.bot.name)? BotPeek will press “\(pending.option.label)” in Grok Bot.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Back") { self.pending = nil }
                        Spacer()
                        Button(approving ? "Confirm Approve" : "Confirm Deny") {
                            model.actions?.send(.approval(pending.decision, option: pending.option))
                            self.pending = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(approving ? Color.accentColor : Color.red)
                        .disabled(model.delivery == .sending)
                    }
                } else if let approve, let deny {
                    HStack {
                        Button(deny.label + "…") { pending = PendingApproval(decision: .deny, option: deny) }
                        Spacer()
                        Button(approve.label + "…") { pending = PendingApproval(decision: .approve, option: approve) }
                            .buttonStyle(.borderedProminent)
                    }
                    if !model.isDemo {
                        Button("Review in Grok Bot") { model.actions?.openInGrokBot() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                } else {
                    reviewInGrokBot
                }
            } else {
                reviewInGrokBot
            }
        }
    }

    @ViewBuilder
    private var reviewInGrokBot: some View {
        if model.isDemo {
            // Nothing to open for a sample bot.
            Label("Approvals normally open in Grok Bot. To try approving here, turn on Settings → General → Approve or deny inline.", systemImage: "checkmark.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Approvals open in Grok Bot so you can review the full details.", systemImage: "checkmark.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Review in Grok Bot") { model.actions?.openInGrokBot() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct QuestionLoader: View {
    @ObservedObject var model: StageModel

    var body: some View {
        HStack(spacing: 8) {
            if model.isLoadingContent {
                ProgressView().controlSize(.small)
                Text("Reading the question from Grok Bot…").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Show the question") { model.actions?.loadQuestion() }
                    .buttonStyle(.link)
                    .font(.caption)
                    .help("Opens this bot's conversation in Grok Bot in the background and reads the question.")
                if let error = model.contentError {
                    Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }
}

/// Requests that can only be handled in Grok Bot: secure forms (`isSecure`),
/// or any reply while BotPeek can't reach Grok Bot.
private struct ReplyUnavailableView: View {
    @ObservedObject var model: StageModel
    let reason: String
    let isSecure: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(reason, systemImage: isSecure ? "lock.shield" : "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if reason.contains("Accessibility") {
                    Button("Grant Access…") { model.actions?.requestAccessibility() }
                }
                Button(isSecure ? "Open in Grok Bot" : "Answer in Grok Bot") { model.actions?.openInGrokBot() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct DeliveryStatusView: View {
    @ObservedObject var model: StageModel

    var body: some View {
        switch model.delivery {
        case .idle:
            EmptyView()
        case .sending:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Sending to \(model.botName)…").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .delivered:
            Label("Delivered", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        case .failed(let error):
            VStack(alignment: .leading, spacing: 6) {
                Label(error.userMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                if model.isDemo {
                    EmptyView()
                } else if error == .accessibilityPermissionMissing {
                    Button("Grant Accessibility Access…") { model.actions?.requestAccessibility() }
                        .buttonStyle(.link)
                        .font(.caption)
                } else if !error.isSafeToRetry || [.ambiguousBot, .botNotFound, .questionNotFound, .choiceNotOffered].contains(error) {
                    Button("Answer in Grok Bot") { model.actions?.openInGrokBot() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
    }
}

private struct BubbleFooter: View {
    @ObservedObject var model: StageModel
    let request: AttentionRequest

    /// The footer link is left out where the reply area already offers Grok
    /// Bot as its main button, and for demo bots, which have nothing to open.
    private var showsOpenInGrokBot: Bool {
        !model.isDemo
            && request.content.grokBotOnlyReason == nil
            && model.replyUnavailableReason == nil
            && request.content.kind != .approval
    }

    var body: some View {
        HStack {
            if showsOpenInGrokBot {
                Button { model.actions?.openInGrokBot() } label: {
                    Label("Open in Grok Bot", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Open in Grok Bot (⌘O)")
            }
            Spacer()
            Menu {
                Button("Snooze for \(model.snoozeMinutes) minutes (⌘L)") { model.actions?.snooze() }
                Button("Dismiss, keep in menu bar (⌘D)") { model.actions?.dismiss() }
            } label: {
                Text("Later")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .font(.caption)
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
#endif

#if canImport(AppKit)
/// Number keys 1–9 pick the matching answer while the reply is open. Off
/// while typing a different answer, so digits go into the text field.
private struct NumberKeyShortcut: ViewModifier {
    let index: Int
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled, index < 9 {
            content.keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
        } else {
            content
        }
    }
}

/// Keyboard shortcuts while the reply is open: ⌘[ / ⌘] switch requests,
/// ⌘L snoozes, ⌘D dismisses, ⌘O opens Grok Bot. Esc closes (on the close button).
private struct BubbleShortcuts: View {
    @ObservedObject var model: StageModel

    var body: some View {
        ZStack {
            Button("Newer request") { model.actions?.showPrevious() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Older request") { model.actions?.showNext() }
                .keyboardShortcut("]", modifiers: .command)
            Button("Snooze") { model.actions?.snooze() }
                .keyboardShortcut("l", modifiers: .command)
            Button("Dismiss") { model.actions?.dismiss() }
                .keyboardShortcut("d", modifiers: .command)
            if !model.isDemo {
                Button("Open in Grok Bot") { model.actions?.openInGrokBot() }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
        .buttonStyle(.plain)
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
