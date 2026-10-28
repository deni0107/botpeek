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
        case .right: return .bottomTrailing
        case .left: return .bottomLeading
        case .bottom: return .bottom
        }
    }

    @ViewBuilder
    private var arrangement: some View {
        switch model.edge {
        case .right:
            HStack(alignment: .bottom, spacing: 4) {
                bubble
                PeekingCharacter(model: model)
            }
            .padding(.bottom, 16)
        case .left:
            HStack(alignment: .bottom, spacing: 4) {
                PeekingCharacter(model: model)
                bubble
            }
            .padding(.bottom, 16)
        case .bottom:
            VStack(spacing: 4) {
                bubble
                PeekingCharacter(model: model)
            }
        }
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
        case .right: anchor = .bottomTrailing
        case .left: anchor = .bottomLeading
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
            .scaleEffect(pose.scale * (hover ? 1.05 : 1), anchor: anchor)
            .rotationEffect(.degrees(pose.rotationDegrees * (model.edge == .left ? -1 : 1)), anchor: anchor)
            .offset(x: -CGFloat(inward.dx) * travel * CGFloat(pose.hidden),
                    y: -CGFloat(inward.dy) * travel * CGFloat(pose.hidden))
            .opacity(pose.opacity)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
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

    private var anchor: UnitPoint {
        switch model.edge {
        case .right: return .trailing
        case .left: return .leading
        case .bottom: return .bottom
        }
    }
}

/// A rounded bubble with a small tail pointing at the character.
struct BubbleShape: Shape {
    enum Tail { case trailing, leading, bottom }

    var tail: Tail
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
            let y = body.maxY - 30
            tailPath.move(to: CGPoint(x: body.maxX - 2, y: y - 9))
            tailPath.addQuadCurve(to: CGPoint(x: rect.maxX, y: y + 7), control: CGPoint(x: body.maxX + 2, y: y + 2))
            tailPath.addQuadCurve(to: CGPoint(x: body.maxX - 2, y: y + 9), control: CGPoint(x: body.maxX + 1, y: y + 9))
        case .leading:
            let y = body.maxY - 30
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
