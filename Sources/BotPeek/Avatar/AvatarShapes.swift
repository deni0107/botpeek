#if canImport(AppKit)
import SwiftUI
import BotPeekCore

/// BotPeek's own vector drawings of Grok Bot's named avatar shapes.
/// All coordinates are fractions of the avatar's square.
struct AvatarSilhouette: Shape {
    let shape: AvatarShape

    func path(in rect: CGRect) -> Path {
        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y) }
        let w = rect.width
        switch shape {
        case .classic:
            var path = Path()
            path.move(to: p(0.50, 0.08))
            path.addCurve(to: p(0.92, 0.46), control1: p(0.76, 0.07), control2: p(0.93, 0.24))
            path.addCurve(to: p(0.52, 0.93), control1: p(0.91, 0.72), control2: p(0.76, 0.93))
            path.addCurve(to: p(0.08, 0.52), control1: p(0.26, 0.93), control2: p(0.08, 0.76))
            path.addCurve(to: p(0.50, 0.08), control1: p(0.08, 0.27), control2: p(0.25, 0.09))
            path.closeSubpath()
            return path
        case .wedge:
            return Self.roundedPolygon([p(0.10, 0.52), p(0.70, 0.12), p(0.92, 0.36), p(0.78, 0.86), p(0.18, 0.78)], radius: w * 0.10)
        case .cloud:
            var path = Path()
            for (x, y, r) in [(0.32, 0.56, 0.22), (0.50, 0.42, 0.26), (0.70, 0.55, 0.21), (0.50, 0.64, 0.24)] as [(CGFloat, CGFloat, CGFloat)] {
                path.addEllipse(in: CGRect(x: rect.minX + w * (x - r), y: rect.minY + w * (y - r), width: w * r * 2, height: w * r * 2))
            }
            path.addRoundedRect(in: CGRect(x: rect.minX + w * 0.14, y: rect.minY + w * 0.55, width: w * 0.72, height: w * 0.26), cornerSize: CGSize(width: w * 0.13, height: w * 0.13))
            return path
        case .square:
            return Path(roundedRect: rect.insetBy(dx: w * 0.12, dy: w * 0.12), cornerRadius: w * 0.2, style: .continuous)
        case .sparkle:
            var path = Path()
            path.move(to: p(0.50, 0.04))
            path.addQuadCurve(to: p(0.96, 0.50), control: p(0.58, 0.42))
            path.addQuadCurve(to: p(0.50, 0.96), control: p(0.58, 0.58))
            path.addQuadCurve(to: p(0.04, 0.50), control: p(0.42, 0.58))
            path.addQuadCurve(to: p(0.50, 0.04), control: p(0.42, 0.42))
            path.closeSubpath()
            return path
        case .clover:
            var path = Path()
            let r: CGFloat = 0.23
            for (x, y) in [(0.36, 0.36), (0.64, 0.36), (0.36, 0.64), (0.64, 0.64)] as [(CGFloat, CGFloat)] {
                path.addEllipse(in: CGRect(x: rect.minX + w * (x - r), y: rect.minY + w * (y - r), width: w * r * 2, height: w * r * 2))
            }
            path.addEllipse(in: CGRect(x: rect.minX + w * 0.3, y: rect.minY + w * 0.3, width: w * 0.4, height: w * 0.4))
            return path
        case .flower:
            var path = Path()
            let r: CGFloat = 0.17
            for index in 0..<6 {
                let angle = CGFloat(index) * .pi / 3 - .pi / 2
                let x = 0.5 + cos(angle) * 0.27
                let y = 0.5 + sin(angle) * 0.27
                path.addEllipse(in: CGRect(x: rect.minX + w * (x - r), y: rect.minY + w * (y - r), width: w * r * 2, height: w * r * 2))
            }
            path.addEllipse(in: CGRect(x: rect.minX + w * 0.27, y: rect.minY + w * 0.27, width: w * 0.46, height: w * 0.46))
            return path
        case .heart:
            var path = Path()
            path.move(to: p(0.50, 0.90))
            path.addCurve(to: p(0.06, 0.38), control1: p(0.30, 0.76), control2: p(0.06, 0.60))
            path.addCurve(to: p(0.50, 0.24), control1: p(0.06, 0.12), control2: p(0.40, 0.08))
            path.addCurve(to: p(0.94, 0.38), control1: p(0.60, 0.08), control2: p(0.94, 0.12))
            path.addCurve(to: p(0.50, 0.90), control1: p(0.94, 0.60), control2: p(0.70, 0.76))
            path.closeSubpath()
            return path
        case .star:
            var points: [CGPoint] = []
            for index in 0..<10 {
                let radius: CGFloat = index.isMultiple(of: 2) ? 0.46 : 0.26
                let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 5
                points.append(p(0.5 + cos(angle) * radius, 0.53 + sin(angle) * radius))
            }
            return Self.roundedPolygon(points, radius: w * 0.05)
        case .teardrop:
            var path = Path()
            path.move(to: p(0.50, 0.05))
            path.addCurve(to: p(0.86, 0.60), control1: p(0.64, 0.24), control2: p(0.86, 0.38))
            path.addCurve(to: p(0.50, 0.94), control1: p(0.86, 0.80), control2: p(0.70, 0.94))
            path.addCurve(to: p(0.14, 0.60), control1: p(0.30, 0.94), control2: p(0.14, 0.80))
            path.addCurve(to: p(0.50, 0.05), control1: p(0.14, 0.38), control2: p(0.36, 0.24))
            path.closeSubpath()
            return path
        case .egg:
            var path = Path()
            path.move(to: p(0.50, 0.06))
            path.addCurve(to: p(0.86, 0.58), control1: p(0.72, 0.06), control2: p(0.86, 0.34))
            path.addCurve(to: p(0.50, 0.94), control1: p(0.86, 0.80), control2: p(0.70, 0.94))
            path.addCurve(to: p(0.14, 0.58), control1: p(0.30, 0.94), control2: p(0.14, 0.80))
            path.addCurve(to: p(0.50, 0.06), control1: p(0.14, 0.34), control2: p(0.28, 0.06))
            path.closeSubpath()
            return path
        case .capsule:
            return Path(roundedRect: CGRect(x: rect.minX + w * 0.08, y: rect.minY + w * 0.24, width: w * 0.84, height: w * 0.52), cornerRadius: w * 0.26)
        case .house:
            return Self.roundedPolygon([p(0.50, 0.08), p(0.90, 0.40), p(0.82, 0.90), p(0.18, 0.90), p(0.10, 0.40)], radius: w * 0.09)
        case .hexagon:
            let points = (0..<6).map { index -> CGPoint in
                let angle = CGFloat(index) * .pi / 3 - .pi / 2
                return p(0.5 + cos(angle) * 0.45, 0.5 + sin(angle) * 0.45)
            }
            return Self.roundedPolygon(points, radius: w * 0.09)
        case .gem:
            return Self.roundedPolygon([p(0.28, 0.14), p(0.72, 0.14), p(0.92, 0.38), p(0.50, 0.92), p(0.08, 0.38)], radius: w * 0.07)
        case .pebble:
            var path = Path()
            path.move(to: p(0.30, 0.16))
            path.addCurve(to: p(0.88, 0.36), control1: p(0.52, 0.04), control2: p(0.82, 0.14))
            path.addCurve(to: p(0.70, 0.86), control1: p(0.96, 0.60), control2: p(0.88, 0.80))
            path.addCurve(to: p(0.14, 0.70), control1: p(0.48, 0.94), control2: p(0.20, 0.90))
            path.addCurve(to: p(0.30, 0.16), control1: p(0.06, 0.48), control2: p(0.12, 0.26))
            path.closeSubpath()
            return path
        case .circle:
            return Path(ellipseIn: rect.insetBy(dx: w * 0.06, dy: w * 0.06))
        }
    }

    /// A closed polygon with rounded corners.
    static func roundedPolygon(_ points: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        let count = points.count
        let start = CGPoint(x: (points[count - 1].x + points[0].x) / 2, y: (points[count - 1].y + points[0].y) / 2)
        path.move(to: start)
        for index in 0..<count {
            let corner = points[index]
            let next = points[(index + 1) % count]
            path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
        }
        path.closeSubpath()
        return path
    }

    /// Where the face sits inside each shape, as a fraction of the square.
    static func faceCenter(for shape: AvatarShape) -> CGPoint {
        switch shape {
        case .heart: return CGPoint(x: 0.5, y: 0.46)
        case .star: return CGPoint(x: 0.5, y: 0.55)
        case .teardrop, .egg: return CGPoint(x: 0.5, y: 0.62)
        case .house: return CGPoint(x: 0.5, y: 0.6)
        case .gem: return CGPoint(x: 0.5, y: 0.4)
        case .cloud: return CGPoint(x: 0.5, y: 0.58)
        default: return CGPoint(x: 0.5, y: 0.52)
        }
    }
}

/// Simple eyes drawn over built-in shapes. Happy eyes while celebrating.
struct AvatarFace: View {
    let shape: AvatarShape
    let color: AvatarColor
    var isHappy = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            let center = AvatarSilhouette.faceCenter(for: shape)
            let eyeColor: Color = color.isLight ? Color.black.opacity(0.78) : .white
            let spacing = size * 0.17
            Group {
                if isHappy {
                    HStack(spacing: spacing) {
                        HappyEye().stroke(eyeColor, style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))
                        HappyEye().stroke(eyeColor, style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))
                    }
                    .frame(width: size * 0.42, height: size * 0.1)
                } else {
                    HStack(spacing: spacing) {
                        Capsule().fill(eyeColor).frame(width: size * 0.075, height: size * 0.15)
                        Capsule().fill(eyeColor).frame(width: size * 0.075, height: size * 0.15)
                    }
                }
            }
            .position(x: size * center.x, y: size * center.y)
        }
    }
}

private struct HappyEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height))
        return path
    }
}
#endif
