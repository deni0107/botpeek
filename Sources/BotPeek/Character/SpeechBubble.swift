#if canImport(AppKit)
import SwiftUI
import BotPeekCore

struct SpeechBubble: View {
    @ObservedObject var model: StageModel
    static let width: CGFloat = 312

    var body: some View {
        let shape = BubbleShape(tail: model.bubbleTail)
        VStack(alignment: .leading, spacing: 10) {
            BubbleHeader(model: model)
            if let request = model.request {
                PromptText(text: request.content.displayPrompt, isExpanded: model.isExpanded)
                if model.isExpanded {
                    ReplyArea(model: model, request: request)
                        .transition(.opacity)
                } else {
                    Text(collapsedHint(for: request))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DeliveryStatusView(model: model)
                if model.isExpanded {
                    BubbleFooter(model: model)
                }
            }
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
        .interactiveRegion()
        .animation(model.reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: model.isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Request from \(model.botName)")
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
        switch request.content.kind {
        case .choice: return "Click to choose an answer"
        case .approval: return "Click to review"
        default: return "Click to reply"
        }
    }
}

private struct BubbleHeader: View {
    @ObservedObject var model: StageModel

    var body: some View {
        HStack(spacing: 6) {
            Text(model.botName)
                .font(.system(.headline, design: .rounded))
                .lineLimit(1)
            if model.isDemo {
                Text("DEMO")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.9)))
                    .foregroundStyle(.white)
                    .accessibilityLabel("Demo mode: sample bot, not your Grok Bot")
            }
            Spacer(minLength: 4)
            if let queue = model.queue, queue.count > 1 {
                HStack(spacing: 2) {
                    Button { model.actions?.showPrevious() } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous request")
                    Text("\(queue.index + 1) of \(queue.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button { model.actions?.showNext() } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next request")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            if model.isExpanded {
                Button { model.actions?.collapse() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Close (the request stays pending)")
                .accessibilityLabel("Close")
            }
        }
    }
}

private struct PromptText: View {
    let text: String
    let isExpanded: Bool
    @State private var showsAll = false

    var body: some View {
        let isLong = text.count > 220 || text.components(separatedBy: "\n").count > 5
        VStack(alignment: .leading, spacing: 4) {
            if isExpanded && showsAll {
                ScrollView {
                    Text(text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            } else {
                Text(text)
                    .lineLimit(isExpanded ? 6 : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isExpanded && isLong {
                Button(showsAll ? "Show less" : "Show full request") { showsAll.toggle() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .font(.system(.body, design: .rounded))
    }
}

private struct ReplyArea: View {
    @ObservedObject var model: StageModel
    let request: AttentionRequest

    var body: some View {
        if let reason = model.replyUnavailableReason {
            ReplyUnavailableView(model: model, reason: reason)
        } else {
            switch request.content.kind {
            case .approval:
                ApprovalView(model: model, request: request)
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
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(choice.label).multilineTextAlignment(.leading)
                            if let detail = choice.detail {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
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
                .buttonStyle(.plain)
                .disabled(model.delivery == .sending)
                .accessibilityLabel("Answer \(choice.label)")
            }
            if showsComposer {
                Composer(model: model, placeholder: "Type a different answer…")
            } else {
                Button("Type a different answer") { showsComposer = true }
                    .buttonStyle(.link)
                    .font(.caption)
            }
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
                        Button(deny.label) { pending = PendingApproval(decision: .deny, option: deny) }
                        Spacer()
                        Button(approve.label + "…") { pending = PendingApproval(decision: .approve, option: approve) }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Review in Grok Bot") { model.actions?.openInGrokBot() }
                        .buttonStyle(.link)
                        .font(.caption)
                } else {
                    reviewInGrokBot
                }
            } else {
                reviewInGrokBot
            }
        }
    }

    private var reviewInGrokBot: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Approvals open in Grok Bot so you can review the full details.", systemImage: "checkmark.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Review in Grok Bot") { model.actions?.openInGrokBot() }
                .buttonStyle(.borderedProminent)
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

private struct ReplyUnavailableView: View {
    @ObservedObject var model: StageModel
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                if reason.contains("Accessibility") {
                    Button("Grant Access…") { model.actions?.requestAccessibility() }
                }
                Button("Answer in Grok Bot") { model.actions?.openInGrokBot() }
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
                if !error.isSafeToRetry || error == .ambiguousBot || error == .botNotFound {
                    Button("Check in Grok Bot") { model.actions?.openInGrokBot() }
                        .buttonStyle(.link)
                        .font(.caption)
                } else if error == .accessibilityPermissionMissing {
                    Button("Grant Accessibility Access…") { model.actions?.requestAccessibility() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
    }
}

private struct BubbleFooter: View {
    @ObservedObject var model: StageModel

    var body: some View {
        HStack {
            Button { model.actions?.openInGrokBot() } label: {
                Label("Open in Grok Bot", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Spacer()
            Menu {
                Button("Snooze for \(model.snoozeMinutes) minutes") { model.actions?.snooze() }
                Button("Dismiss (keep in menu bar)") { model.actions?.dismiss() }
            } label: {
                Text("Later")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}
#endif
