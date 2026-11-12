import XCTest
@testable import PetCore

final class PetPreferencesTests: XCTestCase {
    func testDefaultsAndBounds() throws {
        XCTAssertEqual(PetPreferences().sizeScale, 1)
        XCTAssertEqual(PetPreferences(sizeScale: 100).sizeScale, 2)
        XCTAssertEqual(PetPreferences(sizeScale: -1).sizeScale, 0.5)
        XCTAssertEqual(PetPreferences(sizeScale: .nan).sizeScale, 1)
        let old = try JSONDecoder().decode(PetPreferences.self, from: Data(#"{"sizeScale":1.5}"#.utf8))
        XCTAssertEqual(old.disabledSprites, [])
        XCTAssertEqual(old.sizeScale, 1.5); XCTAssertTrue(old.allowWandering); XCTAssertTrue(old.showSessionLabels)
    }
    func testPersistsAndRecoversFromBadOrMissingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("preferences.json")
        XCTAssertEqual(PetPreferences.load(from: file), PetPreferences())
        let changed = PetPreferences(sizeScale: 1.75, allowWandering: false, showSessionLabels: false, multicats: true, disabledSprites: ["cat-01-calico"])
        try changed.save(to: file)
        XCTAssertEqual(PetPreferences.load(from: file), changed)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try Data("broken".utf8).write(to: file)
        XCTAssertEqual(PetPreferences.load(from: file), PetPreferences())
    }
    func testScalingPreservesAspectRatioAndContainsEntireSprite() {
        for scale in [0.5, 1, 1.5, 2] {
            let layout = PetSizeLayout(frameSize: [192,208], anchor: [100,202], displayHeight: 160, scale: scale)
            XCTAssertEqual(layout.spriteSize.height, 160*scale)
            XCTAssertEqual(layout.spriteSize.width/layout.spriteSize.height, 192.0/208.0, accuracy: 0.001)
            let bottom = layout.spritePosition.y-layout.spriteSize.height*(1-202.0/208.0)
            XCTAssertEqual(bottom, 4, accuracy: 0.001)
            XCTAssertLessThanOrEqual(bottom+layout.spriteSize.height, layout.windowSize.height)
            let left = layout.spritePosition.x-layout.spriteSize.width*100.0/192.0
            XCTAssertEqual(left, 4, accuracy: 0.001)
            XCTAssertLessThanOrEqual(left+layout.spriteSize.width, layout.windowSize.width)
        }
    }
}
