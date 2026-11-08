import XCTest
@testable import PetCore

final class IdleRoamingTests: XCTestCase {
    func testStartsRestingThenWalksBrieflyThenRestsAgain() {
        var behavior = IdleRoaming(sample: { 0 })
        XCTAssertEqual(behavior.phase, .resting)
        for _ in 0..<59 { behavior.advance(seconds: 0.25, sample: { 0 }) }
        XCTAssertEqual(behavior.phase, .resting)
        behavior.advance(seconds: 0.25, sample: { 0 })
        XCTAssertEqual(behavior.phase, .walking)
        XCTAssertEqual(behavior.direction, -1)
        for _ in 0..<8 { behavior.advance(seconds: 0.25, sample: { 0 }) }
        XCTAssertEqual(behavior.phase, .resting)
        XCTAssertEqual(behavior.remaining, 15)
    }

    func testRandomSamplesControlDurationAndBothDirections() {
        var behavior = IdleRoaming(sample: { 1 })
        XCTAssertEqual(behavior.remaining, 40)
        for _ in 0..<160 { behavior.advance(seconds: 0.25, sample: { 1 }) }
        XCTAssertEqual(behavior.phase, .walking)
        XCTAssertEqual(behavior.remaining, 5)
        XCTAssertEqual(behavior.direction, 1)
    }

    func testSleepDoesNotSkipRestAndRestartBeginsWithRest() {
        var behavior = IdleRoaming(sample: { 0 })
        behavior.advance(seconds: 3600, sample: { 0 })
        XCTAssertEqual(behavior.phase, .resting)
        XCTAssertEqual(behavior.remaining, 14.75)
        let resumed = IdleRoaming(sample: { 0.5 })
        XCTAssertEqual(resumed.phase, .resting)
        XCTAssertEqual(resumed.remaining, 27.5)
    }
}
