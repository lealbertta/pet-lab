// Validate the final animation pixels, independently of the rig authoring pass.
import Foundation
import CoreGraphics
import ImageIO
let folders=["dog-20-french-bulldog","dog-21-corgi","dog-22-dachshund","dog-23-bernedoodle"]
let size=320
func frames(_ root:String,_ animation:[String:Any])->[[UInt8]] {
 let im=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath:root+"/"+(animation["image"] as! String)) as CFURL,nil)!,0,nil)!
 return (animation["frames"] as! [Int]).map { index in
  let part=im.cropping(to:CGRect(x:index%4*size,y:index/4*size,width:size,height:size))!
  let c=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  c.draw(part,in:CGRect(x:0,y:0,width:size,height:size));return Array(UnsafeBufferPointer(start:c.data!.assumingMemoryBound(to:UInt8.self),count:size*size*4))
 }
}
for (breed,folder) in folders.enumerated(){
 let root="packs/\(folder)",manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:root+"/manifest.json"))) as! [String:Any]
 let animations=manifest["animations"] as! [String:[String:Any]]
 var largestDelta=0.0
 for (state,animation) in animations {
  let images=frames(root,animation);precondition(images.count==8)
  for (step,p) in images.enumerated(){
   for y in 0..<size {for x in 0..<size where x<8 || x>=size-8 || y<8 || y>=size-8 {
    precondition(p[(y*size+x)*4+3]<40,"Clipped/stray artwork: \(folder) \(state) \(step)")
   }}
   if !["spawn","retire"].contains(state) || step<images.count-1 {
    let next=images[(step+1)%images.count]
    let delta=zip(p,next).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(p.count*255)
    precondition(delta<0.025,"Abrupt frame or loop seam: \(folder) \(state) \(step)")
    largestDelta=max(largestDelta,delta)
   }
   if state=="working" {
    let base=images[0]
    for y in 0..<size {for x in 0..<size {
     let pinned:Bool
     switch breed {
      case 0:pinned=x>=193 && x<280 && y>=188 && y<256 // laptop
      case 1:pinned = !(x>=111 && x<192 && y>=198 && y<239) // all except paws
      case 2:pinned=x>=190 && x<285 && y>=203 && y<256 // glass and clues
      default:pinned=x>=235 && x<280 && y>=219 && y<256 // plant pot
     }
     if pinned {let a=(y*size+x)*4;precondition(p[a..<a+4].elementsEqual(base[a..<a+4]),"Static object moved: \(folder) \(step) at \(x),\(y)")}
    }}
   }
  }
 }
 let work=frames(root,animations["working"]!)
 precondition(work.dropFirst().contains{$0 != work[0]},"Working rig must animate")
 print("\(folder): 72 clear frames, pinned working props, cyclic continuity; largest step \(String(format:"%.3f",largestDelta*100))%")
}
