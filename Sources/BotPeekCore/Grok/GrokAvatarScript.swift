import Foundation

public enum GrokAvatarScriptError: Error, Equatable, Sendable {
    case rendererNotFound
    case unsupportedImport(String)
    case runtimeNotFound(String)
}

/// Adapts Grok Bot's avatar renderer, read from its installed `app.asar`, so
/// it can run in a bare JavaScript engine.
///
/// Grok Bot draws every avatar in code: one renderer module turns a scene
/// (shape, pose, eyes) and a palette into an SVG string. That module is a
/// minified ES module whose only import is the bundler's small runtime chunk.
/// This type rewrites both into one classic script that evaluates to
/// `{ render, alias, gradients }`. Names are minified and change between
/// Grok Bot releases, so the functions are found by the shape of their code,
/// not by name; when that fails BotPeek keeps drawing its own avatars.
///
/// Nothing is copied into BotPeek: the code is read from the user's own
/// Grok Bot install each time BotPeek starts.
public struct GrokAvatarScript: Equatable, Sendable {
    public static let assetsDirectory = "dist/renderer/assets/"

    /// The renderer: `(scene, palette, size, id, options) -> svg string`.
    static let renderPattern = #"function ([\w$]+)\(e,t,n,r,i=\{\}\)\{return [\w$]+\([\w$]+\(e,t,n,r,i\)\)\}"#
    /// Maps picker shape names to renderer body names (`blob` -> `sphere`).
    static let aliasPattern = #"function ([\w$]+)\(e\)\{switch\(e\)\{case`blob`:return`sphere`"#
    /// The per-color body gradient table.
    static let gradientPattern = #"([\w$]+)=\{black:\{lightFrom:"#
    /// Marks the module that holds the renderer, so only it is read in full.
    public static let rendererMarker = "viewBox:`0 0 ${"

    public let source: String
    public let modulePath: String

    /// Finds the renderer module among the archive's renderer assets.
    /// Likely names are tried first so a normal install reads one or two files.
    public static func locate(in archive: AsarArchive) throws -> GrokAvatarScript {
        let candidates = archive.entries.keys
            .filter { $0.hasPrefix(assetsDirectory) && $0.hasSuffix(".js") }
            .sorted { lhs, rhs in
                let l = lhs.contains("eager-common"), r = rhs.contains("eager-common")
                return l != r ? l : lhs < rhs
            }
        for path in candidates {
            guard let module = try? archive.readString(path),
                  module.contains(rendererMarker),
                  firstMatch(renderPattern, in: module) != nil
            else { continue }
            return try make(module: module, modulePath: path) { name in
                try archive.readString(assetsDirectory + name)
            }
        }
        throw GrokAvatarScriptError.rendererNotFound
    }

    /// Rewrites `module` (and the chunks it imports, via `loadChunk`) into one script.
    public static func make(module: String, modulePath: String, loadChunk: (String) throws -> String) throws -> GrokAvatarScript {
        guard let render = firstMatch(renderPattern, in: module) else { throw GrokAvatarScriptError.rendererNotFound }
        let alias = firstMatch(aliasPattern, in: module)
        let gradients = firstMatch(gradientPattern, in: module)

        var body = module
        var prelude: [String] = []
        for statement in matches(#"import\{([^}]*)\}from"\./([\w.\-]+\.js)";?"#, in: module) {
            let (specifiers, file) = (statement.groups[0], statement.groups[1])
            guard file.hasPrefix("chunk-rolldown-runtime") else { throw GrokAvatarScriptError.unsupportedImport(file) }
            let runtime: String
            do { runtime = try loadChunk(file) } catch { throw GrokAvatarScriptError.runtimeNotFound(file) }
            let runtimeVar = "__botpeekRuntime\(prelude.count)"
            prelude.append("const \(runtimeVar)=(function(){\"use strict\";\(exportsToReturn(runtime))})();")
            for specifier in specifiers.split(separator: ",") {
                let parts = specifier.components(separatedBy: " as ")
                let exported = parts[0].trimmingCharacters(in: .whitespaces)
                let local = (parts.count > 1 ? parts[1] : parts[0]).trimmingCharacters(in: .whitespaces)
                prelude.append("const \(local)=\(runtimeVar).\(exported);")
            }
            body = body.replacingOccurrences(of: statement.whole, with: "")
        }
        if let anyImport = firstMatch(#"import\s*(\{[^}]*\}|\*\s*as\s+[\w$]+|[\w$]+)\s*from\s*["']"#, in: body) {
            throw GrokAvatarScriptError.unsupportedImport(anyImport)
        }
        body = removeExports(body)
        let result = "return{render:\(render),alias:\(alias ?? "null"),gradients:\(gradients ?? "null")};"
        let source = "(function(){\"use strict\";\(prelude.joined())\n\(body)\n;\(result)})()"
        return GrokAvatarScript(source: source, modulePath: modulePath)
    }

    /// `export{a as b,c as d};` becomes `return{b:a,d:c};`.
    static func exportsToReturn(_ module: String) -> String {
        var text = module
        for statement in matches(#"export\{([^}]*)\};?"#, in: module) {
            let pairs = statement.groups[0].split(separator: ",").map { specifier -> String in
                let parts = specifier.components(separatedBy: " as ")
                let local = parts[0].trimmingCharacters(in: .whitespaces)
                let exported = (parts.count > 1 ? parts[1] : parts[0]).trimmingCharacters(in: .whitespaces)
                return "\"\(exported)\":\(local)"
            }
            text = text.replacingOccurrences(of: statement.whole, with: "return{\(pairs.joined(separator: ","))};")
        }
        return text
    }

    static func removeExports(_ module: String) -> String {
        var text = module
        for statement in matches(#"export\{[^}]*\};?"#, in: module) {
            text = text.replacingOccurrences(of: statement.whole, with: "")
        }
        return text
    }

    // MARK: - Scene

    /// A JavaScript expression that renders one avatar, evaluated against the
    /// object the script returns (bound as `g`). Shape and color names come
    /// from Grok Bot's roster, so they are passed as JSON string literals.
    public static func renderCall(shape: AvatarShape, color: AvatarColor, isHappy: Bool, id: String, size: Int = 256) -> String {
        let body = jsonString(shape.grokName)
        let paint = jsonString("url(#\(id)-ink)")
        let eye = isHappy
            ? "{oval:[0.15,0.17],off:[0,0.02],lidY:1,tilt:0,wid:0,ovalMix:1,pts:[]}"
            : "{oval:[0.13,0.285],off:[0,0],lidY:1,tilt:0,wid:0,ovalMix:1,pts:[]}"
        return """
        (function(){var b=\(body);var e=\(eye);\
        var s={bodies:[{body:(g.alias?g.alias(b):b),weight:1}],quat:[0,0,0,1],zoom:0.8,offset:[0,0],\
        squash:[1,1],squashAnchor:0,eyes:[e,e],glow:null};\
        var p={ink:[0,0,0],spot:[0,0,0],cutout:false,inkPaint:\(paint),spotPaint:"#FFFFFF"};\
        return g.render(s,p,\(size),\(jsonString(id)));})()
        """
    }

    /// A JavaScript expression returning `[from, to]` hex strings for a color
    /// from Grok Bot's own gradient table, or `null`.
    public static func gradientCall(color: AvatarColor) -> String {
        let name = jsonString(color.name)
        return "(function(){var t=g.gradients&&g.gradients[\(name)];return t?[t.lightFrom,t.lightTo]:null;})()"
    }

    /// Adds the body gradient the render call refers to (`url(#id-ink)`).
    public static func injectGradient(into svg: String, id: String, from: String, to: String) -> String {
        let gradient = "<linearGradient id=\"\(id)-ink\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\">"
            + "<stop offset=\"0\" stop-color=\"\(from)\"/><stop offset=\"1\" stop-color=\"\(to)\"/></linearGradient>"
        if let range = svg.range(of: "<defs>") {
            return svg.replacingCharacters(in: range, with: "<defs>" + gradient)
        }
        // Some bodies (the sphere) have no <defs>; add one after the <svg …> tag.
        guard svg.hasPrefix("<svg"), let tagEnd = svg.firstIndex(of: ">") else {
            return svg.replacingOccurrences(of: "url(#\(id)-ink)", with: from)
        }
        var out = svg
        out.insert(contentsOf: "<defs>" + gradient + "</defs>", at: out.index(after: tagEnd))
        return out
    }

    public static func hex(_ rgb: UInt32) -> String {
        let hex = String(rgb, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: max(0, 6 - hex.count)) + hex
    }

    /// Accepts only `#RRGGBB` so values from Grok Bot's table can't inject markup.
    public static func isHexColor(_ value: String) -> Bool {
        firstMatch(#"^#[0-9A-Fa-f]{6}$"#, in: value) != nil
    }

    static func jsonString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value], options: [])) ?? Data("[\"\"]".utf8)
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }

    // MARK: - Regex helpers

    struct Match {
        var whole: String
        var groups: [String]
    }

    static func matches(_ pattern: String, in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { result in
            Match(
                whole: ns.substring(with: result.range),
                groups: (1..<max(1, result.numberOfRanges)).map { index in
                    let range = result.range(at: index)
                    return range.location == NSNotFound ? "" : ns.substring(with: range)
                }
            )
        }
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let match = matches(pattern, in: text).first else { return nil }
        return match.groups.first ?? match.whole
    }
}
