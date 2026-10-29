import Foundation

public enum AsarError: Error, Equatable, Sendable {
    case unreadable
    case badHeader
    case fileNotFound(String)
}

/// Read-only access to an Electron `app.asar` archive.
///
/// Layout: a 16-byte Chromium pickle prefix (`4`, header size, payload size,
/// JSON length), the JSON index, then file contents. Each file entry gives a
/// `size` and an `offset` (a decimal string) relative to the end of the header.
/// Only the index and the files asked for are read, never the whole archive.
public final class AsarArchive: @unchecked Sendable {
    public static let maximumHeaderSize = 16 * 1_024 * 1_024
    public static let maximumFileSize = 32 * 1_024 * 1_024

    public struct Entry: Equatable, Sendable {
        public var path: String
        public var size: Int
        public var offset: UInt64
    }

    public let url: URL
    /// Packed files by path, without a leading slash (`dist/renderer/…`).
    public let entries: [String: Entry]
    private let contentBase: UInt64

    public init(url: URL) throws {
        self.url = url
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw AsarError.unreadable }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 16), prefix.count == 16 else { throw AsarError.badHeader }
        let headerSize = Int(Self.uint32(prefix, at: 4))
        let jsonLength = Int(Self.uint32(prefix, at: 12))
        guard jsonLength > 0, jsonLength <= Self.maximumHeaderSize, jsonLength + 8 <= headerSize + 8,
              let json = try? handle.read(upToCount: jsonLength), json.count == jsonLength,
              let root = try? JSONValue.parse(json)
        else { throw AsarError.badHeader }
        contentBase = UInt64(8 + headerSize)
        var entries: [String: Entry] = [:]
        Self.collect(root, prefix: "", into: &entries)
        self.entries = entries
    }

    public func read(_ path: String) throws -> Data {
        guard let entry = entries[path], entry.size <= Self.maximumFileSize else { throw AsarError.fileNotFound(path) }
        let start = contentBase + entry.offset
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw AsarError.unreadable }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: start)
            guard let data = try handle.read(upToCount: entry.size), data.count == entry.size else { throw AsarError.unreadable }
            return data
        } catch {
            throw AsarError.unreadable
        }
    }

    public func readString(_ path: String) throws -> String {
        guard let text = String(data: try read(path), encoding: .utf8) else { throw AsarError.unreadable }
        return text
    }

    private static func collect(_ node: JSONValue, prefix: String, into entries: inout [String: Entry]) {
        guard case .object(let files)? = node["files"] else { return }
        for (name, child) in files {
            guard !name.contains("/"), name != "..", name != "." else { continue }
            let path = prefix.isEmpty ? name : prefix + "/" + name
            if child["files"] != nil {
                collect(child, prefix: path, into: &entries)
            } else if child["unpacked"]?.boolValue != true,
                      let size = child["size"]?.numberValue, size >= 0,
                      let offset = child["offset"]?.stringValue.flatMap({ UInt64($0) }) {
                entries[path] = Entry(path: path, size: Int(size), offset: offset)
            }
        }
    }

    private static func uint32(_ data: Data, at index: Int) -> UInt32 {
        data.subdata(in: index..<(index + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
    }

    /// Builds an archive in memory, for tests.
    public static func make(files: [String: Data]) -> Data {
        var tree: [String: Any] = [:]
        var body = Data()
        for path in files.keys.sorted() {
            let data = files[path]!
            var node = tree
            let parts = path.split(separator: "/").map(String.init)
            func insert(_ parts: ArraySlice<String>, into dict: inout [String: Any]) {
                let name = parts.first!
                if parts.count == 1 {
                    dict[name] = ["size": data.count, "offset": String(body.count)]
                } else {
                    var dir = (dict[name] as? [String: Any]) ?? ["files": [String: Any]()]
                    var children = (dir["files"] as? [String: Any]) ?? [:]
                    insert(parts.dropFirst(), into: &children)
                    dir["files"] = children
                    dict[name] = dir
                }
            }
            insert(parts[...], into: &node)
            tree = node
            body.append(data)
        }
        let json = try! JSONSerialization.data(withJSONObject: ["files": tree], options: [.sortedKeys])
        let padded = (json.count + 3) / 4 * 4
        func le(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        var out = Data()
        out.append(le(4))
        out.append(le(padded + 8))
        out.append(le(padded + 4))
        out.append(le(json.count))
        out.append(json)
        out.append(Data(count: padded - json.count))
        out.append(body)
        return out
    }
}
