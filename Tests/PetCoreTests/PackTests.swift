import XCTest
@testable import PetCore

final class PackTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: repository.appendingPathComponent("packs/starter"), to: root)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func mutate(_ body: (inout [String: Any]) -> Void) throws {
        let url = root.appendingPathComponent("manifest.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        body(&object); try JSONSerialization.data(withJSONObject: object).write(to: url)
    }
    func animation(_ name: String, modify: (inout [String: Any]) -> Void) throws {
        try mutate { object in
            var animations = object["animations"] as! [String: [String: Any]]
            var value = animations[name]!; modify(&value); animations[name] = value
            object["animations"] = animations
        }
    }
    func testValidPack() throws {
        let pack = try LoadedPack(directory: root)
        XCTAssertEqual(pack.manifest.animations["working"]?.frames.count, 8)
        XCTAssertEqual(pack.decodedBytes, 851_968)
    }
    func testRejectsPathTraversal() throws {
        try animation("idle") { $0["image"] = "../outside.png" }
        XCTAssertThrowsError(try LoadedPack(directory: root))
    }
    func testRejectsSymlinkEscape() throws {
        let path = root.appendingPathComponent("sprites/idle.png")
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createSymbolicLink(atPath: path.path, withDestinationPath: "/private/tmp/outside.png")
        XCTAssertThrowsError(try LoadedPack(directory: root))
    }
    func testRejectsUnknownVersionAndMissingRetirement() throws {
        try mutate { $0["formatVersion"] = 2 }
        XCTAssertThrowsError(try LoadedPack(directory: root))
        try mutate { object in
            object["formatVersion"] = 1
            var animations = object["animations"] as! [String: Any]; animations.removeValue(forKey: "retire")
            object["animations"] = animations
        }
        XCTAssertThrowsError(try LoadedPack(directory: root))
    }
    func testRejectsOutOfBoundsFrameAndDurationMismatch() throws {
        try animation("working") { $0["frames"] = [999] }
        XCTAssertThrowsError(try LoadedPack(directory: root))
        try animation("working") { $0["frames"] = [0,1]; $0["frameDurationsMs"] = [100] }
        XCTAssertThrowsError(try LoadedPack(directory: root))
    }
    func testRejectsTooManyFrames() throws {
        try animation("working") { $0["frames"] = Array(repeating: 0, count: 65) }
        XCTAssertThrowsError(try LoadedPack(directory: root))
    }
}
