import XCTest
@testable import PetCore

final class AnimationPlaybackTests: XCTestCase {
    let durations: [String: TimeInterval] = ["idle": 1, "walk": 1, "working": 1, "attention": 1,
        "spawn": 0.5, "success": 0.5, "error": 0.5, "sleep": 1, "retire": 0.5]

    func testStartupOnceAndWorkPreempts() {
        var player = AnimationPlayback()
        XCTAssertEqual(player.advance(activity: .idle, seconds: 0, durations: durations), "spawn")
        XCTAssertEqual(player.advance(activity: .working, seconds: 0.1, durations: durations), "working")
        XCTAssertEqual(player.advance(activity: .idle, seconds: 0.1, durations: durations), "idle")
    }

    func testExplicitCompletionCelebratesOnceButIdleDoesNot() {
        var player = AnimationPlayback()
        _ = player.advance(activity: .working, seconds: 0, durations: durations)
        XCTAssertEqual(player.advance(activity: .idle, seconds: 0.1, durations: durations), "idle")
        XCTAssertEqual(player.advance(activity: .completed, seconds: 0.1, durations: durations), "success")
        _ = player.advance(activity: .completed, seconds: 0.25, durations: durations)
        XCTAssertEqual(player.advance(activity: .completed, seconds: 0.25, durations: durations), "idle")
        XCTAssertEqual(player.advance(activity: .completed, seconds: 0.25, durations: durations), "idle")
    }

    func testFailureRecoversAndNewWorkInterruptsIt() {
        var player = AnimationPlayback()
        XCTAssertEqual(player.advance(activity: .failed, seconds: 0, durations: durations), "error")
        _ = player.advance(activity: .failed, seconds: 0.25, durations: durations)
        XCTAssertEqual(player.advance(activity: .failed, seconds: 0.25, durations: durations), "idle")
        _ = player.advance(activity: .working, seconds: 0.1, durations: durations)
        XCTAssertEqual(player.advance(activity: .failed, seconds: 0.1, durations: durations), "error")
        XCTAssertEqual(player.advance(activity: .working, seconds: 0.1, durations: durations), "working")
    }

    func testSleepWakesOnInteractionAndAttention() {
        var player = AnimationPlayback(sleepAfter: 0.5)
        var available = durations; available.removeValue(forKey: "spawn")
        _ = player.advance(activity: .idle, seconds: 0.25, durations: available)
        XCTAssertEqual(player.advance(activity: .idle, seconds: 0.25, durations: available), "sleep")
        XCTAssertEqual(player.advance(activity: .idle, seconds: 0.1, interacted: true, durations: available), "idle")
        XCTAssertEqual(player.advance(activity: .attention, seconds: 0.1, durations: available), "attention")
        XCTAssertEqual(player.advance(activity: .retired, seconds: 0.1, durations: available), "retire")
    }

    func testMissingOptionalArtworkAndInvalidElapsedFallBack() {
        var player = AnimationPlayback(sleepAfter: 0)
        let minimal: [String: TimeInterval] = ["idle": 1, "walk": 1, "working": 1, "retire": 1]
        for activity in [Activity.idle, .attention, .completed, .failed] {
            XCTAssertEqual(player.advance(activity: activity, seconds: .infinity, durations: minimal), "idle")
        }
    }
}
