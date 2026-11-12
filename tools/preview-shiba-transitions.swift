import AppKit
import ImageIO
import UniformTypeIdentifiers

let folders = ["shiba-16-red","shiba-17-black-tan","shiba-18-sesame","shiba-19-cream"]
let states = ["idle","walk","working","attention","success","error","sleep","spawn","retire","idle"]
let roots = folders.map { URL(fileURLWithPath:"packs/\($0)") }
let manifests = try roots.map { try JSONSerialization.jsonObject(with:Data(contentsOf:$0.appendingPathComponent("manifest.json"))) as! [String:Any] }
let url=URL(fileURLWithPath:"artifacts/shibas/transitions.gif")
try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
let dest=CGImageDestinationCreateWithURL(url as CFURL,UTType.gif.identifier as CFString,states.count*4,nil)!
CGImageDestinationSetProperties(dest,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
for state in states { for step in 0..<4 {
    let ctx=CGContext(data:nil,width:960,height:270,bitsPerComponent:8,bytesPerRow:960*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red:0.98,green:0.96,blue:0.92,alpha:1));ctx.fill(CGRect(x:0,y:0,width:960,height:270))
    ctx.setStrokeColor(CGColor(gray:0.75,alpha:1));ctx.move(to:CGPoint(x:0,y:44));ctx.addLine(to:CGPoint(x:960,y:44));ctx.strokePath()
    ctx.interpolationQuality = .none
    for (i,manifest) in manifests.enumerated() {
        let rendering=manifest["rendering"] as! [String:Any], size=rendering["frameSize"] as! [Int], anchor=rendering["anchor"] as! [Int]
        let animation=(manifest["animations"] as! [String:[String:Any]])[state]!
        let source=CGImageSourceCreateWithURL(roots[i].appendingPathComponent(animation["image"] as! String) as CFURL,nil)!
        let sheet=CGImageSourceCreateImageAtIndex(source,0,nil)!, columns=sheet.width/size[0], index=(animation["frames"] as! [Int])[step]
        let frame=sheet.cropping(to:CGRect(x:index%columns*size[0],y:index/columns*size[1],width:size[0],height:size[1]))!
        let scale=200.0/Double(size[1])
        ctx.draw(frame,in:CGRect(x:Double(i*240+20),y:44-Double(size[1]-anchor[1])*scale,width:200,height:200))
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:false)
        (manifest["name"] as! NSString).draw(at:CGPoint(x:i*240+38,y:16),withAttributes:[.font:NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.darkGray])
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:false)
    (state.capitalized as NSString).draw(at:CGPoint(x:20,y:242),withAttributes:[.font:NSFont.boldSystemFont(ofSize:17),.foregroundColor:NSColor.darkGray])
    NSGraphicsContext.restoreGraphicsState()
    CGImageDestinationAddImage(dest,ctx.makeImage()!,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.35]] as CFDictionary)
}}
precondition(CGImageDestinationFinalize(dest))
