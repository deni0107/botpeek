import XCTest
@testable import BotPeekCore
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

/// A tiny stand-in for Grok Bot's renderer module, minified the same way.
private let runtimeChunk = #"var n=Object.create;var s=(e,t)=>()=>(t||e((t={exports:{}}).exports,t),t.exports);export{n as a,s as t};"#
private let rendererModule = """
!function(){try{var e=globalThis}catch(e){}}();
import{t as e}from"./chunk-rolldown-runtime-ABC123.js";var q=e;\
function i_(e){switch(e){case`blob`:return`sphere`;case`star`:return`star6`;default:return e}}\
var lr={black:{lightFrom:`#585858`,lightTo:`#000000`},blue:{lightFrom:`#459FFE`,lightTo:`#0E74E0`}};\
function mp(e){return{viewBox:`0 0 ${e} ${e}`}}function hp(e){return e}function Xg(e,t,n,r,i){var b=e.bodies[0].body;\
return`<svg xmlns="http://www.w3.org/2000/svg" id="${r}" width="${n}" height="${n}"><defs></defs><path data-body="${b}" fill="${t.inkPaint}"/><path fill="${t.spotPaint}"/></svg>`}\
function Yg(e,t,n,r,i={}){return hp(Xg(e,t,n,r,i))}\
export{Yg as O,i_ as E};
"""

final class GrokAvatarScriptTests: XCTestCase {
    func testAsarRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("app.asar")
        try AsarArchive.make(files: [
            "package.json": Data("{}".utf8),
            "dist/renderer/assets/a.js": Data("alpha".utf8),
            "dist/renderer/assets/b.js": Data("bravo!".utf8),
        ]).write(to: url)

        let archive = try AsarArchive(url: url)
        XCTAssertEqual(Set(archive.entries.keys), ["package.json", "dist/renderer/assets/a.js", "dist/renderer/assets/b.js"])
        XCTAssertEqual(try archive.readString("dist/renderer/assets/b.js"), "bravo!")
        XCTAssertEqual(try archive.readString("package.json"), "{}")
        XCTAssertThrowsError(try archive.read("missing.js"))
    }

    func testRejectsNonArchive() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("not-asar-\(UUID().uuidString)")
        try Data("hello, not an archive".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try AsarArchive(url: url))
    }

    func testRewritesModuleIntoClassicScript() throws {
        var requested: [String] = []
        let script = try GrokAvatarScript.make(module: rendererModule, modulePath: "x.js") { name in
            requested.append(name)
            return runtimeChunk
        }
        XCTAssertEqual(requested, ["chunk-rolldown-runtime-ABC123.js"])
        XCTAssertFalse(script.source.contains("import{"))
        XCTAssertFalse(script.source.contains("export{"))
        XCTAssertTrue(script.source.contains("return{render:Yg,alias:i_,gradients:lr}"))
    }

    func testLocatesRendererInArchive() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("asar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("app.asar")
        try AsarArchive.make(files: [
            "dist/renderer/assets/other-1.js": Data("export{};".utf8),
            "dist/renderer/assets/index.eager-common-XYZ.js": Data(rendererModule.utf8),
            "dist/renderer/assets/chunk-rolldown-runtime-ABC123.js": Data(runtimeChunk.utf8),
        ]).write(to: url)
        let script = try GrokAvatarScript.locate(in: try AsarArchive(url: url))
        XCTAssertEqual(script.modulePath, "dist/renderer/assets/index.eager-common-XYZ.js")
    }

    func testRefusesModulesWithOtherImports() {
        let module = #"import{x as y}from"./react-123.js";function Yg(e,t,n,r,i={}){return hp(Xg(e,t,n,r,i))}viewBox:`0 0 ${"#
        XCTAssertThrowsError(try GrokAvatarScript.make(module: module, modulePath: "x.js") { _ in "" }) { error in
            XCTAssertEqual(error as? GrokAvatarScriptError, .unsupportedImport("react-123.js"))
        }
    }

    func testMissingRendererIsReported() {
        XCTAssertThrowsError(try GrokAvatarScript.make(module: "var a=1;", modulePath: "x.js") { _ in "" }) { error in
            XCTAssertEqual(error as? GrokAvatarScriptError, .rendererNotFound)
        }
    }

    func testGradientInjectionAndColorValidation() {
        let svg = ##"<svg><defs><mask/></defs><path fill="url(#a-ink)"/></svg>"##
        let out = GrokAvatarScript.injectGradient(into: svg, id: "a", from: "#111111", to: "#222222")
        XCTAssertTrue(out.hasPrefix(#"<svg><defs><linearGradient id="a-ink""#))
        XCTAssertTrue(out.contains(##"stop-color="#222222""##))
        let bare = GrokAvatarScript.injectGradient(into: ##"<svg id="a"><path fill="url(#a-ink)"/></svg>"##, id: "a", from: "#111111", to: "#222222")
        XCTAssertTrue(bare.hasPrefix(##"<svg id="a"><defs><linearGradient"##), "an SVG without <defs> still gets the gradient")
        XCTAssertTrue(GrokAvatarScript.isHexColor("#9159FE"))
        XCTAssertFalse(GrokAvatarScript.isHexColor(##"#fff"/><script"##))
        XCTAssertEqual(GrokAvatarScript.hex(0x00C972), "#00C972")
    }

    func testRenderCallQuotesRosterValues() {
        let call = GrokAvatarScript.renderCall(shape: .pumpkin, color: .defaultColor, isHappy: false, id: "a\"b")
        XCTAssertTrue(call.contains(#"var b="pumpkin""#))
        XCTAssertTrue(call.contains(#""a\"b""#), "ids are JSON-escaped, never spliced raw")
    }

    #if canImport(JavaScriptCore)
    func testRunsInJavaScriptCore() throws {
        let script = try GrokAvatarScript.make(module: rendererModule, modulePath: "x.js") { _ in runtimeChunk }
        let context = try XCTUnwrap(JSContext())
        let engine = context.evaluateScript(script.source)
        XCTAssertNil(context.exception)
        context.setObject(engine, forKeyedSubscript: "g" as NSString)

        let blue = AvatarColor.resolve("blue")
        let svg = context.evaluateScript(GrokAvatarScript.renderCall(shape: .classic, color: blue, isHappy: false, id: "t"))?.toString()
        XCTAssertNil(context.exception)
        XCTAssertTrue(svg?.contains(#"data-body="sphere""#) == true, "Grok Bot's alias maps blob to its sphere body")
        XCTAssertTrue(svg?.contains(##"fill="url(#t-ink)""##) == true)

        let star = context.evaluateScript(GrokAvatarScript.renderCall(shape: .star, color: blue, isHappy: false, id: "t"))?.toString()
        XCTAssertTrue(star?.contains(#"data-body="star6""#) == true)

        let stops = context.evaluateScript(GrokAvatarScript.gradientCall(color: blue))?.toArray() as? [String]
        XCTAssertEqual(stops, ["#459FFE", "#0E74E0"])
    }
    #endif
}
