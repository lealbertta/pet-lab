import XCTest
@testable import PetCore

final class RoamingTests: XCTestCase {
    func testFractionalStepsAccumulateEvenWhenWindowCoordinatesAreRoundedDown() {
        var motion = RoamingMotion(x: 152)
        var actualWindowX: CGFloat = 152
        for _ in 0..<30 {
            actualWindowX = floor(motion.advance(seconds: 1.0/30, minX: 0, maxX: 1000))
        }
        XCTAssertGreaterThan(actualWindowX, 172)
        XCTAssertEqual(motion.x, 174, accuracy: 0.001)
    }

    func testBouncesAtBothEdgesWithoutCrossingThem() {
        var motion = RoamingMotion(x: 9)
        XCTAssertEqual(motion.advance(seconds: 0.2, minX: 0, maxX: 10), 10)
        XCTAssertEqual(motion.direction, -1)
        for _ in 0..<100 {
            let x = motion.advance(seconds: 1.0/30, minX: 0, maxX: 10)
            XCTAssertTrue((0...10).contains(x))
        }
    }

    func testDisplayChangesClampStoredPositionAndLongPausesDoNotTeleport() {
        var motion = RoamingMotion(x: 500)
        XCTAssertEqual(motion.advance(seconds: 0, minX: -100, maxX: 0), 0)
        let before = motion.x
        motion.advance(seconds: 3600, minX: -100, maxX: 0)
        XCTAssertLessThanOrEqual(abs(motion.x-before), 5.5)
    }
}
