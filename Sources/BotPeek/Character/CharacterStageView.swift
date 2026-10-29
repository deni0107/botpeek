#if canImport(AppKit)
import SwiftUI
import BotPeekCore

/// The panel's root view: the peeking character and its speech bubble,
/// arranged against the chosen screen edge.
struct CharacterStageView: View {
    @ObservedObject var model: StageModel
    var onInteractiveRectsChange: ([CGRect]) -> Void

    var body: some View {
        ZStack(alignment: stageAlignment) {
            Color.clear
            arrangement
        }
        .coordinateSpace(name: StageCoordinateSpace.name)
        .onPreferenceChange(InteractiveRectsKey.self) { rects in
            onInteractiveRectsChange(rects)
        }
    }

    private var stageAlignment: Alignment {
        switch model.edge {
        case .right: return model.growsDown ? .topTrailing : .bottomTrailing
        case .left: return model.growsDown ? .topLeading : .bottomLeading
        case .bottom: return .bottom
        }
    }

    /// The character with the stack on the far side from the bubble's end.
    @ViewBuilder
    private func characterColumn(_ alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: CGFloat(PanelPlacement.stackSpacing)) {
            if model.growsDown {
                PeekingCharacter(model: model)
                PeekStack(model: model)
            } else {
                PeekStack(model: model)
                PeekingCharacter(model: model)
            }
        }
    }

    @ViewBuilder
    private var arrangement: some View {
        switch model.edge {
        case .right:
            HStack(alignment: model.growsDown ? .top : .bottom, spacing: 4) {
                bubble
                characterColumn(.trailing)
            }
            .padding(model.growsDown ? .top : .bottom, PanelPlacement.characterInset)
        case .left:
            HStack(alignment: model.growsDown ? .top : .bottom, spacing: 4) {
                characterColumn(.leading)
                bubble
            }
            .padding(model.growsDown ? .top : .bottom, PanelPlacement.characterInset)
        case .bottom:
            VStack(spacing: 4) {
                bubble
                // An empty spacer the stack's width keeps the character centered under its bubble.
                HStack(alignment: .bottom, spacing: CGFloat(PanelPlacement.stackSpacing)) {
                    Color.clear.frame(width: stackLength, height: 1)
                    PeekingCharacter(model: model)
                    PeekStack(model: model)
                        .frame(width: stackLength, alignment: .leading)
                }
            }
        }
    }

    private var stackLength: CGFloat {
        CGFloat(PanelPlacement.stackLength(characterSize: Double(model.characterSize)))
    }

    @ViewBuilder
    private var bubble: some View {
        if model.bubbleVisible, model.request != nil {
            SpeechBubble(model: model)
                .transition(bubbleTransition)
        }
    }

    private var bubbleTransition: AnyTransition {
        if model.reduceMotion { return .opacity }
        let anchor: UnitPoint
        switch model.edge {
        case .right: anchor = model.growsDown ? .topTrailing : .bottomTrailing
        case .left: anchor = model.growsDown ? .topLeading : .bottomLeading
        case .bottom: anchor = .bottom
        }
        return .scale(scale: 0.6, anchor: anchor).combined(with: .opacity)
    }
}

/// The bot's avatar, sliding out from behind the screen edge.
struct PeekingCharacter: View {
    @ObservedObject var model: StageModel

    var body: some View {
        let size = model.characterSize
        let travel = size * 1.15
        let inward = PanelPlacement.inwardDirection(for: model.edge)
        let pose = model.pose
        let hover = model.isHovering && !model.reduceMotion && model.phase == .presented

        BotAvatarView(source: model.avatar, size: size, isHappy: model.phase == .celebrating)
            .overlay(alignment: badgeAlignment) {
                if model.isShrunk {
                    // The bubble tucked itself away; a small badge says there's still a message.
                    Image(systemName: "ellipsis.bubble.fill")
                        .font(.system(size: size * 0.26))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(model.reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: model.isShrunk)
            .scaleEffect(pose.scale * (hover ? 1.05 : 1), anchor: anchor)
            .rotationEffect(.degrees(pose.rotationDegrees * (model.edge == .left ? -1 : 1)), anchor: anchor)
            .offset(x: -CGFloat(inward.dx) * travel * CGFloat(pose.hidden),
                    y: -CGFloat(inward.dy) * travel * CGFloat(pose.hidden))
            .opacity(pose.opacity)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .gesture(
                // Drag along the edge to move the character; the spot is remembered.
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in model.actions?.dragChanged() }
                    .onEnded { _ in model.actions?.dragEnded() }
            )
            .onTapGesture {
                if model.isExpanded { model.actions?.collapse() } else { model.actions?.expand() }
            }
            .onHover { model.isHovering = $0 }
            .interactiveRegion()
            .accessibilityElement()
            .accessibilityLabel("\(model.botName) needs your attention")
            .accessibilityHint(model.isExpanded ? "Collapses the reply" : "Opens the reply")
            .accessibilityAddTraits(.isButton)
    }

    /// The badge sits at the top corner facing into the screen.
    private var badgeAlignment: Alignment {
        switch model.edge {
        case .right, .bottom: return .topLeading
        case .left: return .topTrailing
        }
    }

    private var anchor: UnitPoint {
        switch model.edge {
        case .right: return .trailing
        case .left: return .leading
        case .bottom: return .bottom
        }
    }
}

/// The other waiting bots, mostly tucked behind the edge beside the active
/// character, next in line closest to it. Hover to see who it is and how long
/// they've waited; click to switch.
struct PeekStack: View {
    @ObservedObject var model: StageModel

    var body: some View {
        let size = CGFloat(PanelPlacement.stackAvatarSize(characterSize: Double(model.characterSize)))
        let items = stackItems
        Group {
            switch model.edge {
            case .right, .left:
                // Next in line sits closest to the character, above or below it.
                VStack(alignment: model.edge == .right ? .trailing : .leading, spacing: CGFloat(PanelPlacement.stackSpacing)) {
                    ForEach(model.growsDown ? items : items.reversed()) { item in itemView(item, size: size) }
                }
            case .bottom:
                HStack(alignment: .bottom, spacing: CGFloat(PanelPlacement.stackSpacing)) {
                    ForEach(items) { item in itemView(item, size: size) }
                }
            }
        }
        .opacity(model.request == nil ? 0 : 1)
    }

    private enum Item: Identifiable {
        case bot(WaitingBot)
        case overflow(Int)

        var id: String {
            switch self {
            case .bot(let bot): return bot.id.rawValue
            case .overflow: return "overflow"
            }
        }
    }

    private var stackItems: [Item] {
        var items = model.waiting.map(Item.bot)
        if model.waitingOverflow > 0 { items.append(.overflow(model.waitingOverflow)) }
        return items
    }

    @ViewBuilder
    private func itemView(_ item: Item, size: CGFloat) -> some View {
        switch item {
        case .bot(let bot):
            StackedAvatar(model: model, bot: bot, size: size)
                .transition(insertion)
        case .overflow(let count):
            OverflowChip(model: model, count: count, size: size)
                .transition(insertion)
        }
    }

    private var insertion: AnyTransition {
        if model.reduceMotion { return .opacity }
        switch model.edge {
        case .right: return .move(edge: .trailing).combined(with: .opacity)
        case .left: return .move(edge: .leading).combined(with: .opacity)
        case .bottom: return .move(edge: .bottom).combined(with: .opacity)
        }
    }
}

/// Clips a stacked item to the part that shows past the screen edge and
/// slides it further out on hover.
private struct TuckedAgainstEdge: ViewModifier {
    let edge: ScreenEdge
    let size: CGFloat
    let isHovering: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let visible = size * CGFloat(PanelPlacement.stackVisibleFraction)
        let extra = isHovering ? size * CGFloat(PanelPlacement.stackHoverVisibleFraction - PanelPlacement.stackVisibleFraction) : 0
        switch edge {
        case .right:
            content.offset(x: -extra)
                .frame(width: visible, height: size, alignment: .leading)
        case .left:
            content.offset(x: extra)
                .frame(width: visible, height: size, alignment: .trailing)
        case .bottom:
            content.offset(y: -extra)
                .frame(width: size, height: visible, alignment: .top)
        }
    }
}

private struct StackedAvatar: View {
    @ObservedObject var model: StageModel
    let bot: WaitingBot
    let size: CGFloat
    @State private var isHovering = false

    var body: some View {
        BotAvatarView(source: bot.avatar, size: size, showsShadow: true)
            .modifier(TuckedAgainstEdge(edge: model.edge, size: size, isHovering: isHovering, reduceMotion: model.reduceMotion))
            .animation(model.reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75), value: isHovering)
            .contentShape(Rectangle())
            .onTapGesture { model.actions?.focus(bot.id) }
            .onHover { isHovering = $0 }
            .overlay(alignment: labelAlignment) {
                if isHovering {
                    StackLabel(edge: model.edge) {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text("\(bot.name) · \(WaitTime.describe(since: bot.waitingSince, now: context.date))")
                        }
                    }
                    .transition(.opacity)
                }
            }
            .zIndex(isHovering ? 1 : 0)
            .interactiveRegion()
            .accessibilityElement()
            .accessibilityLabel("\(bot.name) is also waiting")
            .accessibilityHint("Shows this request")
            .accessibilityAddTraits(.isButton)
    }

    private var labelAlignment: Alignment {
        switch model.edge {
        case .right: return .leading
        case .left: return .trailing
        case .bottom: return .top
        }
    }
}

private struct OverflowChip: View {
    @ObservedObject var model: StageModel
    let count: Int
    let size: CGFloat

    var body: some View {
        Text("+\(count)")
            .font(.system(size: size * 0.32, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(Circle().fill(.regularMaterial))
            .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
            .modifier(TuckedAgainstEdge(edge: model.edge, size: size, isHovering: false, reduceMotion: model.reduceMotion))
            .contentShape(Rectangle())
            .onTapGesture { model.actions?.showNext() }
            .interactiveRegion()
            .help("\(count) more waiting. The menu bar lists them all.")
            .accessibilityLabel("\(count) more bots waiting")
            .accessibilityAddTraits(.isButton)
    }
}

/// A small name tag beside a stacked avatar, pointing into the screen.
/// It hangs off a zero-size anchor on the avatar's inner side, so it grows
/// away from the screen edge whatever its width.
private struct StackLabel<Content: View>: View {
    let edge: ScreenEdge
    @ViewBuilder var content: Content

    var body: some View {
        switch edge {
        case .right:
            Color.clear.frame(width: 0).overlay(alignment: .trailing) { tag.padding(.trailing, 6) }
        case .left:
            Color.clear.frame(width: 0).overlay(alignment: .leading) { tag.padding(.leading, 6) }
        case .bottom:
            Color.clear.frame(height: 0).overlay(alignment: .bottom) { tag.padding(.bottom, 6) }
        }
    }

    private var tag: some View {
        content
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            .fixedSize()
            .allowsHitTesting(false)
    }
}

/// A rounded bubble with a small tail pointing at the character.
struct BubbleShape: Shape {
    enum Tail { case trailing, leading, bottom }

    var tail: Tail
    /// Side tails point at the character near the bubble's top instead of its bottom.
    var tailNearTop = false
    var radius: CGFloat = 18
    static let tailSize: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        let t = Self.tailSize
        var body = rect
        switch tail {
        case .trailing: body.size.width -= t
        case .leading: body.origin.x += t; body.size.width -= t
        case .bottom: body.size.height -= t
        }
        var path = Path(roundedRect: body, cornerRadius: radius, style: .continuous)
        var tailPath = Path()
        switch tail {
        case .trailing:
            let y = tailNearTop ? body.minY + 30 : body.maxY - 30
            tailPath.move(to: CGPoint(x: body.maxX - 2, y: y - 9))
            tailPath.addQuadCurve(to: CGPoint(x: rect.maxX, y: y + 7), control: CGPoint(x: body.maxX + 2, y: y + 2))
            tailPath.addQuadCurve(to: CGPoint(x: body.maxX - 2, y: y + 9), control: CGPoint(x: body.maxX + 1, y: y + 9))
        case .leading:
            let y = tailNearTop ? body.minY + 30 : body.maxY - 30
            tailPath.move(to: CGPoint(x: body.minX + 2, y: y - 9))
            tailPath.addQuadCurve(to: CGPoint(x: rect.minX, y: y + 7), control: CGPoint(x: body.minX - 2, y: y + 2))
            tailPath.addQuadCurve(to: CGPoint(x: body.minX + 2, y: y + 9), control: CGPoint(x: body.minX - 1, y: y + 9))
        case .bottom:
            let x = body.midX
            tailPath.move(to: CGPoint(x: x - 9, y: body.maxY - 2))
            tailPath.addQuadCurve(to: CGPoint(x: x + 5, y: rect.maxY), control: CGPoint(x: x - 1, y: body.maxY + 2))
            tailPath.addQuadCurve(to: CGPoint(x: x + 9, y: body.maxY - 2), control: CGPoint(x: x + 8, y: body.maxY + 1))
        }
        tailPath.closeSubpath()
        path.addPath(tailPath)
        return path
    }
}

extension StageModel {
    var bubbleTail: BubbleShape.Tail {
        switch edge {
        case .right: return .trailing
        case .left: return .leading
        case .bottom: return .bottom
        }
    }
}
#endif
