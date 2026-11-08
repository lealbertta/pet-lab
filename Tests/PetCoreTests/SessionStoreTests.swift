import XCTest
@testable import PetCore

final class SessionStoreTests: XCTestCase {
    func event(_ kind: String, session: String = "a", turn: String? = "t1", time: UInt64 = 1,
               background: Int? = nil) -> SessionEvent {
        SessionEvent(provider: "fixture", session: session, turn: turn, kind: kind,
                     observedNs: time, backgroundCount: background)
    }
    func testWorkingSurvivesTenMinuteGapAndToolCompletion() {
        let store = SessionStore()
        store.apply(event("turnStart"))
        store.apply(event("toolEnd", time: 600_000_000_001))
        XCTAssertEqual(store.sharedActivity, .working)
        store.apply(event("completed", time: 600_000_000_002))
        XCTAssertEqual(store.sharedActivity, .completed)
    }
    func testOverlappingSessionsAndAttentionRemainIndependent() {
        let store = SessionStore()
        store.apply(event("turnStart")); store.apply(event("turnStart", session: "b"))
        store.apply(event("attention", time: 2))
        XCTAssertEqual(store.sharedActivity, .working); XCTAssertEqual(store.attentionCount, 1)
        store.apply(event("completed", session: "b", time: 3))
        XCTAssertEqual(store.sharedActivity, .attention)
    }
    func testLatePreviousTurnCannotCompleteNewTurn() {
        let store = SessionStore()
        store.apply(event("turnStart")); store.apply(event("turnStart", turn: "t2", time: 2))
        store.apply(event("completed", turn: "t1", time: 3))
        XCTAssertEqual(store.sharedActivity, .working)
        store.apply(event("attention", turn: "t2", time: 4))
        store.apply(event("toolStart", turn: "t1", time: 5))
        XCTAssertEqual(store.sharedActivity, .attention)
    }
    func testStopIsCandidateAndContinuationPreservesWork() {
        let store = SessionStore()
        store.apply(event("turnStart")); store.apply(event("stopCandidate", time: 2))
        XCTAssertTrue(store.sessions["fixture:a"]!.stopPending)
        XCTAssertEqual(store.sharedActivity, .working)
        store.apply(event("requestStart", time: 3))
        XCTAssertFalse(store.sessions["fixture:a"]!.stopPending)
    }
    func testCompletionWithBackgroundWorkRemainsWorking() {
        let store = SessionStore()
        store.apply(event("turnStart")); store.apply(event("completed", time: 2, background: 1))
        XCTAssertEqual(store.sharedActivity, .working)
        store.apply(event("completed", time: 3, background: 0))
        XCTAssertEqual(store.sharedActivity, .completed)
    }
    func testDuplicateOldObservationAndDisconnect() {
        let store = SessionStore(); let first = event("turnStart", time: 2)
        store.apply(first); store.apply(first); store.apply(event("completed", time: 1))
        XCTAssertEqual(store.sharedActivity, .working)
        store.apply(event("disconnected", time: 3))
        XCTAssertEqual(store.sharedActivity, .uncertain)
    }
    func testRetirementDoesNotHideOtherSession() {
        let store = SessionStore()
        store.apply(event("turnStart")); store.apply(event("turnStart", session: "b"))
        store.apply(event("sessionEnd", time: 2))
        XCTAssertEqual(store.sharedActivity, .working)
        XCTAssertEqual(store.sessions["fixture:a"]!.activity, .retired)
        store.apply(event("completed", time: 3))
        XCTAssertEqual(store.sessions["fixture:a"]!.activity, .retired)
    }
}
