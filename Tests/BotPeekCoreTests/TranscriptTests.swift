import XCTest
@testable import BotPeekCore

final class SidebarParserTests: XCTestCase {
    func testListsBotButtonsOnly() {
        let ax = AXTreeBuilder()
        let window = ax.window(sidebar: ["Research Bot, Waiting for you", "Writer"], heading: nil, messages: [])
        let entries = SidebarParser.entries(in: window)
        XCTAssertEqual(entries?.map(\.label), ["Research Bot, Waiting for you", "Writer"])
        XCTAssertEqual(SidebarParser.statusText(of: entries![0], botName: "Research Bot"), "Waiting for you")
        XCTAssertNil(SidebarParser.statusText(of: entries![1], botName: "Writer"))
    }

    func testMissingSidebarReturnsNil() {
        let ax = AXTreeBuilder()
        XCTAssertNil(SidebarParser.entries(in: ax.node("AXWindow")))
    }
}

final class BotIdentityMatcherTests: XCTestCase {
    func testExactMatchOnly() {
        let research = identity("r", "Research")
        let sidebar = [SidebarEntry(nodeID: 1, label: "Research Assistant"), SidebarEntry(nodeID: 2, label: "Research, Waiting for you")]
        XCTAssertEqual(BotIdentityMatcher.match(bot: research, roster: [research], sidebar: sidebar), .unique(sidebar[1]))
    }

    func testNoFuzzyMatching() {
        let bot = identity("r", "Res")
        let sidebar = [SidebarEntry(nodeID: 1, label: "Research Bot")]
        XCTAssertEqual(BotIdentityMatcher.match(bot: bot, roster: [bot], sidebar: sidebar), .notFound, "prefixes never match")
    }

    func testDuplicateNamesAreAmbiguous() {
        let a = identity("a", "Helper")
        let b = identity("b", "Helper")
        let sidebar = [SidebarEntry(nodeID: 1, label: "Helper"), SidebarEntry(nodeID: 2, label: "Helper")]
        XCTAssertEqual(BotIdentityMatcher.match(bot: a, roster: [a, b], sidebar: sidebar), .ambiguous)
    }

    func testOpenConversationNeedsUniqueName() {
        let a = identity("a", "Helper")
        let b = identity("b", "Helper")
        let c = identity("c", "Writer")
        XCTAssertTrue(BotIdentityMatcher.isOpen(bot: c, heading: "Writer", roster: [a, b, c]))
        XCTAssertFalse(BotIdentityMatcher.isOpen(bot: c, heading: "Helper", roster: [a, b, c]))
        XCTAssertFalse(BotIdentityMatcher.isOpen(bot: c, heading: nil, roster: [a, b, c]))
        XCTAssertFalse(BotIdentityMatcher.isOpen(bot: a, heading: "Helper", roster: [a, b, c]), "the open Helper may be the other one")
    }

    func testNamesContainingCommas() {
        let short = identity("a", "Ops")
        let long = identity("b", "Ops, Europe")
        let sidebar = [SidebarEntry(nodeID: 1, label: "Ops, Working"), SidebarEntry(nodeID: 2, label: "Ops, Europe, Waiting for you")]
        XCTAssertEqual(BotIdentityMatcher.match(bot: short, roster: [short, long], sidebar: sidebar), .unique(sidebar[0]))
        XCTAssertEqual(BotIdentityMatcher.match(bot: long, roster: [short, long], sidebar: sidebar), .unique(sidebar[1]))
    }
}

final class TranscriptParserTests: XCTestCase {
    func testParsesMessagesAndOpenQuestion() {
        let ax = AXTreeBuilder()
        let window = ax.window(sidebar: ["Research Bot"], heading: "Research Bot", messages: [
            ax.message("You", "9:50:01 PM", ["Find me vendors"]),
            ax.message("Research Bot", "9:55:21\u{202F}PM", ["I found three.", "Which should I contact?"],
                       buttons: ["Northwind", "Acme", "Globex"], dismiss: true),
        ])
        let conversation = TranscriptParser.parse(window: window)
        XCTAssertEqual(conversation.heading, "Research Bot")
        XCTAssertTrue(conversation.hasTranscript)
        XCTAssertNotNil(conversation.composerNodeID)
        XCTAssertEqual(conversation.messages.map(\.sender), ["You", "Research Bot"])
        XCTAssertEqual(conversation.messages[1].text, "I found three.\n\nWhich should I contact?", "button text and timestamps are excluded")
        XCTAssertEqual(conversation.openQuestion?.options.map(\.label), ["Northwind", "Acme", "Globex"])

        let content = TranscriptParser.content(from: conversation)
        XCTAssertEqual(content?.kind, .choice)
        XCTAssertEqual(content?.choices.count, 3)
        XCTAssertEqual(content?.source, .transcript)
    }

    func testButtonsWithoutDismissAreNotChoices() {
        let ax = AXTreeBuilder()
        let window = ax.window(sidebar: [], heading: "Writer", messages: [
            ax.message("Writer", "10:00:00", ["Draft ready. Any changes?"], buttons: ["Copy", "Retry"]),
        ])
        let conversation = TranscriptParser.parse(window: window)
        XCTAssertNil(conversation.openQuestion, "copy/retry buttons are not answers")
        let content = TranscriptParser.content(from: conversation)
        XCTAssertEqual(content?.kind, .question)
        XCTAssertEqual(content?.prompt, "Draft ready. Any changes?")
    }

    func testApprovalButtonsAreRecognized() {
        let ax = AXTreeBuilder()
        let window = ax.window(sidebar: [], heading: "Ops Bot", messages: [
            ax.message("Ops Bot", "8:00:00 AM", ["Run the migration?"], buttons: ["Approve", "Deny"], dismiss: true),
        ])
        XCTAssertEqual(TranscriptParser.content(from: TranscriptParser.parse(window: window))?.kind, .approval)
    }

    func testLastMessageFromUserIsNotAQuestion() {
        let ax = AXTreeBuilder()
        let window = ax.window(sidebar: [], heading: "Writer", messages: [ax.message("You", "10:00:00", ["Thanks!"])])
        XCTAssertNil(TranscriptParser.content(from: TranscriptParser.parse(window: window)))
    }

    func testInlineQuestionButtons() {
        let ax = AXTreeBuilder()
        let window = ax.window(sidebar: [], heading: "Tets", messages: [
            ax.inlineQuestion("Tets", "12:54:10\u{202F}AM", prompt: "How many travelers?", buttons: ["1", "2", "3"]),
            ax.message("Message from Planner", "1:52:36\u{202F}PM", ["Message from"], buttons: ["Open exchange with Planner"]),
            ax.inlineQuestion("Tets", "1:56:10\u{202F}PM", prompt: "Which cabin?", buttons: ["Economy", "Business"]),
        ])
        let question = TranscriptParser.parse(window: window).openQuestion
        XCTAssertEqual(question?.prompt, "Which cabin?", "only the newest message's question counts")
        XCTAssertEqual(question?.options.map(\.label), ["Economy", "Business"])
    }

    func testOlderInlineQuestionIsNotOpen() {
        let ax = AXTreeBuilder()
        let window = ax.window(sidebar: [], heading: "Tets", messages: [
            ax.inlineQuestion("Tets", "12:54:10 AM", prompt: "How many travelers?", buttons: ["1", "2"]),
            ax.message("Tets", "1:52:40 PM", ["Still here."]),
        ])
        XCTAssertNil(TranscriptParser.parse(window: window).openQuestion)
    }

    func testSingleInlineButtonNeedsCustomAnswerBox() {
        let ax = AXTreeBuilder()
        let withBox = ax.window(sidebar: [], heading: "Tets", messages: [
            ax.inlineQuestion("Tets", "1:00:00 PM", prompt: "Ready?", buttons: ["Yes"]),
        ])
        XCTAssertEqual(TranscriptParser.parse(window: withBox).openQuestion?.options.map(\.label), ["Yes"])
        let lone = ax.window(sidebar: [], heading: "Tets", messages: [
            ax.inlineQuestion("Tets", "1:00:00 PM", prompt: "Ready?", buttons: ["Yes"], customAnswer: false),
        ])
        XCTAssertNil(TranscriptParser.parse(window: lone).openQuestion, "a lone button could be a link or action")
    }

    func testListMarkersAreJoined() {
        XCTAssertEqual(TranscriptParser.joinListMarkers(["Options:", "1.", "Alpha", "2.", "Beta"]), "Options:\n\n1. Alpha\n\n2. Beta")
    }
}

final class DeliveryVerifierTests: XCTestCase {
    func conversation(_ messages: [(String, String, String)], question: [String]? = nil) -> ConversationSnapshot {
        ConversationSnapshot(
            heading: "Bot",
            hasTranscript: true,
            messages: messages.map { TranscriptMessage(label: "\($0.0) \($0.1)", sender: $0.0, time: $0.1, text: $0.2) },
            openQuestion: question.map { OpenQuestion(prompt: "?", options: $0.enumerated().map { .init(label: $1, nodeID: $0) }) },
            composerNodeID: 1,
            sendButtonNodeID: nil
        )
    }

    func testTextDeliveryNeedsANewMessage() {
        let before = conversation([("Bot", "1:00:00", "Budget?")])
        let same = conversation([("Bot", "1:00:00", "Budget?")])
        let after = conversation([("Bot", "1:00:00", "Budget?"), ("You", "1:00:09", "Under   $200 please")])
        XCTAssertFalse(DeliveryVerifier.textDelivered("Under $200 please", before: before, after: same))
        XCTAssertTrue(DeliveryVerifier.textDelivered("Under $200 please", before: before, after: after))
    }

    func testOldIdenticalMessageDoesNotCount() {
        let before = conversation([("You", "1:00:00", "yes")])
        XCTAssertFalse(DeliveryVerifier.textDelivered("yes", before: before, after: before))
    }

    func testChoiceDelivery() {
        let before = conversation([("Bot", "1:00:00", "Pick")], question: ["A", "B"])
        let stillOpen = conversation([("Bot", "1:00:00", "Pick")], question: ["A", "B"])
        let answered = conversation([("Bot", "1:00:00", "Pick"), ("You", "1:00:05", "A")])
        XCTAssertFalse(DeliveryVerifier.choiceDelivered("A", before: before, after: stillOpen))
        XCTAssertTrue(DeliveryVerifier.choiceDelivered("A", before: before, after: answered))
    }
}
