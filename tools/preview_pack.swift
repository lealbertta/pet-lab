// Export previews from the actual manifest frames; does not alter the artwork.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Usage: swift preview_pack.swift PACK OUTPUT") }
let root = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("manifest.json"))) as! [String: Any]
let rendering = manifest["rendering"] as! [String: Any]
let size = rendering["frameSize"] as! [Int]
let animations = manifest["animations"] as! [String: [String: Any]]
let names = ["idle", "walk", "working", "attention", "success", "error", "sleep", "spawn", "retire"]
var frames: [String: [CGImage]] = [:], durations: [String: [Int]] = [:]
for name in names {
    guard let animation = animations[name] else { continue }
    let source = CGImageSourceCreateWithURL(root.appendingPathComponent(animation["image"] as! String) as CFURL, nil)!
    let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    let columns = sheet.width / size[0], indices = animation["frames"] as! [Int]
    frames[name] = indices.map { sheet.cropping(to: CGRect(x: ($0 % columns)*size[0], y: ($0 / columns)*size[1], width: size[0], height: size[1]))! }
    durations[name] = animation["frameDurationsMs"] as? [Int] ?? Array(repeating: animation["frameDurationMs"] as! Int, count: indices.count)
}
func bitmap(_ width: Int, _ height: Int) -> CGContext {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .none
    return context
}
func gif(_ filename: String, _ images: [CGImage], _ delays: [Int]) {
    let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(filename) as CFURL, UTType.gif.identifier as CFString, images.count, nil)!
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (index, image) in images.enumerated() {
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: Double(delays[index])/1000, kCGImagePropertyGIFUnclampedDelayTime: Double(delays[index])/1000]] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(destination))
}
for name in names where frames[name] != nil {
    let images = frames[name]!.map { frame -> CGImage in
        let context = bitmap(size[0], size[1]); context.draw(frame, in: CGRect(x: 0, y: 0, width: size[0], height: size[1])); return context.makeImage()!
    }
    gif("\(name).gif", images, durations[name]!)
}
var overview: [CGImage] = []
for tick in 0..<100 {
    let context = bitmap(660, 720)
    for (index, name) in names.enumerated() where frames[name] != nil {
        let times = durations[name]!, elapsed = tick*100 % times.reduce(0,+)
        var frame = 0, boundary = times[0]
        while elapsed >= boundary && frame+1 < times.count { frame += 1; boundary += times[frame] }
        let x = (index % 3)*220, y = 720-(index/3+1)*240
        context.draw(frames[name]![frame], in: CGRect(x: x+5, y: y+30, width: 209, height: 209))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (name.capitalized as NSString).draw(at: NSPoint(x: x+70, y: y+10), withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.darkGray])
        NSGraphicsContext.restoreGraphicsState()
    }
    overview.append(context.makeImage()!)
}
gif("all-animations.gif", overview, Array(repeating: 100, count: overview.count))
print("Exported \(frames.count) animations and a 10-second overview to \(output.path)")
