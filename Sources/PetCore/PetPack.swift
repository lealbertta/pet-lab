import Foundation
import ImageIO

public struct PackManifest: Codable {
    public var formatVersion: Int
    public var id: String
    public var name: String
    public var author: String
    public var license: String
    public var artworkVersion: String
    public var rendering: Rendering
    public var animations: [String: Animation]
    public struct Rendering: Codable {
        public var frameSize: [Int]
        public var anchor: [Int]
        public var displayHeight: Int
        public var filtering: String
    }
    public struct Animation: Codable {
        public var image: String
        public var frames: [Int]
        public var frameDurationMs: Int
        public var frameDurationsMs: [Int]?
        /// Per-reference translation in source pixels: positive x right, positive y down.
        public var frameOffsets: [[Int]]?
        public var facing: String?
        public var allowMirror: Bool?
        public func anchor(at index: Int, rendering: Rendering) -> CGPoint {
            let offset = frameOffsets?[index] ?? [0, 0]
            return CGPoint(x: Double(rendering.anchor[0] - offset[0]) / Double(rendering.frameSize[0]),
                           y: 1 - Double(rendering.anchor[1] - offset[1]) / Double(rendering.frameSize[1]))
        }
        public func duration(at index: Int) -> Double {
            Double(frameDurationsMs?[index] ?? frameDurationMs) / 1000
        }
    }
}

public struct PackError: LocalizedError {
    public var message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct LoadedPack {
    public let root: URL
    public let manifest: PackManifest
    public let decodedBytes: Int
    public static let required = ["idle", "walk", "working", "retire"]
    public static let allowed = Set(required + ["spawn", "attention", "success", "error", "sleep"])
    // Provisional engineering limits, not benchmark-derived compatibility commitments.
    public static let maxDecodedBytes = 64 * 1024 * 1024

    public init(directory: URL) throws {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        let manifestURL = root.appendingPathComponent("manifest.json")
        guard manifestURL.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else {
            throw PackError(message: "Manifest escapes pack")
        }
        guard let size = try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 65536 else {
            throw PackError(message: "Manifest exceeds 64 KiB")
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let m = try JSONDecoder().decode(PackManifest.self, from: manifestData)
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw PackError(message: message) }
        }
        if let object = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] {
            try require(Set(object.keys).isSubset(of: ["formatVersion", "id", "name", "author", "license", "artworkVersion", "rendering", "animations"]), "Unknown manifest property")
            if let rendering = object["rendering"] as? [String: Any] {
                try require(Set(rendering.keys).isSubset(of: ["frameSize", "anchor", "displayHeight", "filtering"]), "Unknown rendering property")
            }
            if let animations = object["animations"] as? [String: [String: Any]] {
                for animation in animations.values {
                    try require(Set(animation.keys).isSubset(of: ["image", "frames", "frameDurationMs", "frameDurationsMs", "frameOffsets", "facing", "allowMirror"]), "Unknown animation property")
                }
            }
        }
        try require(m.formatVersion == 1, "Unsupported formatVersion")
        try require(!m.id.isEmpty && !m.name.isEmpty && !m.author.isEmpty && !m.license.isEmpty && !m.artworkVersion.isEmpty, "Missing pack metadata")
        try require(m.rendering.frameSize.count == 2 && m.rendering.anchor.count == 2, "Frame size and anchor require two coordinates")
        let w = m.rendering.frameSize[0], h = m.rendering.frameSize[1]
        try require((1...1024).contains(w) && (1...1024).contains(h), "Frames must be 1–1024 pixels per side")
        try require((0...w).contains(m.rendering.anchor[0]) && (0...h).contains(m.rendering.anchor[1]), "Anchor outside frame")
        try require((16...256).contains(m.rendering.displayHeight), "Display height must be 16–256 points")
        try require(["nearest", "linear"].contains(m.rendering.filtering), "Unknown filtering mode")
        try require(Set(Self.required).isSubset(of: Set(m.animations.keys)), "Required animations: idle, walk, working, retire")
        try require(Set(m.animations.keys).isSubset(of: Self.allowed), "Unknown animation name")
        try require(m.animations.values.reduce(0) { $0 + $1.frames.count } <= 256, "Pack exceeds 256 referenced frames")
        var bytes = 0
        var inspected: Set<String> = []
        for (name, animation) in m.animations {
            try require((1...64).contains(animation.frames.count), "\(name): requires 1–64 frames")
            try require((16...2000).contains(animation.frameDurationMs), "\(name): duration must be 16–2000 ms")
            if let durations = animation.frameDurationsMs {
                try require(durations.count == animation.frames.count && durations.allSatisfy { (16...2000).contains($0) }, "\(name): invalid per-frame durations")
            }
            if let offsets = animation.frameOffsets {
                try require(offsets.count == animation.frames.count, "\(name): offsets must match frame count")
                for offset in offsets {
                    try require(offset.count == 2 && offset.allSatisfy { (-1024...1024).contains($0) }, "\(name): invalid frame offset")
                    try require((0...w).contains(m.rendering.anchor[0] - offset[0]) &&
                                (0...h).contains(m.rendering.anchor[1] - offset[1]), "\(name): offset moves anchor outside frame")
                }
            }
            try require(animation.facing == nil || ["left", "right"].contains(animation.facing!), "\(name): invalid facing")
            let parts = animation.image.split(separator: "/", omittingEmptySubsequences: false)
            try require(!animation.image.hasPrefix("/") && !animation.image.contains("\\") && !parts.contains("..") && !parts.contains("."), "\(name): unsafe image path")
            let imageURL = root.appendingPathComponent(animation.image).resolvingSymlinksInPath()
            try require(imageURL.path.hasPrefix(root.path + "/"), "\(name): image escapes pack")
            try require(imageURL.pathExtension.lowercased() == "png", "\(name): prototype accepts PNG only")
            guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else {
                throw PackError(message: "\(name): unreadable image")
            }
            try require((CGImageSourceGetType(source) as String?) == "public.png", "\(name): image must actually be PNG")
            try require((properties[kCGImagePropertyDepth] as? Int) == 8, "\(name): PNG must use 8-bit channels")
            try require(width > 0 && height > 0 && width <= 4096 && height <= 4096, "\(name): sheet exceeds 4096 pixels per side")
            try require(width % w == 0 && height % h == 0, "\(name): sheet does not align to frame grid")
            let count = (width / w) * (height / h)
            try require(animation.frames.allSatisfy { $0 >= 0 && $0 < count }, "\(name): frame outside sheet")
            if inspected.insert(imageURL.path).inserted { bytes += width * height * 4 }
            try require(bytes <= Self.maxDecodedBytes, "Pack exceeds 64 MiB decoded pixel budget")
        }
        self.root = root; self.manifest = m; self.decodedBytes = bytes
    }
}
