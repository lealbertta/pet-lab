import Foundation

public struct PetPreferences: Codable, Equatable {
    public var sizeScale: Double
    public var allowWandering: Bool
    public var showSessionLabels: Bool
    public var multicats: Bool?
    public var disabledSprites: [String]

    public init(sizeScale: Double = 1, allowWandering: Bool = true, showSessionLabels: Bool = true, multicats: Bool? = nil, disabledSprites: [String] = []) {
        self.sizeScale = sizeScale.isFinite ? min(max(sizeScale, 0.5), 2) : 1
        self.allowWandering = allowWandering
        self.showSessionLabels = showSessionLabels
        self.multicats = multicats
        self.disabledSprites = disabledSprites
    }

    enum CodingKeys: String, CodingKey { case sizeScale, allowWandering, showSessionLabels, multicats, disabledSprites }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(sizeScale: try values.decodeIfPresent(Double.self, forKey: .sizeScale) ?? 1,
                  allowWandering: try values.decodeIfPresent(Bool.self, forKey: .allowWandering) ?? true,
                  showSessionLabels: try values.decodeIfPresent(Bool.self, forKey: .showSessionLabels) ?? true,
                  multicats: try values.decodeIfPresent(Bool.self, forKey: .multicats),
                  disabledSprites: try values.decodeIfPresent([String].self, forKey: .disabledSprites) ?? [])
    }

    public static func load(from url: URL) -> PetPreferences {
        guard let data = try? Data(contentsOf: url), data.count <= 4096,
              let preferences = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return preferences
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public struct PetSizeLayout {
    public let spriteSize: CGSize
    public let windowSize: CGSize
    public let spritePosition: CGPoint
    public init(frameSize: [Int], anchor: [Int], displayHeight: Int, scale: Double) {
        let bounded = PetPreferences(sizeScale: scale).sizeScale
        let height = CGFloat(displayHeight) * bounded
        let width = height * CGFloat(frameSize[0]) / CGFloat(frameSize[1])
        spriteSize = CGSize(width: width, height: height)
        windowSize = CGSize(width: width + 8, height: height + 24)
        spritePosition = CGPoint(x: width * CGFloat(anchor[0])/CGFloat(frameSize[0]) + 4,
                                 y: height * (1 - CGFloat(anchor[1])/CGFloat(frameSize[1])) + 4)
    }
}
