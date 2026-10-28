#if canImport(AppKit)
import AppKit
import SwiftUI
import BotPeekCore

/// Loads uploaded profile images from Grok Bot's avatar cache, read-only.
@MainActor
final class AvatarImageCache {
    static let shared = AvatarImageCache()

    struct Entry {
        let image: NSImage
        let hasTransparency: Bool
        let modified: Date?
    }

    private var entries: [URL: Entry] = [:]

    func image(at url: URL) -> Entry? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let cached = entries[url], cached.modified == modified { return cached }
        guard let image = NSImage(contentsOf: url), image.isValid else { return nil }
        let entry = Entry(image: image, hasTransparency: Self.hasTransparentCorners(image), modified: modified)
        entries[url] = entry
        return entry
    }

    /// Transparent images keep their own outline instead of a circular crop.
    static func hasTransparentCorners(_ image: NSImage) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        switch cgImage.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let maxX = bitmap.pixelsWide - 1
        let maxY = bitmap.pixelsHigh - 1
        guard maxX > 0, maxY > 0 else { return false }
        return [(0, 0), (maxX, 0), (0, maxY), (maxX, maxY)].contains { point in
            (bitmap.colorAt(x: point.0, y: point.1)?.alphaComponent ?? 1) < 0.5
        }
    }
}

/// Draws a bot exactly as configured in Grok Bot: its uploaded image when
/// available, otherwise its built-in shape in its color.
struct BotAvatarView: View {
    let source: AvatarSource
    var size: CGFloat = 72
    var isHappy = false
    var showsShadow = true

    var body: some View {
        content
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(showsShadow ? 0.22 : 0), radius: size * 0.08, x: 0, y: size * 0.04)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch source {
        case .photo(let url):
            if let entry = AvatarImageCache.shared.image(at: url) {
                if entry.hasTransparency {
                    Image(nsImage: entry.image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(nsImage: entry.image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: max(1, size * 0.02)))
                }
            } else {
                FallbackAvatar(size: size)
            }
        case .builtIn(let shape, let color), .photoUnavailable(let shape, let color):
            BuiltInAvatar(shape: shape, color: color, isHappy: isHappy)
        }
    }
}

struct BuiltInAvatar: View {
    let shape: AvatarShape
    let color: AvatarColor
    var isHappy = false

    var body: some View {
        let base = Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: 1)
        ZStack {
            AvatarSilhouette(shape: shape)
                .fill(base)
            // A soft top highlight for depth; the color itself is unchanged.
            AvatarSilhouette(shape: shape)
                .fill(LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center))
            AvatarFace(shape: shape, color: color, isHappy: isHappy)
        }
    }
}

/// Shown only when an uploaded image exists but can't be decoded.
struct FallbackAvatar: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(.quaternary)
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

extension BotAvatarView {
    /// A small rendered avatar for NSMenu items.
    @MainActor
    static func menuImage(source: AvatarSource, size: CGFloat = 18) -> NSImage? {
        let renderer = ImageRenderer(content: BotAvatarView(source: source, size: size, showsShadow: false))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }
}
#endif
