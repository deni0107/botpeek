import XCTest
@testable import BotPeekCore

@MainActor
final class DemoIntegrationTests: XCTestCase {
    func testScriptedTimelineAndNoFalsePositives() async {
        let demo = DemoIntegration(startedAt: date(0), replyDelay: 0)
        XCTAssertTrue(demo.currentSnapshot(now: date(1)).attention.isEmpty)
        XCTAssertEqual(demo.currentSnapshot(now: date(3)).attention.map(\.bot.name), ["Research Bot"])
        let later = demo.currentSnapshot(now: date(60))
        XCTAssertEqual(later.attention.map(\.bot.name), ["Research Bot", "Travel Planner", "Ops Bot"])
        XCTAssertFalse(later.attention.contains { $0.bot.name == "Writer" || $0.bot.name == "Inbox Bot" },
                       "bots with unread updates never ask for attention")
        XCTAssertEqual(later.bots.count, 5)
        XCTAssertTrue(demo.health(now: date(0)).isDemo)
    }

    func testEndToEndDemoFlow() async throws {
        let demo = DemoIntegration(startedAt: date(0), replyDelay: 0)
        let manager = AttentionEventManager(configuration: .init(confirmationDelay: 0))
        let replies = ReplyCoordinator(service: demo.replyService, manager: manager, allowInlineApprovals: { false })

        manager.ingest(demo.currentSnapshot(now: date(3)))
        let request = try XCTUnwrap(manager.presentable.first)
        XCTAssertEqual(request.content.choices.count, 3)

        let state = await replies.send(.choice(AttentionChoice(label: "Acme Components")), for: request.id)
        if case .delivered = state {} else { return XCTFail("demo reply should deliver: \(state)") }

        // Once the demo bot notices the answer, the request resolves as answered here.
        let events = manager.ingest(demo.currentSnapshot(now: Date().addingTimeInterval(5)))
        XCTAssertTrue(events.contains(.resolved(request.id, .answeredHere)))
    }

    func testSimulatedFailure() async {
        let demo = DemoIntegration(startedAt: date(0), replyDelay: 0)
        let manager = AttentionEventManager(configuration: .init(confirmationDelay: 0))
        manager.ingest(demo.currentSnapshot(now: date(10)))
        let travel = manager.presentable.first { $0.bot.name == "Travel Planner" }!
        let replies = ReplyCoordinator(service: demo, manager: manager, allowInlineApprovals: { false })
        let state = await replies.send(.text("cheap please \(DemoIntegration.failureKeyword)"), for: travel.id)
        if case .failed = state {} else { XCTFail("expected simulated failure") }
    }
}
