import XCTest
@testable import BotPeekCore

final class RosterParserTests: XCTestCase {
    func testParsesIdentitiesAndSkipsUnusableRows() throws {
        let result = try RosterParser.parse(Fixture.data("roster-v4.json"))
        XCTAssertEqual(result.schemaVersion, 4)
        XCTAssertTrue(result.isKnownSchema)
        XCTAssertEqual(result.bots.map(\.name), ["Research Bot", "Writer", "Ops Bot", "Archived Helper", "Path Trick", "Numeric Id Bot"])
        XCTAssertEqual(result.skippedRows, 3, "rows without an id or a name are skipped")
    }

    func testReadsBuiltInAvatarAndPhotoKey() throws {
        let bots = try RosterParser.parse(Fixture.data("roster-v4.json")).bots
        let research = try XCTUnwrap(bots.first { $0.id == BotID("bot-research") })
        XCTAssertEqual(research.identity.avatar.shape, .cloud)
        XCTAssertEqual(research.identity.avatar.color.name, "blue")
        XCTAssertNil(research.identity.avatar.photoKey)

        let writer = try XCTUnwrap(bots.first { $0.id == BotID("bot-writer") })
        XCTAssertEqual(writer.identity.avatar.photoKey, "0123456789abcdef0123456789abcdef")
        XCTAssertEqual(writer.identity.avatar.shape, .heart, "heartchubby maps to the heart shape")
    }

    func testRejectsPathTraversalInPhotoKey() throws {
        let bots = try RosterParser.parse(Fixture.data("roster-v4.json")).bots
        let trick = try XCTUnwrap(bots.first { $0.name == "Path Trick" })
        XCTAssertNil(trick.identity.avatar.photoKey)
    }

    func testEmptyOrFalseAwaitingPayloadIsNotAttention() throws {
        let bots = try RosterParser.parse(Fixture.data("roster-v4.json")).bots
        XCTAssertNil(bots.first { $0.name == "Path Trick" }?.awaitingUserResponse, "{} is not a request")
        XCTAssertNil(bots.first { $0.name == "Numeric Id Bot" }?.awaitingUserResponse, "false is not a request")
        XCTAssertNil(bots.first { $0.name == "Writer" }?.awaitingUserResponse, "null is not a request")
        XCTAssertNotNil(bots.first { $0.name == "Research Bot" }?.awaitingUserResponse)
    }

    func testNumericIdsAndTimestamps() throws {
        let bots = try RosterParser.parse(Fixture.data("roster-v4.json")).bots
        XCTAssertEqual(bots.first { $0.name == "Numeric Id Bot" }?.id, BotID("42"))
        XCTAssertEqual(bots.first { $0.name == "Research Bot" }?.lastActivity, Date(timeIntervalSince1970: 1_730_000_000))
        XCTAssertEqual(bots.first { $0.name == "Writer" }?.lastActivity, Date(timeIntervalSince1970: 1_730_000_100))
    }

    func testChangedFormatIsFlaggedNotFatal() throws {
        let result = try RosterParser.parse(Fixture.data("roster-v9-changed.json"))
        XCTAssertFalse(result.isKnownSchema)
        XCTAssertEqual(result.bots.count, 1)
        XCTAssertNil(result.bots[0].awaitingUserResponse, "unknown fields are never guessed to be requests")
        XCTAssertEqual(result.bots[0].identity.avatar.shape, .classic)
    }

    func testMalformedInput() {
        XCTAssertThrowsError(try RosterParser.parse(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? RosterParseError, .notJSON)
        }
        XCTAssertThrowsError(try RosterParser.parse(Data(#"{"schemaVersion":4,"value":{}}"#.utf8))) { error in
            XCTAssertEqual(error as? RosterParseError, .missingRows)
        }
    }
}

final class Base32Tests: XCTestCase {
    func testRoundTripAndKnownVector() {
        XCTAssertEqual(Base32.decodeKey(fileName: "mzxw6"), "foo")
        let key = "user_123.roster.last-roster"
        XCTAssertEqual(Base32.decodeKey(fileName: Base32.encode(Data(key.utf8))), key)
        XCTAssertNil(Base32.decode("not base32!"))
    }
}

final class RosterStoreTests: XCTestCase {
    func testMissingGrokBotFolder() {
        let paths = GrokBotPaths(supportDirectory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        XCTAssertThrowsError(try RosterStore(paths: paths).load()) { error in
            XCTAssertEqual(error as? RosterStoreError, .grokBotDataMissing)
        }
    }

    func testNoRosterYet() throws {
        let folder = try TemporaryGrokFolder()
        try folder.writeBlob(key: "user.settings.theme", data: Data("{}".utf8))
        XCTAssertThrowsError(try RosterStore(paths: folder.paths).load()) { error in
            XCTAssertEqual(error as? RosterStoreError, .rosterNotFound)
        }
    }

    func testPicksNewestRosterAmongAccounts() throws {
        let folder = try TemporaryGrokFolder()
        let old = #"{"schemaVersion":4,"value":{"rows":[{"id":"a","name":"Old Account Bot"}]}}"#
        let new = #"{"schemaVersion":4,"value":{"rows":[{"id":"b","name":"Current Bot"}]}}"#
        try folder.writeBlob(key: "account-1.roster.last-roster", data: Data(old.utf8), modified: date(1_000))
        try folder.writeBlob(key: "account-2.roster.last-roster", data: Data(new.utf8), modified: date(2_000))
        let snapshot = try RosterStore(paths: folder.paths).load()
        XCTAssertEqual(snapshot.bots.map(\.name), ["Current Bot"])
    }

    func testReloadsWhenFileChanges() throws {
        let folder = try TemporaryGrokFolder()
        let store = RosterStore(paths: folder.paths)
        let v1 = #"{"schemaVersion":4,"value":{"rows":[{"id":"a","name":"Bot","awaitingUserResponse":null}]}}"#
        try folder.writeBlob(key: "acct.roster.last-roster", data: Data(v1.utf8), modified: date(1_000))
        XCTAssertNil(try store.load().bots[0].awaitingUserResponse)

        let v2 = #"{"schemaVersion":4,"value":{"rows":[{"id":"a","name":"Bot","awaitingUserResponse":{"question":"Ok?"}}]}}"#
        try folder.writeBlob(key: "acct.roster.last-roster", data: Data(v2.utf8), modified: date(2_000))
        XCTAssertNotNil(try store.load().bots[0].awaitingUserResponse)
    }

    func testCorruptRosterReportsParseError() throws {
        let folder = try TemporaryGrokFolder()
        try folder.writeBlob(key: "acct.roster.last-roster", data: Data("{ truncated".utf8))
        XCTAssertThrowsError(try RosterStore(paths: folder.paths).load()) { error in
            XCTAssertEqual(error as? RosterStoreError, .parse(.notJSON))
        }
    }

    func testDesktopStatusRequiresLiveProcess() throws {
        let folder = try TemporaryGrokFolder()
        try Data(#"{"pid":4242,"signedIn":true,"appVersion":"1.2.3"}"#.utf8).write(to: folder.paths.desktopStatusFile)
        let alive = DesktopStatusReader(paths: folder.paths, isProcessAlive: { $0 == 4242 })
        XCTAssertEqual(alive.load(), DesktopStatus(pid: 4242, signedIn: true, appVersion: "1.2.3"))
        let dead = DesktopStatusReader(paths: folder.paths, isProcessAlive: { _ in false })
        XCTAssertNil(dead.load(), "a stale status file from a crashed app is ignored")
    }
}

final class AvatarTests: XCTestCase {
    func testShapeAliases() {
        XCTAssertEqual(AvatarShape.resolve("Cloud").shape, .cloud)
        XCTAssertEqual(AvatarShape.resolve("starflower").shape, .star)
        XCTAssertEqual(AvatarShape.resolve("tablet").shape, .tablet)
        XCTAssertEqual(AvatarShape.resolve("pumpkin").shape, .pumpkin)
        XCTAssertEqual(AvatarShape.resolve("blob").shape.grokName, "blob")
        XCTAssertEqual(AvatarShape.resolve("hex").shape.grokName, "hex")
        XCTAssertEqual(AvatarShape.resolve(nil).shape, .classic)
        XCTAssertTrue(AvatarShape.resolve(nil).recognized)
        let unknown = AvatarShape.resolve("mystery-shape")
        XCTAssertEqual(unknown.shape, .classic)
        XCTAssertFalse(unknown.recognized, "unknown shapes are reported, not silently claimed as matched")
    }

    func testColors() {
        XCTAssertEqual(AvatarColor.resolve("Blue").name, "blue")
        XCTAssertEqual(AvatarColor.resolve("#12AB34").rgb, 0x12AB34)
        XCTAssertEqual(AvatarColor.resolve(nil), .defaultColor)
        XCTAssertFalse(AvatarColor.resolve("chartreuse-ish").isRecognized)
        XCTAssertEqual(AvatarColor.resolve("#12AB34").hexString, "#12AB34")
        XCTAssertEqual(AvatarColor.resolve("violet").rgb, 0x9159FE, "Grok Bot's own violet, not a system purple")
        XCTAssertTrue(AvatarColor.resolve("violet").isRecognized)
        XCTAssertEqual(AvatarColor.resolve("purple").name, "violet")
        XCTAssertEqual(AvatarColor.resolve("blue").gradient.from, 0x459FFE)
        XCTAssertEqual(AvatarColor.resolve("#12AB34").gradient.to, 0x12AB34, "custom colors get a flat fill")
    }

    func testPhotoLookupAndFallback() throws {
        let folder = try TemporaryGrokFolder()
        let key = "0123456789abcdef0123456789abcdef"
        let withPhoto = AvatarDescriptor(rawShape: "cloud", rawColor: "blue", photoKey: key)

        XCTAssertEqual(
            AvatarResolver.resolve(withPhoto, paths: folder.paths),
            .photoUnavailable(shape: .cloud, color: AvatarColor.resolve("blue")),
            "a missing cached photo falls back to the built-in avatar and says so"
        )

        try folder.writeAvatar(key: key)
        XCTAssertEqual(
            AvatarResolver.resolve(withPhoto, paths: folder.paths),
            .photo(folder.paths.avatarsDirectory.appendingPathComponent(key))
        )

        let builtIn = AvatarDescriptor(rawShape: "square", rawColor: "green")
        XCTAssertEqual(AvatarResolver.resolve(builtIn, paths: folder.paths), .builtIn(shape: .square, color: AvatarColor.resolve("green")))
    }

    func testEmptyPhotoFileIsUnavailable() throws {
        let folder = try TemporaryGrokFolder()
        let key = "ffffffffffffffffffffffffffffffff"
        try folder.writeAvatar(key: key, bytes: 0)
        let avatar = AvatarDescriptor(photoKey: key)
        if case .photoUnavailable = AvatarResolver.resolve(avatar, paths: folder.paths) {} else {
            XCTFail("empty files are not used as avatars")
        }
    }
}
