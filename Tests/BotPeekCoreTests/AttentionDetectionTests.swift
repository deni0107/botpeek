import XCTest
@testable import BotPeekCore

final class AwaitingRequestParserTests: XCTestCase {
    func testQuestionWithMixedOptions() throws {
        let payload = try JSONValue.parse(Data(#"""
        {"id":"q1","question":"Which vendor?","options":[{"label":"A","description":"cheap"},"B",{"title":"C"}]}
        """#.utf8))
        let content = AwaitingRequestParser.parse(payload)
        XCTAssertEqual(content.kind, .choice)
        XCTAssertEqual(content.prompt, "Which vendor?")
        XCTAssertEqual(content.choices.map(\.label), ["A", "B", "C"])
        XCTAssertEqual(content.choices.first?.detail, "cheap")
        XCTAssertEqual(content.source, .roster)
    }

    func testFreeTextQuestion() throws {
        let payload = try JSONValue.parse(Data(#"{"prompt":"What budget should I use?"}"#.utf8))
        let content = AwaitingRequestParser.parse(payload)
        XCTAssertEqual(content.kind, .question)
        XCTAssertEqual(content.prompt, "What budget should I use?")
    }

    func testApprovalByTypeAndByLabels() throws {
        let byType = try JSONValue.parse(Data(#"{"kind":"tool_approval","message":"Send the email?"}"#.utf8))
        XCTAssertEqual(AwaitingRequestParser.parse(byType).kind, .approval)

        let byLabels = try JSONValue.parse(Data(#"{"text":"Run it?","choices":["Allow","Don't allow"]}"#.utf8))
        XCTAssertEqual(AwaitingRequestParser.parse(byLabels).kind, .approval)
    }

    func testNestedPayload() throws {
        let payload = try JSONValue.parse(Data(#"{"request":{"body":{"question":"Deep?","answers":["Yes","No"]}}}"#.utf8))
        let content = AwaitingRequestParser.parse(payload)
        XCTAssertEqual(content.prompt, "Deep?")
        XCTAssertEqual(content.choices.map(\.label), ["Yes", "No"])
    }

    func testUnreadableButNonEmptyPayloadIsOpaque() throws {
        let payload = try JSONValue.parse(Data(#"{"since":1730000000,"flag":true}"#.utf8))
        XCTAssertEqual(AwaitingRequestParser.parse(payload), .opaque)
    }

    func testFingerprintIgnoresVolatileFields() throws {
        let a = try JSONValue.parse(Data(#"{"id":"q1","question":"Same?","updatedAt":1}"#.utf8))
        let b = try JSONValue.parse(Data(#"{"id":"q1","question":"Same?","updatedAt":2}"#.utf8))
        let c = try JSONValue.parse(Data(#"{"id":"q2","question":"Same?","updatedAt":2}"#.utf8))
        XCTAssertEqual(AwaitingRequestParser.fingerprint(of: a), AwaitingRequestParser.fingerprint(of: b))
        XCTAssertNotEqual(AwaitingRequestParser.fingerprint(of: a), AwaitingRequestParser.fingerprint(of: c))
    }

    func testLongTextIsClamped() {
        let long = String(repeating: "x", count: 5_000)
        let content = AwaitingRequestParser.parse(.object(["question": .string(long)]))
        XCTAssertLessThanOrEqual(content.prompt?.count ?? 0, AwaitingRequestParser.maximumTextLength + 1)
    }
}

final class AttentionDetectorTests: XCTestCase {
    func testOnlyAwaitingBotsNeedAttention() throws {
        let bots = try RosterParser.parse(Fixture.data("roster-v4.json")).bots
        let snapshot = AttentionDetector.snapshot(roster: bots, sidebar: nil, observedAt: date(0))
        XCTAssertEqual(Set(snapshot.attention.map(\.bot.name)), ["Research Bot", "Ops Bot"])
        XCTAssertFalse(snapshot.bots.contains { $0.name == "Archived Helper" }, "hidden bots are ignored")
    }

    func testUnreadAndFinishedBotsNeverTrigger() {
        let bot = Bot(identity: identity("w", "Writer"), awaitingUserResponse: nil, hasUnread: true, unreadCount: 12, lastActivity: date(0))
        let snapshot = AttentionDetector.snapshot(roster: [bot], sidebar: nil, observedAt: date(1))
        XCTAssertTrue(snapshot.attention.isEmpty)
    }

    func testSidebarSignalIsUsedOnlyWithExactMatch() {
        let research = Bot(identity: identity("r", "Research"))
        let researchLong = Bot(identity: identity("r2", "Research Bot"))
        let sidebar = [
            SidebarEntry(nodeID: 1, label: "Research Bot, Waiting for you"),
            SidebarEntry(nodeID: 2, label: "Research, Working"),
        ]
        let snapshot = AttentionDetector.snapshot(roster: [research, researchLong], sidebar: sidebar, observedAt: date(0))
        XCTAssertEqual(snapshot.attention.map(\.bot.name), ["Research Bot"])
        XCTAssertEqual(snapshot.attention.first?.source, .accessibility)
    }

    func testWorkingLabelsDoNotTrigger() {
        let bot = Bot(identity: identity("c", "Car rental"))
        for status in ["Car rental, Working", "Car rental, Thinking", "Car rental, Finished", "Car rental, 3 unread"] {
            let snapshot = AttentionDetector.snapshot(
                roster: [bot], sidebar: [SidebarEntry(nodeID: 1, label: status)], observedAt: date(0)
            )
            XCTAssertTrue(snapshot.attention.isEmpty, status)
        }
    }

    func testRosterPayloadWinsOverSidebar() {
        let bot = Bot(identity: identity("r", "Research"), awaitingUserResponse: .object(["question": .string("Pick one")]))
        let snapshot = AttentionDetector.snapshot(
            roster: [bot], sidebar: [SidebarEntry(nodeID: 1, label: "Research, Waiting for you")], observedAt: date(0)
        )
        XCTAssertEqual(snapshot.attention.count, 1)
        XCTAssertEqual(snapshot.attention[0].source, .roster)
        XCTAssertEqual(snapshot.attention[0].content.prompt, "Pick one")
    }
}

final class JSONValueTests: XCTestCase {
    func testEmptySignals() {
        XCTAssertTrue(JSONValue.null.isEmptySignal)
        XCTAssertTrue(JSONValue.bool(false).isEmptySignal)
        XCTAssertTrue(JSONValue.object([:]).isEmptySignal)
        XCTAssertTrue(JSONValue.array([]).isEmptySignal)
        XCTAssertTrue(JSONValue.string("  ").isEmptySignal)
        XCTAssertFalse(JSONValue.bool(true).isEmptySignal)
        XCTAssertFalse(JSONValue.object(["a": .null]).isEmptySignal)
    }

    func testCanonicalStringIsKeyOrderIndependent() throws {
        let a = try JSONValue.parse(Data(#"{"b":1,"a":[true,null,"x"]}"#.utf8))
        let b = try JSONValue.parse(Data(#"{"a":[true,null,"x"],"b":1}"#.utf8))
        XCTAssertEqual(a.canonicalString, b.canonicalString)
        XCTAssertEqual(StableHash.fnv1a("hello"), "a430d84680aabd0b")
    }
}
