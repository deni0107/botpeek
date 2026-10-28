import Foundation

/// Spring parameters, matching SwiftUI's `.spring(response:dampingFraction:)`.
public struct SpringSpec: Equatable, Sendable {
    public var response: Double
    public var dampingFraction: Double

    public init(response: Double, dampingFraction: Double) {
        self.response = response
        self.dampingFraction = dampingFraction
    }
}

public enum MotionCurve: Equatable, Sendable {
    case spring(SpringSpec)
    case easeOut(duration: Double)
    case easeIn(duration: Double)
}

/// One pose of the character. `hidden` = 1 means fully tucked behind the
/// screen edge; 0 means fully out. Poses only move, scale and rotate the
/// avatar; they never change how it looks.
public struct MotionPose: Equatable, Sendable {
    public var hidden: Double
    public var scale: Double
    public var rotationDegrees: Double
    public var opacity: Double
    public var curve: MotionCurve
    /// Seconds to wait after the previous step started.
    public var delay: Double

    public init(hidden: Double, scale: Double = 1, rotationDegrees: Double = 0, opacity: Double = 1, curve: MotionCurve, delay: Double = 0) {
        self.hidden = hidden
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.opacity = opacity
        self.curve = curve
        self.delay = delay
    }
}

/// The complete motion for one appearance, derived from user preferences.
public struct AnimationPlan: Equatable, Sendable {
    /// Where the character starts before the entrance.
    public var initial: MotionPose
    public var entrance: [MotionPose]
    public var celebration: [MotionPose]
    public var exit: [MotionPose]
    /// Delay before the speech bubble appears.
    public var bubbleDelay: Double
    /// Whether anything moves (false under reduced motion).
    public var usesMotion: Bool
    /// The resting pose: how far the character stays peeking.
    public var rest: MotionPose

    public var entranceDuration: Double { Self.duration(of: entrance) }
    public var celebrationDuration: Double { Self.duration(of: celebration) }
    public var exitDuration: Double { Self.duration(of: exit) }

    static func duration(of steps: [MotionPose]) -> Double {
        var total = 0.0
        for (index, step) in steps.enumerated() {
            total += step.delay
            if index == steps.count - 1 {
                switch step.curve {
                case .spring(let spec): total += spec.response
                case .easeOut(let duration), .easeIn(let duration): total += duration
                }
            }
        }
        return total
    }

    /// How much of the character stays tucked behind the edge at rest.
    public static let restingHidden = 0.18

    public static func make(intensity: AnimationIntensity, reduceMotion: Bool) -> AnimationPlan {
        let rest = MotionPose(hidden: restingHidden, curve: .easeOut(duration: 0.2))
        if reduceMotion {
            // No sliding, bouncing or rotation: cross-fade in place.
            return AnimationPlan(
                initial: MotionPose(hidden: restingHidden, opacity: 0, curve: .easeOut(duration: 0)),
                entrance: [MotionPose(hidden: restingHidden, curve: .easeOut(duration: 0.25))],
                celebration: [],
                exit: [MotionPose(hidden: restingHidden, opacity: 0, curve: .easeIn(duration: 0.2))],
                bubbleDelay: 0.05,
                usesMotion: false,
                rest: rest
            )
        }
        switch intensity {
        case .lively:
            return AnimationPlan(
                initial: MotionPose(hidden: 1, rotationDegrees: 0, curve: .easeOut(duration: 0)),
                entrance: [
                    // Peek: a little more than half way out, curious tilt.
                    MotionPose(hidden: 0.55, rotationDegrees: -8, curve: .spring(SpringSpec(response: 0.38, dampingFraction: 0.72))),
                    // Pop out past rest, then settle with a tiny bounce.
                    MotionPose(hidden: 0.06, scale: 1.06, rotationDegrees: 4, curve: .spring(SpringSpec(response: 0.32, dampingFraction: 0.55)), delay: 0.42),
                    MotionPose(hidden: restingHidden, scale: 1, rotationDegrees: 0, curve: .spring(SpringSpec(response: 0.45, dampingFraction: 0.62)), delay: 0.22),
                ],
                celebration: [
                    MotionPose(hidden: 0.02, scale: 1.12, rotationDegrees: -10, curve: .spring(SpringSpec(response: 0.25, dampingFraction: 0.5))),
                    MotionPose(hidden: 0.04, scale: 1.08, rotationDegrees: 10, curve: .spring(SpringSpec(response: 0.25, dampingFraction: 0.5)), delay: 0.2),
                    MotionPose(hidden: restingHidden, scale: 1, rotationDegrees: 0, curve: .spring(SpringSpec(response: 0.3, dampingFraction: 0.7)), delay: 0.2),
                ],
                exit: [
                    MotionPose(hidden: 0.1, scale: 1.04, curve: .spring(SpringSpec(response: 0.2, dampingFraction: 0.8))),
                    MotionPose(hidden: 1, scale: 0.92, rotationDegrees: 6, curve: .easeIn(duration: 0.28), delay: 0.12),
                ],
                bubbleDelay: 0.55,
                usesMotion: true,
                rest: rest
            )
        case .subtle:
            return AnimationPlan(
                initial: MotionPose(hidden: 1, curve: .easeOut(duration: 0)),
                entrance: [
                    MotionPose(hidden: restingHidden, curve: .spring(SpringSpec(response: 0.5, dampingFraction: 0.82))),
                ],
                celebration: [
                    MotionPose(hidden: 0.08, scale: 1.05, curve: .spring(SpringSpec(response: 0.3, dampingFraction: 0.7))),
                    MotionPose(hidden: restingHidden, scale: 1, curve: .spring(SpringSpec(response: 0.35, dampingFraction: 0.8)), delay: 0.25),
                ],
                exit: [MotionPose(hidden: 1, curve: .easeIn(duration: 0.3))],
                bubbleDelay: 0.3,
                usesMotion: true,
                rest: rest
            )
        case .minimal:
            return AnimationPlan(
                initial: MotionPose(hidden: 1, opacity: 0, curve: .easeOut(duration: 0)),
                entrance: [MotionPose(hidden: restingHidden, curve: .easeOut(duration: 0.25))],
                celebration: [],
                exit: [MotionPose(hidden: 1, opacity: 0, curve: .easeIn(duration: 0.2))],
                bubbleDelay: 0.1,
                usesMotion: true,
                rest: rest
            )
        }
    }
}

// MARK: - Character lifecycle

public enum CharacterPhase: String, Equatable, Sendable {
    case hidden
    case entering
    /// Peeking with the speech bubble.
    case presented
    /// The user is composing a reply.
    case expanded
    case sending
    case celebrating
    case exiting
}

public enum CharacterInput: Equatable, Sendable {
    case present
    case expand
    case collapse
    case beginSend
    case sendFailed
    case sendSucceeded
    /// Answered elsewhere, withdrawn, snoozed or dismissed.
    case leave
    case animationFinished
}

/// The lifecycle of the on-screen character. Invalid inputs are ignored and
/// reported, so a late callback can never put the UI in an impossible state.
public struct CharacterStateMachine: Equatable, Sendable {
    public private(set) var phase: CharacterPhase = .hidden

    public init() {}

    public var isVisible: Bool { phase != .hidden }

    @discardableResult
    public mutating func handle(_ input: CharacterInput) -> Bool {
        guard let next = transition(from: phase, on: input) else { return false }
        phase = next
        return true
    }

    func transition(from phase: CharacterPhase, on input: CharacterInput) -> CharacterPhase? {
        switch (phase, input) {
        case (.hidden, .present), (.exiting, .present): return .entering
        case (.entering, .present), (.presented, .present), (.expanded, .present): return phase
        case (.entering, .animationFinished): return .presented
        case (.presented, .expand), (.entering, .expand): return .expanded
        case (.expanded, .collapse): return .presented
        case (.presented, .beginSend), (.expanded, .beginSend): return .sending
        case (.sending, .sendFailed): return .expanded
        case (.sending, .sendSucceeded): return .celebrating
        case (.celebrating, .animationFinished): return .exiting
        case (.entering, .leave), (.presented, .leave), (.expanded, .leave), (.sending, .leave): return .exiting
        case (.celebrating, .leave): return .celebrating
        case (.exiting, .animationFinished): return .hidden
        case (.exiting, .leave): return .exiting
        default: return nil
        }
    }
}
