import Foundation

/// The built-in avatar shapes BotPeek knows how to draw.
///
/// Grok Bot stores a shape *name* per bot. When Grok Bot is installed, BotPeek
/// renders that name with Grok Bot's own avatar code (see `grokBodyName`).
/// Otherwise it falls back to its own vector version of the shape in the
/// bot's color; that artwork is not copied from Grok Bot.
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
    case bean
    case squircle
    case tablet
    case cylinder
    case crystal
    case shield
    case dome
    case arch
    case leaf
    case pumpkin

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
        "capsule": .capsule, "pill": .capsule,
        "house": .house,
        "hex": .hexagon, "hexagon": .hexagon,
        "gem": .gem,
        "pebble": .pebble,
        "circle": .circle, "sphere": .circle, "dot": .circle,
        "bean": .bean,
        "squircle": .squircle,
        "tablet": .tablet,
        "cylinder": .cylinder,
        "crystal": .crystal,
        "shield": .shield,
        "dome": .dome,
        "arch": .arch,
        "leaf": .leaf,
        "pumpkin": .pumpkin,
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

    /// The shape's name in Grok Bot's avatar picker, as stored in the roster.
    public var grokName: String {
        switch self {
        case .classic, .circle: return "blob"
        case .hexagon: return "hex"
        default: return rawValue
        }
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

    /// Grok Bot's avatar colors (its color picker's swatch values).
    static let palette: [String: UInt32] = [
        "black": 0x000000,
        "brown": 0x936439,
        "red": 0xFF263C,
        "orange": 0xFF6700,
        "yellow": 0xFF9800,
        "green": 0x00C972,
        "cyan": 0x00BCA6,
        "blue": 0x1084FE,
        "violet": 0x9159FE,
        "magenta": 0xFF309B,
        "gray": 0x777777,
    ]

    /// Other color names, mapped to the nearest Grok Bot color.
    static let aliases: [String: String] = [
        "grey": "gray", "white": "gray", "silver": "gray",
        "purple": "violet", "indigo": "violet",
        "pink": "magenta",
        "teal": "cyan", "mint": "cyan",
    ]

    /// Grok Bot's two-stop body gradient per color, (top-left, bottom-right) in
    /// light appearance. Used when Grok Bot's own table can't be read.
    static let gradients: [String: (from: UInt32, to: UInt32)] = [
        "black": (0x585858, 0x000000),
        "brown": (0xAE8968, 0x855C36),
        "red": (0xFF5667, 0xE02135),
        "orange": (0xFF8838, 0xE05B00),
        "yellow": (0xFFAF38, 0xE08600),
        "green": (0x1CCF82, 0x009957),
        "cyan": (0x58D3C5, 0x00A592),
        "blue": (0x459FFE, 0x0E74E0),
        "violet": (0xB792FE, 0x804EE0),
        "magenta": (0xFF77BE, 0xE02A88),
        "gray": (0xA6A6A6, 0x696969),
    ]

    /// Used when the roster stores no color. Orange is what other community
    /// tools observed for unset colors; unverified against Grok Bot itself.
    public static let defaultColor = AvatarColor(name: "orange", rgb: 0xFF6700, isRecognized: true)

    /// The body gradient for this color: Grok Bot's when it is one of Grok
    /// Bot's colors, otherwise a flat fill.
    public var gradient: (from: UInt32, to: UInt32) {
        Self.gradients[name] ?? (rgb, rgb)
    }

    public init(name: String, rgb: UInt32, isRecognized: Bool) {
        self.name = name
        self.rgb = rgb
        self.isRecognized = isRecognized
    }

    public static func resolve(_ rawName: String?) -> AvatarColor {
        let name = (rawName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.isEmpty { return defaultColor }
        let canonical = aliases[name] ?? name
        if let rgb = palette[canonical] { return AvatarColor(name: canonical, rgb: rgb, isRecognized: true) }
        if let rgb = parseHex(name) { return AvatarColor(name: name, rgb: rgb, isRecognized: true) }
        return AvatarColor(name: name, rgb: 0x777777, isRecognized: false)
    }

    /// Parses `#RRGGBB`.
    public static func parseHexColor(_ value: String) -> UInt32? { parseHex(value) }

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
