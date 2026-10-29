import XCTest
@testable import BotPeekCore

final class PanelPlacementTests: XCTestCase {
    let screen = CGRect(x: 0, y: 80, width: 1440, height: 795) // visible frame above a Dock

    func testRightEdgeIsFlushAndInsideVisibleFrame() {
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 400, height: 220), edge: .right, position: 0.5, visibleFrame: screen)
        XCTAssertEqual(frame.maxX, screen.maxX)
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY)
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY)
    }

    func testBottomEdgeSitsOnTheDock() {
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 300, height: 300), edge: .bottom, position: 1, visibleFrame: screen)
        XCTAssertEqual(frame.minY, screen.minY, "never covers the Dock")
        XCTAssertEqual(frame.maxX, screen.maxX - 8)
    }

    func testLeftEdgeAndSecondaryScreenOrigin() {
        let secondary = CGRect(x: -1920, y: 0, width: 1920, height: 1050)
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 300, height: 200), edge: .left, position: 0, visibleFrame: secondary)
        XCTAssertEqual(frame.minX, -1920)
        XCTAssertEqual(frame.minY, 8)
    }

    func testOversizedContentIsClamped() {
        let small = CGRect(x: 0, y: 0, width: 200, height: 100)
        let frame = PanelPlacement.frame(contentSize: CGSize(width: 500, height: 500), edge: .right, position: 0.5, visibleFrame: small)
        XCTAssertTrue(small.contains(frame))
    }

    func testStackRoomIsReservedAlongTheEdge() {
        let bubble = CGSize(width: 312, height: 400)
        let side = PanelPlacement.contentSize(characterSize: 72, bubbleSize: bubble, edge: .right)
        XCTAssertGreaterThanOrEqual(side.height, 72 + PanelPlacement.stackLength(characterSize: 72))
        let bottom = PanelPlacement.contentSize(characterSize: 72, bubbleSize: bubble, edge: .bottom)
        XCTAssertGreaterThanOrEqual(bottom.width, 72 + PanelPlacement.stackLength(characterSize: 72) * 2, "character stays centered")
    }

    func testStackOverflow() {
        let split = PanelPlacement.stack(Array(1...7))
        XCTAssertEqual(split.shown, [1, 2, 3, 4])
        XCTAssertEqual(split.overflow, 3)
        XCTAssertEqual(PanelPlacement.stack([1]).overflow, 0)
    }

    func testPositionIsTheInverseOfFrame() {
        let size = CGSize(width: 400, height: 300)
        for edge in ScreenEdge.allCases {
            for position in [0, 0.25, 0.5, 0.8, 1.0] {
                let frame = PanelPlacement.frame(contentSize: size, edge: edge, position: position, visibleFrame: screen)
                let anchor = PanelPlacement.dragAnchor(of: frame, edge: edge, growsDown: PanelPlacement.growsDown(edge: edge, position: position), characterSize: 72)
                let back = PanelPlacement.position(forDragAnchor: anchor, edge: edge, contentSize: size, visibleFrame: screen)
                XCTAssertEqual(back, position, accuracy: 0.0001, "\(edge) at \(position)")
            }
        }
        let below = PanelPlacement.position(forDragAnchor: -500, edge: .right, contentSize: size, visibleFrame: screen)
        XCTAssertEqual(below, 0, "dragging past the end clamps")
    }

    func testCharacterReachesBothEndsOfASideEdge() {
        let tall = CGSize(width: 400, height: 450)
        let top = PanelPlacement.frame(contentSize: tall, edge: .right, position: 1, visibleFrame: screen)
        XCTAssertTrue(PanelPlacement.growsDown(edge: .right, position: 1), "the bubble hangs below near the top")
        XCTAssertEqual(top.maxY, screen.maxY - 8, "character near the top of the screen")
        let bottom = PanelPlacement.frame(contentSize: tall, edge: .right, position: 0, visibleFrame: screen)
        XCTAssertEqual(bottom.minY, screen.minY + 8)
        let middleUp = PanelPlacement.frame(contentSize: CGSize(width: 400, height: 380), edge: .left, position: 0.5, visibleFrame: screen)
        let middleDown = PanelPlacement.frame(contentSize: CGSize(width: 400, height: 380), edge: .left, position: 0.5001, visibleFrame: screen)
        let anchorUp = PanelPlacement.dragAnchor(of: middleUp, edge: .left, growsDown: false, characterSize: 72)
        let anchorDown = PanelPlacement.dragAnchor(of: middleDown, edge: .left, growsDown: true, characterSize: 72)
        XCTAssertEqual(anchorUp, anchorDown, accuracy: 0.5, "the character doesn't jump when the bubble flips")
    }

    func testInwardDirections() {
        XCTAssertEqual(PanelPlacement.inwardDirection(for: .right).dx, -1)
        XCTAssertEqual(PanelPlacement.inwardDirection(for: .left).dx, 1)
        XCTAssertEqual(PanelPlacement.inwardDirection(for: .bottom).dy, -1)
    }
}

final class AnimationPlanTests: XCTestCase {
    func testReducedMotionNeverMovesOrRotates() {
        for intensity in AnimationIntensity.allCases {
            let plan = AnimationPlan.make(intensity: intensity, reduceMotion: true)
            XCTAssertFalse(plan.usesMotion)
            let poses = [plan.initial] + plan.entrance + plan.celebration + plan.exit
            XCTAssertTrue(poses.allSatisfy { $0.hidden == AnimationPlan.restingHidden }, "no sliding")
            XCTAssertTrue(poses.allSatisfy { $0.rotationDegrees == 0 && $0.scale == 1 }, "no bounce or rotation")
            XCTAssertTrue(plan.celebration.isEmpty)
            XCTAssertTrue(plan.nudge.isEmpty, "no reminder wiggle")
        }
    }

    func testEntranceStartsHiddenAndEndsAtRest() {
        for intensity in AnimationIntensity.allCases {
            let plan = AnimationPlan.make(intensity: intensity, reduceMotion: false)
            XCTAssertEqual(plan.initial.hidden, 1, "starts tucked behind the edge")
            XCTAssertEqual(plan.entrance.last?.hidden, AnimationPlan.restingHidden)
            XCTAssertEqual(plan.entrance.last?.scale, 1)
            XCTAssertEqual(plan.entrance.last?.rotationDegrees, 0, "always settles upright")
            XCTAssertEqual(plan.exit.last?.hidden, 1, "leaves the screen completely")
        }
    }

    func testMinimalModeHasNoBounce() {
        let plan = AnimationPlan.make(intensity: .minimal, reduceMotion: false)
        XCTAssertEqual(plan.entrance.count, 1)
        XCTAssertTrue((plan.entrance + plan.exit).allSatisfy { $0.rotationDegrees == 0 && $0.scale == 1 })
    }

    func testAnimationsStayShort() {
        for intensity in AnimationIntensity.allCases {
            let plan = AnimationPlan.make(intensity: intensity, reduceMotion: false)
            XCTAssertLessThan(plan.entranceDuration, 1.5, "entrance must never become annoying")
            XCTAssertLessThan(plan.exitDuration, 1)
            XCTAssertLessThan(plan.celebrationDuration, 1.2)
            XCTAssertLessThan(plan.nudgeDuration, 1)
            XCTAssertEqual(plan.nudge.last?.hidden ?? AnimationPlan.restingHidden, AnimationPlan.restingHidden, "a nudge settles back at rest")
            XCTAssertEqual(plan.nudge.last?.rotationDegrees ?? 0, 0)
        }
    }
}

final class CharacterStateMachineTests: XCTestCase {
    func testHappyPath() {
        var machine = CharacterStateMachine()
        for (input, expected) in [
            (CharacterInput.present, CharacterPhase.entering),
            (.animationFinished, .presented),
            (.expand, .expanded),
            (.beginSend, .sending),
            (.sendSucceeded, .celebrating),
            (.animationFinished, .exiting),
            (.animationFinished, .hidden),
        ] {
            XCTAssertTrue(machine.handle(input), "\(input)")
            XCTAssertEqual(machine.phase, expected)
        }
    }

    func testFailedSendReturnsToComposer() {
        var machine = CharacterStateMachine()
        machine.handle(.present); machine.handle(.animationFinished); machine.handle(.expand); machine.handle(.beginSend)
        XCTAssertTrue(machine.handle(.sendFailed))
        XCTAssertEqual(machine.phase, .expanded)
    }

    func testAnsweredElsewhereLeavesFromAnyVisiblePhase() {
        for setup in [[CharacterInput.present], [.present, .animationFinished], [.present, .animationFinished, .expand]] {
            var machine = CharacterStateMachine()
            setup.forEach { machine.handle($0) }
            XCTAssertTrue(machine.handle(.leave))
            XCTAssertEqual(machine.phase, .exiting)
        }
    }

    func testIgnoresInvalidAndLateInputs() {
        var machine = CharacterStateMachine()
        XCTAssertFalse(machine.handle(.sendSucceeded))
        XCTAssertFalse(machine.handle(.animationFinished))
        XCTAssertFalse(machine.handle(.leave))
        XCTAssertEqual(machine.phase, .hidden)
    }

    func testNewRequestDuringExitReenters() {
        var machine = CharacterStateMachine()
        machine.handle(.present); machine.handle(.leave)
        XCTAssertTrue(machine.handle(.present))
        XCTAssertEqual(machine.phase, .entering)
    }
}

final class SettingsTests: XCTestCase {
    func testDefaults() {
        let settings = BotPeekSettings()
        XCTAssertFalse(settings.soundsEnabled, "sounds are off by default")
        XCTAssertFalse(settings.allowInlineApprovals, "approvals open in Grok Bot by default")
        XCTAssertFalse(settings.demoMode)
        XCTAssertEqual(settings.deliveryMethod, .background, "replies never bring Grok Bot forward by default")
    }

    func testOldDeliveryMethodsMoveToBackground() throws {
        for old in ["pasteAndReturn", "backgroundExperimental"] {
            let json = #"{"deliveryMethod":"\#(old)"}"#
            XCTAssertEqual(try JSONDecoder().decode(BotPeekSettings.self, from: Data(json.utf8)).deliveryMethod, .background)
        }
        let paste = try JSONDecoder().decode(BotPeekSettings.self, from: Data(#"{"deliveryMethod":"paste"}"#.utf8))
        XCTAssertEqual(paste.deliveryMethod, .paste)
    }

    func testMissingAndInvalidKeysKeepDefaults() throws {
        let json = #"{"edge":"bottom","snoozeMinutes":0,"edgePosition":7,"futureSetting":true,"animationIntensity":"bogus"}"#
        let settings = try JSONDecoder().decode(BotPeekSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.edge, .bottom)
        XCTAssertEqual(settings.snoozeMinutes, 1)
        XCTAssertEqual(settings.edgePosition, 1)
        XCTAssertEqual(settings.animationIntensity, .lively)
        XCTAssertTrue(settings.isEnabled)
    }

    func testPauseRoundTripsAndExpires() throws {
        var settings = BotPeekSettings()
        XCTAssertFalse(settings.isPaused(at: date(0)))
        XCTAssertTrue(settings.collapsesWhenIdle && settings.nudgesWhenIgnored && settings.hideFromScreenCapture)
        settings.pausedUntil = date(100)
        let decoded = try JSONDecoder().decode(BotPeekSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.isPaused(at: date(99)))
        XCTAssertFalse(decoded.isPaused(at: date(100)), "characters return when the pause ends")
    }

    func testStoreRoundTrip() {
        let store = SettingsStore(store: InMemoryKeyValueStore())
        var settings = store.load()
        settings.characterSize = .large
        settings.hasCompletedOnboarding = true
        store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    func testDismissedStoreKeepsNoContent() {
        let backing = InMemoryKeyValueStore()
        let store = PersistentDismissedStore(store: backing)
        let id = RequestID(botID: BotID("secret-bot"), fingerprint: "abc")
        store.insert(id, at: date(100))
        let raw = String(data: backing.data(forKey: PersistentDismissedStore.key) ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(raw.contains("secret-bot"), "only hashes are stored")
        XCTAssertTrue(store.contains(id))
        store.prune(olderThan: date(200))
        XCTAssertFalse(store.contains(id))
    }
}

final class DiagnosticsLogTests: XCTestCase {
    func testCapacityAndExport() {
        let log = DiagnosticsLog(capacity: 3)
        for index in 0..<5 { log.record(.info, "test", "event \(index)", date: date(Double(index))) }
        XCTAssertEqual(log.allEntries.map(\.message), ["event 2", "event 3", "event 4"])
        let text = log.export(header: ["Version": "1.0"])
        XCTAssertTrue(text.contains("Version: 1.0"))
        XCTAssertTrue(text.contains("Contains no message contents"))
    }

    func testLogTagsHideBotIds() {
        XCTAssertFalse(BotID("my-private-bot").logTag.contains("private"))
        XCTAssertTrue(BotID("x").logTag.hasPrefix("bot#"))
    }
}
