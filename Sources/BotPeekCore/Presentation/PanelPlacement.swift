import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Geometry for the character panel. Uses AppKit's coordinate system
/// (origin at the bottom-left of the screen).
public enum PanelPlacement {
    /// How far the character sits from the panel's end along the edge.
    public static let characterInset: CGFloat = 16

    /// On the right and left edges, `position` places the character itself.
    /// In the upper half the bubble and the stack hang below it instead of
    /// above, so the character can reach any height on screen.
    public static func growsDown(edge: ScreenEdge, position: Double) -> Bool {
        edge != .bottom && position > 0.5
    }

    /// The panel frame flush against `edge` inside `visibleFrame`.
    ///
    /// `position` runs along the edge from 0 (bottom or left end) to 1 (top or
    /// right end). On the side edges it places the character; on the bottom
    /// edge, the panel. The panel never extends beyond the visible frame, so
    /// it never covers the menu bar or the Dock.
    public static func frame(
        contentSize: CGSize,
        edge: ScreenEdge,
        position: Double,
        visibleFrame: CGRect,
        characterSize: CGFloat = 72,
        inset: CGFloat = 8
    ) -> CGRect {
        let width = min(contentSize.width, visibleFrame.width)
        let height = min(contentSize.height, visibleFrame.height)
        let fraction = CGFloat(min(max(position, 0), 1))

        switch edge {
        case .right, .left:
            let range = characterRange(characterSize: characterSize, visibleFrame: visibleFrame, inset: inset)
            let bottom = range.low + (range.high - range.low) * fraction
            let y = growsDown(edge: edge, position: position)
                ? bottom + characterSize + characterInset - height
                : bottom - characterInset
            let x = edge == .right ? visibleFrame.maxX - width : visibleFrame.minX
            return CGRect(x: x, y: min(max(y, visibleFrame.minY), visibleFrame.maxY - height), width: width, height: height)
        case .bottom:
            // The inset shrinks when space is tight so the panel stays inside.
            let available = visibleFrame.width - width
            let margin = min(inset, available / 2)
            let x = visibleFrame.minX + margin + (available - margin * 2) * fraction
            return CGRect(x: x, y: visibleFrame.minY, width: width, height: height)
        }
    }

    /// Where the character's bottom can be on a side edge, from position 0 to 1.
    static func characterRange(characterSize: CGFloat, visibleFrame: CGRect, inset: CGFloat) -> (low: CGFloat, high: CGFloat) {
        let low = visibleFrame.minY + inset + characterInset
        return (low, max(low, visibleFrame.maxY - inset - characterInset - characterSize))
    }

    /// The point that dragging moves: the character's bottom on a side edge,
    /// the panel's left side on the bottom edge.
    public static func dragAnchor(of frame: CGRect, edge: ScreenEdge, growsDown: Bool, characterSize: CGFloat) -> CGFloat {
        switch edge {
        case .right, .left: return growsDown ? frame.maxY - characterInset - characterSize : frame.minY + characterInset
        case .bottom: return frame.minX
        }
    }

    /// The position (0...1) that puts the drag anchor at `anchor`: the
    /// inverse of `frame(...)`, used while dragging.
    public static func position(
        forDragAnchor anchor: CGFloat,
        edge: ScreenEdge,
        contentSize: CGSize,
        visibleFrame: CGRect,
        characterSize: CGFloat = 72,
        inset: CGFloat = 8
    ) -> Double {
        let start: CGFloat, span: CGFloat
        switch edge {
        case .right, .left:
            let range = characterRange(characterSize: characterSize, visibleFrame: visibleFrame, inset: inset)
            start = range.low
            span = range.high - range.low
        case .bottom:
            let available = visibleFrame.width - min(contentSize.width, visibleFrame.width)
            let margin = min(inset, available / 2)
            start = visibleFrame.minX + margin
            span = available - margin * 2
        }
        guard span > 0 else { return 0.5 }
        return Double(min(max((anchor - start) / span, 0), 1))
    }

    /// Unit vector pointing from the screen edge into the screen, in SwiftUI
    /// coordinates (y grows downwards). The character moves along this axis.
    public static func inwardDirection(for edge: ScreenEdge) -> (dx: Double, dy: Double) {
        switch edge {
        case .right: return (-1, 0)
        case .left: return (1, 0)
        case .bottom: return (0, -1)
        }
    }

    /// Size of the panel for a character and its speech bubble side by side
    /// (right/left edges) or stacked (bottom edge), with room along the edge
    /// for the stack of other waiting bots. The room is always reserved, so
    /// the panel doesn't move as bots come and go.
    public static func contentSize(characterSize: Double, bubbleSize: CGSize, edge: ScreenEdge) -> CGSize {
        let character = CGFloat(characterSize)
        let stack = CGFloat(stackLength(characterSize: characterSize))
        let padding: CGFloat = 24
        switch edge {
        case .right, .left:
            return CGSize(
                width: bubbleSize.width + character + padding,
                height: max(bubbleSize.height, character + stack) + padding * 2
            )
        case .bottom:
            // The character stays centered under its bubble, the stack beside it.
            return CGSize(
                width: max(bubbleSize.width, character + stack * 2) + padding * 2,
                height: bubbleSize.height + character + padding
            )
        }
    }

    // MARK: Stack of waiting bots

    /// Waiting bots shown beside the active character; any more are summed
    /// up in a "+N" slot.
    public static let maxStackedAvatars = 4
    public static let stackSpacing = 6.0
    /// How much of a stacked avatar shows past the edge, at rest and on hover.
    public static let stackVisibleFraction = 0.68
    public static let stackHoverVisibleFraction = 0.9

    public static func stackAvatarSize(characterSize: Double) -> Double {
        (characterSize * 0.56).rounded()
    }

    /// Room along the edge for the full stack, including the "+N" slot.
    public static func stackLength(characterSize: Double) -> Double {
        let slots = Double(maxStackedAvatars + 1)
        return slots * (stackAvatarSize(characterSize: characterSize) + stackSpacing)
    }

    /// Splits the other waiting requests into the avatars to stack and how
    /// many are left over for the "+N" slot.
    public static func stack<T>(_ waiting: [T]) -> (shown: [T], overflow: Int) {
        let shown = Array(waiting.prefix(maxStackedAvatars))
        return (shown, waiting.count - shown.count)
    }
}
