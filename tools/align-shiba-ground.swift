// Translate generated frames onto the manifest's shared ground line.
// Artwork is not redrawn; the success hop retains its authored lift.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[1])
var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("manifest.json"))) as! [String: Any]
var rendering = manifest["rendering"] as! [String: Any]
let size = rendering["frameSize"] as! [Int], anchor = rendering["anchor"] as! [Int]
let animations = manifest["animations"] as! [String: [String: Any]]
let files = Set(animations.values.map { $0["image"] as! String })
let checkOnly = CommandLine.arguments.contains("--check")
let padding = checkOnly ? 0 : 32
let targetSize = [size[0]+padding*2,size[1]+padding*2]
let targetAnchor = [anchor[0]+padding,anchor[1]+padding]
var report: [[String: Any]] = []
func context(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
for file in files.sorted() {
    let url = root.appendingPathComponent(file)
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    let columns = sheet.width/size[0], rows = sheet.height/size[1]
    let output = context(columns*targetSize[0],rows*targetSize[1])
    output.interpolationQuality = .none
    let used = Set(animations.values.filter { $0["image"] as! String == file }.flatMap { $0["frames"] as! [Int] })
    for index in 0..<(columns*rows) {
        let column=index%columns, row=index/columns
        let frame = sheet.cropping(to: CGRect(x:column*size[0],y:row*size[1],width:size[0],height:size[1]))!
        if !used.contains(index) { continue }
        let pixels = context(size[0],size[1])
        pixels.draw(frame,in:CGRect(x:0,y:0,width:size[0],height:size[1]))
        let rgba = pixels.data!.assumingMemoryBound(to: UInt8.self)
        // Require several opaque pixels per row so detached soft specks do not set the baseline.
        let supported = (0..<size[1]).filter { y in
            (0..<size[0]).reduce(0) { count,x in count + (rgba[(y*size[0]+x)*4+3] >= 180 ? 1 : 0) } >= 4
        }
        guard let bottom = supported.last, let top = supported.first else { fatalError("Empty frame") }
        let lift = file == "sprites/atlas.png" && index == 18 ? 12 : 0
        let desiredBottom = targetAnchor[1]-1-lift
        let shift = desiredBottom-bottom
        if checkOnly { precondition(shift == 0, "Ground drift in \(file) frame \(index): \(shift)") }
        precondition(top+shift >= 0, "Alignment would clip solid artwork: \(file) frame \(index)")
        let rect=CGRect(x:column*targetSize[0],y:(rows-row-1)*targetSize[1],width:targetSize[0],height:targetSize[1])
        output.saveGState(); output.clip(to:rect)
        output.draw(frame,in:CGRect(x:column*targetSize[0]+padding,y:rows*targetSize[1]-row*targetSize[1]-shift-size[1],width:size[0],height:size[1]))
        output.restoreGState()
        report.append(["sheet":file,"frame":index,"originalBottom":bottom,"shiftY":shift,"ground":desiredBottom+1,"intentionalLift":lift])
    }
    if !checkOnly {
        let dest=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(dest,output.makeImage()!,nil)
        precondition(CGImageDestinationFinalize(dest))
    }
}
let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
if !checkOnly {
    try data.write(to:root.appendingPathComponent("ground-alignment.json"))
    rendering["frameSize"] = targetSize
    rendering["anchor"] = targetAnchor
    rendering["displayHeight"] = Int((Double(rendering["displayHeight"] as! Int)*Double(targetSize[1])/Double(size[1])).rounded())
    manifest["rendering"] = rendering
    try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("manifest.json"))
}
print("\(checkOnly ? "Verified" : "Aligned") \(report.count) frames: \(root.lastPathComponent)")
