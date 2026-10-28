import Foundation

/// The built-in avatar shapes BotPeek knows how to draw.
///
/// Grok Bot stores a shape *name* per bot. BotPeek draws its own vector version
/// of each named shape in the bot's color; the artwork is not copied from
/// Grok Bot, so it is a faithful match of shape and color, not a pixel copy.
public enum AvatarShape: String, Codable, CaseIterable, Sendable {
    case classic
    case wedge
    case cloud
    case square
    case sparkle
    case clover
    case flower
    case heart
    case star
    case teardrop
    case egg
    case capsule
    case house
    case hexagon
    case gem
    case pebble
    case circle

    /// Shape names observed in Grok Bot's roster, mapped to a drawable shape.
    static let aliases: [String: AvatarShape] = [
        "": .classic, "default": .classic, "grokbot": .classic, "blob": .classic,
        "wedge": .wedge,
        "cloud": .cloud,
        "square": .square, "rounded-square": .square, "roundedsquare": .square,
        "sparkle": .sparkle,
        "clover": .clover,
        "flower": .flower,
        "heart": .heart, "heartchubby": .heart,
        "star": .star, "starflower": .star, "star6": .star,
        "teardrop": .teardrop,
        "egg": .egg,
        "capsule": .capsule, "tablet": .capsule, "pill": .capsule,
        "house": .house,
        "hex": .hexagon, "hexagon": .hexagon,
        "gem": .gem, "crystal": .gem,
        "pebble": .pebble,
        "circle": .circle, "sphere": .circle, "dot": .circle,
    ]

    /// Returns the shape for a stored name and whether the name was recognized.
    public static func resolve(_ rawName: String?) -> (shape: AvatarShape, recognized: Bool) {
        let key = (rawName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        if let shape = aliases[key] ?? aliases[key.replacingOccurrences(of: "-", with: "")] {
            return (shape, true)
        }
        return (.classic, false)
    }
}

/// A bot's avatar color as an sRGB value.
public struct AvatarColor: Equatable, Hashable, Codable, Sendable {
    public let name: String
    /// 0xRRGGBB in sRGB.
    public let rgb: UInt32
    public let isRecognized: Bool

    public var red: Double { Double((rgb >> 16) & 0xff) / 255 }
    public var green: Double { Double((rgb >> 8) & 0xff) / 255 }
    public var blue: Double { Double(rgb & 0xff) / 255 }

    public var hexString: String {
        let hex = String(rgb, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: 6 - hex.count) + hex
    }

    /// Relative luminance, used to pick legible face/eye colors.
    public var isLight: Bool {
        (0.299 * red + 0.587 * green + 0.114 * blue) > 0.7
    }

    static let palette: [String: UInt32] = [
        "red": 0xFF453A,
        "orange": 0xFF9F0A,
        "yellow": 0xFFD60A,
        "green": 0x30D158,
        "mint": 0x63E6E2,
        "teal": 0x40C8E0,
        "cyan": 0x64D2FF,
        "blue": 0x0A84FF,
        "indigo": 0x5E5CE6,
        "purple": 0xBF5AF2,
        "pink": 0xFF375F,
        "brown": 0xAC8E68,
        "gray": 0x8E8E93,
        "grey": 0x8E8E93,
        "black": 0x1C1C1E,
        "white": 0xF2F2F7,
    ]

    /// Used when the roster stores no color. Orange is what other community
    /// tools observed for unset colors; unverified against Grok Bot itself.
    public static let defaultColor = AvatarColor(name: "orange", rgb: 0xFF9F0A, isRecognized: true)

    public init(name: String, rgb: UInt32, isRecognized: Bool) {
        self.name = name
        self.rgb = rgb
        self.isRecognized = isRecognized
    }

    public static func resolve(_ rawName: String?) -> AvatarColor {
        let name = (rawName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.isEmpty { return defaultColor }
        if let rgb = palette[name] { return AvatarColor(name: name, rgb: rgb, isRecognized: true) }
        if let rgb = parseHex(name) { return AvatarColor(name: name, rgb: rgb, isRecognized: true) }
        return AvatarColor(name: name, rgb: 0x8E8E93, isRecognized: false)
    }

    static func parseHex(_ value: String) -> UInt32? {
        var hex = value
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let number = UInt32(hex, radix: 16) else { return nil }
        return number
    }
}

/// How a bot looks in Grok Bot, as recorded in its local roster.
public struct AvatarDescriptor: Equatable, Hashable, Codable, Sendable {
    /// The shape name exactly as stored by Grok Bot (for diagnostics).
    public var rawShape: String?
    /// The color name exactly as stored by Grok Bot (for diagnostics).
    public var rawColor: String?
    /// Key of an uploaded profile image in Grok Bot's avatar cache.
    /// Validated to 32 lowercase hex characters, so it can never escape the cache folder.
    public var photoKey: String?

    public init(rawShape: String? = nil, rawColor: String? = nil, photoKey: String? = nil) {
        self.rawShape = rawShape
        self.rawColor = rawColor
        self.photoKey = photoKey.flatMap(Self.validatedPhotoKey)
    }

    public var shape: AvatarShape { AvatarShape.resolve(rawShape).shape }
    public var isShapeRecognized: Bool { AvatarShape.resolve(rawShape).recognized }
    public var color: AvatarColor { AvatarColor.resolve(rawColor) }

    public static func validatedPhotoKey(_ key: String) -> String? {
        let allowed = Set("0123456789abcdef")
        guard key.count == 32, key.allSatisfy({ allowed.contains($0) }) else { return nil }
        return key
    }
}
