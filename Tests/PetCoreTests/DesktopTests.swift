import XCTest
@testable import PetCore

final class DesktopTests: XCTestCase {
    func testEveryEdgeKeepsEntirePetInBounds() {
        let screen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        for x in [-2000.0, -1000, 500] {
            for y in [-200.0, 400, 1200] {
                let result = DesktopGeometry.clamp(CGRect(x: x, y: y, width: 128, height: 150), to: screen)
                XCTAssertTrue(screen.contains(result))
            }
        }
    }
    func testSelectsScreenWithMostOverlapAndHandlesDisplayRemoval() {
        let left = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let pet = CGRect(x: -70, y: 50, width: 100, height: 120)
        XCTAssertEqual(DesktopGeometry.containingScreen(for: pet, screens: [left, right]), left)
        XCTAssertTrue(right.contains(DesktopGeometry.clamp(pet, to: right)))
    }
    func testEmptySnapshotIsIdleAndAnotherSessionCannotClearWork() throws {
        let empty = try JSONDecoder().decode(MonitorSnapshot.self, from: Data(#"{"schemaVersion":1,"generation":"a","sessions":[]}"#.utf8))
        XCTAssertEqual(empty.sharedActivity, .idle)
        let busy = try JSONDecoder().decode(MonitorSnapshot.self, from: Data(#"{"schemaVersion":1,"generation":"b","sessions":[{"key":"a","activity":"working"},{"key":"b","activity":"idle"}]}"#.utf8))
        XCTAssertEqual(busy.sharedActivity, .working)
    }
    func testActivityBarReservesSpaceAboveDraggedPet() {
        let screen = CGRect(x: -1440, y: 20, width: 1440, height: 850)
        let allowed = DesktopGeometry.petBounds(on: screen, accessoryHeight: 60)
        let pet = DesktopGeometry.clamp(CGRect(x: -80, y: 900, width: 150, height: 184), to: allowed)
        XCTAssertLessThanOrEqual(pet.maxY + 60, screen.maxY)
        XCTAssertTrue(screen.contains(pet))
    }
    func testFeetRestOnFloorDespiteWindowPadding() {
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)
        let allowed = DesktopGeometry.petBounds(on: visible, accessoryHeight: 0, footInset: 14.5)
        let pet = DesktopGeometry.clamp(CGRect(x: 200, y: -300, width: 104, height: 120), to: allowed)
        XCTAssertEqual(pet.minY + 14.5, visible.minY)
        XCTAssertEqual(DesktopGeometry.clamp(CGRect(x: 200, y: 2000, width: 104, height: 120), to: allowed).maxY, visible.maxY)
    }
    func testPetsStandOnPhysicalBottomEdgeWithOrWithoutDock() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let hidden = DesktopGeometry.standingArea(screen: screen, visible: CGRect(x: 0, y: 4, width: 1440, height: 871))
        XCTAssertEqual(hidden.minY, 0); XCTAssertEqual(hidden.maxY, 875)
        let docked = DesktopGeometry.standingArea(screen: screen, visible: CGRect(x: 0, y: 57, width: 1440, height: 818))
        XCTAssertEqual(docked.minY, 0); XCTAssertEqual(docked.maxY, 875)
        let sideDock = DesktopGeometry.standingArea(screen: screen, visible: CGRect(x: 60, y: 0, width: 1380, height: 875))
        XCTAssertEqual(sideDock.minX, 60)
    }
    func testSessionWaitingForInputOutranksWork() throws {
        let snapshot = try JSONDecoder().decode(MonitorSnapshot.self, from: Data(#"{"schemaVersion":1,"generation":"w","sessions":[{"key":"a","activity":"working"},{"key":"b","activity":"attention","title":"Asks a question"},{"key":"c","activity":"idle"}]}"#.utf8))
        XCTAssertEqual(snapshot.sharedActivity, .attention)
        XCTAssertEqual(snapshot.preferredSession?.key, "b")
    }
    func testExplicitResultsReachPlaybackWithoutOverridingBusySession() throws {
        for state in [Activity.completed, .failed] {
            let data = Data("{\"schemaVersion\":1,\"generation\":\"result\",\"sessions\":[{\"key\":\"a\",\"activity\":\"\(state.rawValue)\"}]}".utf8)
            let snapshot = try JSONDecoder().decode(MonitorSnapshot.self, from: data)
            XCTAssertEqual(snapshot.sharedActivity, state)
        }
        let mixed = try JSONDecoder().decode(MonitorSnapshot.self, from: Data(#"{"schemaVersion":1,"generation":"mixed","sessions":[{"key":"a","activity":"failed"},{"key":"b","activity":"working"}]}"#.utf8))
        XCTAssertEqual(mixed.sharedActivity, .working)
    }
    func testPerSessionSnapshotKeepsItsOwnActivityTitleAndCat() throws {
        let snapshot = try JSONDecoder().decode(MonitorSnapshot.self, from: Data(#"{"schemaVersion":1,"generation":"multi","sessions":[{"key":"a","activity":"idle","title":"One","pack":"/cats/one"},{"key":"b","activity":"working","title":"Two","pack":"/cats/two"}]}"#.utf8))
        let own = snapshot.forSession("a")
        XCTAssertEqual(own.sessions.count, 1)
        XCTAssertEqual(own.sharedActivity, .idle)
        XCTAssertEqual(own.preferredSession?.title, "One")
        XCTAssertEqual(own.preferredSession?.pack, "/cats/one")
        XCTAssertTrue(snapshot.forSession("missing").sessions.isEmpty)
    }
    func testActivityBarFollowsBusySessionAndAcceptsOlderSnapshots() throws {
        let snapshot = try JSONDecoder().decode(MonitorSnapshot.self, from: Data(#"{"schemaVersion":1,"generation":"a","sessions":[{"key":"a","activity":"idle"},{"key":"b","activity":"working","title":"Fixture task"}]}"#.utf8))
        XCTAssertEqual(snapshot.preferredSession?.key, "b")
        XCTAssertEqual(snapshot.preferredSession?.title, "Fixture task")
        XCTAssertNil(snapshot.sessions[0].title)
    }

}
