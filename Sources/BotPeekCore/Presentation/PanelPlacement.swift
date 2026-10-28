import Foundation

/// Geometry for the character panel. Uses AppKit's coordinate system
/// (origin at the bottom-left of the screen).
public enum PanelPlacement {
    /// The panel frame flush against `edge` inside `visibleFrame`.
    ///
    /// `position` runs along the edge from 0 (bottom or left end) to 1 (top or
    /// right end). The panel never extends beyond the visible frame, so it
    /// never covers the menu bar or the Dock.
    public static func frame(
        contentSize: CGSize,
        edge: ScreenEdge,
        position: Double,
        visibleFrame: CGRect,
        inset: CGFloat = 8
    ) -> CGRect {
        let width = min(contentSize.width, visibleFrame.width)
        let height = min(contentSize.height, visibleFrame.height)
        let fraction = CGFloat(min(max(position, 0), 1))

        // Offset along the edge; the inset shrinks when space is tight so the
        // panel always stays inside the visible frame.
        func offset(available: CGFloat) -> CGFloat {
            let margin = min(inset, available / 2)
            return margin + (available - margin * 2) * fraction
        }

        switch edge {
        case .right, .left:
            let y = visibleFrame.minY + offset(available: visibleFrame.height - height)
            let x = edge == .right ? visibleFrame.maxX - width : visibleFrame.minX
            return CGRect(x: x, y: y, width: width, height: height)
        case .bottom:
            let x = visibleFrame.minX + offset(available: visibleFrame.width - width)
            return CGRect(x: x, y: visibleFrame.minY, width: width, height: height)
        }
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
    /// (right/left edges) or stacked (bottom edge).
    public static func contentSize(characterSize: Double, bubbleSize: CGSize, edge: ScreenEdge) -> CGSize {
        let character = CGFloat(characterSize)
        let padding: CGFloat = 24
        switch edge {
        case .right, .left:
            return CGSize(
                width: bubbleSize.width + character + padding,
                height: max(bubbleSize.height, character) + padding * 2
            )
        case .bottom:
            return CGSize(
                width: max(bubbleSize.width, character) + padding * 2,
                height: bubbleSize.height + character + padding
            )
        }
    }
}
