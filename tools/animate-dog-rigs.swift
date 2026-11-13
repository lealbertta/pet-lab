// Deterministic animation from fixed artwork: local deformation, never redrawn frames.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let folders=["dog-20-french-bulldog","dog-21-corgi","dog-22-dachshund","dog-23-bernedoodle"]
let states=["idle","walk","working","attention","success","error","sleep","spawn","retire"]
let s=320,n=8
func context(_ w:Int,_ h:Int)->CGContext {CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!}
func pixels(_ im:CGImage)->[UInt8] {let c=context(s,s);c.draw(im,in:CGRect(x:0,y:0,width:s,height:s));return Array(UnsafeBufferPointer(start:c.data!.assumingMemoryBound(to:UInt8.self),count:s*s*4))}
func image(_ p:[UInt8])->CGImage {let c=context(s,s);p.withUnsafeBytes {c.data!.copyMemory(from:$0.baseAddress!,byteCount:p.count)};return c.makeImage()!}
func write(_ im:CGImage,_ path:String){let d=CGImageDestinationCreateWithURL(URL(fileURLWithPath:path) as CFURL,UTType.png.identifier as CFString,1,nil)!;CGImageDestinationAddImage(d,im,nil);precondition(CGImageDestinationFinalize(d))}
func smooth(_ x:Double)->Double {let z=max(0,min(1,x));return z*z*(3-2*z)}
struct Field {
 let x0:Double,y0:Double,x1:Double,y1:Double,dx:Double,dy:Double
 func weight(_ x:Double,_ y:Double)->Double {
  let f=min(12,min((x1-x0)/3,(y1-y0)/3))
  return smooth((x-x0)/f)*smooth((x1-x)/f)*smooth((y-y0)/f)*smooth((y1-y)/f)
 }
}
func field(_ r:[Double],_ dx:Double,_ dy:Double)->Field {Field(x0:r[0],y0:r[1],x1:r[2],y1:r[3],dx:dx,dy:dy)}
var report:[[String:Any]]=[]
for (breed,folder) in folders.enumerated(){
 let root="packs/\(folder)",basePath="artifacts/dogs/rig-bases/\(folder).png"
 let src=CGImageSourceCreateWithURL(URL(fileURLWithPath:basePath) as CFURL,nil)!
 let atlas=CGImageSourceCreateImageAtIndex(src,0,nil)!
 var manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:root+"/manifest.json"))) as! [String:Any]
 var animations:[String:Any]=[:]
 func reference(_ index:Int)->[UInt8] {pixels(atlas.cropping(to:CGRect(x:index%4*s,y:index/4*s,width:s,height:s))!)}
 for (row,state) in states.enumerated(){
  let chosen:Int
  switch row {
   case 3: chosen=[15,14,15,14][breed]
   case 4: chosen=[17,16,16,16][breed]
   case 5: chosen=[22,22,22,22][breed]
   case 7: chosen=31
   case 8: chosen=35
   default:chosen=row*4
  }
  let base=reference(chosen),out=context(s*4,s*2)
  // Retain the approved painted water droplets as an independently moving layer.
  let waterSource = breed==3 && row==2 ? reference(10) : []
  var water:[(Int,Int,[UInt8])]=[]
  if !waterSource.isEmpty {
   for y in 186..<232 {for x in 202..<246 {
    let a=(y*s+x)*4,r=Double(waterSource[a]),g=Double(waterSource[a+1]),b=Double(waterSource[a+2])
    if waterSource[a+3]>60 && g>r*1.25 && b>r*1.25 {water.append((x,y,Array(waterSource[a..<a+4])))}
   }}
  }
  var maximumStep=0.0,frames:[[UInt8]]=[]
  for frame in 0..<n {
   let t=Double(frame)*2*Double.pi/Double(n),wave=sin(t),bounce=(1-cos(t))/2
   var fields:[Field]=[],rootY=0.0,scaleY=1.0
   switch row {
   case 0:
    // Quiet breathing and one breed-specific ear/tail movement; grounded paws stay fixed.
    fields=[field([85,130,230,246],0,-1.2*wave)]
    if breed==0 {fields.append(field([86,73,130,139],1.6*wave,0))}
    if breed==1 {fields.append(field([49,158,112,229],0,2.2*wave))}
    if breed==2 {fields.append(field([123,99,232,202],1.5*wave,-0.7*wave))}
    if breed==3 {fields.append(field([76,105,126,190],1.8*wave,0.8*wave))}
   case 1:
    let stride=breed==1 ? 5.0:3.5
    fields=[field([70,207,138,254],stride*wave,-2.3*bounce),field([157,207,235,254],-stride*wave,-2.3*(1-bounce)),field([81,115,238,214],0,-0.8*wave),field([49,129,100,210],1.5*wave,0)]
   case 2:
    if breed==0 {fields=[field([132,198,186,238],0,-4.5*bounce)]}
    if breed==1 {fields=[field([111,198,155,239],0,-5.0*bounce),field([150,198,192,239],0,-5.0*(1-bounce))]}
    if breed==2 {fields=[field([126,109,217,202],1.2*wave,2.0*bounce),field([48,137,104,213],1.8*wave,0)]}
    if breed==3 {fields=[field([121,102,252,212],1.0*wave,2.5*bounce),field([49,136,109,219],0,2.0*wave)]}
   case 3:
    let amp=[2.0,2.5,2.0,2.0][breed]
    fields=[field([83,82,231,204],amp*wave,-bounce),field([120,208,190,251],0,-2.8*bounce)]
   case 4:
    if breed==1 {rootY = -10*bounce}
    else if breed==3 {fields=[field([66,87,248,213],2.2*wave,0),field([53,130,107,220],0,2.2*wave)]}
    else {fields=[field([85,94,234,238],0,-3*bounce),field([53,150,108,231],1.5*wave,0)]}
   case 5:
    fields=[field([83,82,239,212],2.5*wave,1.0*bounce)]
   case 6:
    fields=[field([57,158,268,249],0,-1.5*wave)]
   case 7:
    let progress=Double(frame)/Double(n-1)
    scaleY=0.95+0.05*smooth(progress)
    rootY = -3*sin(progress*Double.pi)
    fields=[field([70,90,239,204],0,-1.2*sin(progress*Double.pi))]
   default:
    let progress=Double(frame)/Double(n-1)
    fields=[field([59,150,267,249],0,1.5*smooth(progress))]
   }
   var p=base
   for y in 0..<s {for x in 0..<s {
    var dx=0.0,dy=rootY
    for f in fields {let w=f.weight(Double(x),Double(y));dx+=f.dx*w;dy+=f.dy*w}
    let sx=Double(x)-dx,sy=(Double(y)-254-dy)/scaleY+254
    if abs(sx-Double(x))<0.000001 && abs(sy-Double(y))<0.000001 {continue}
    let i=(y*s+x)*4
    if sx<0 || sy<0 || sx>=Double(s-1) || sy>=Double(s-1) {for c in 0..<4 {p[i+c]=0};continue}
    let ix=Int(sx),iy=Int(sy),fx=sx-Double(ix),fy=sy-Double(iy)
    for c in 0..<4 {
     let a=Double(base[(iy*s+ix)*4+c]),b=Double(base[(iy*s+ix+1)*4+c])
     let d=Double(base[((iy+1)*s+ix)*4+c]),e=Double(base[((iy+1)*s+ix+1)*4+c])
     p[i+c]=UInt8(max(0,min(255,((a*(1-fx)+b*fx)*(1-fy)+(d*(1-fx)+e*fx)*fy).rounded())))
    }
   }}
   if !water.isEmpty && frame>0 && frame<7 {
    let opacity=sin(Double(frame)*Double.pi/7)
    for (x,y,color) in water {
     let yy=y+frame-3
     if x>=235 && yy>=219 {continue} // keep the plant and pot completely fixed
     let a=(yy*s+x)*4,alpha=Double(color[3])/255*opacity
     for c in 0..<3 {p[a+c]=UInt8(min(255,(Double(color[c])*opacity+Double(p[a+c])*(1-alpha)).rounded()))}
     p[a+3]=UInt8(min(255,(Double(color[3])*opacity+Double(p[a+3])*(1-alpha)).rounded()))
    }
   }
   out.draw(image(p),in:CGRect(x:frame%4*s,y:(1-frame/4)*s,width:s,height:s));frames.append(p)
  }
  for step in 0..<n {
   if [7,8].contains(row) && step==n-1 {continue}
   let a=frames[step],b=frames[(step+1)%n]
   let delta=zip(a,b).reduce(0.0){$0+Double(abs(Int($1.0)-Int($1.1)))}/Double(a.count*255)
   maximumStep=max(maximumStep,delta)
  }
  let durations:[Int]
  switch row {
   case 0:durations=Array(repeating:260,count:n)
   case 1:durations=Array(repeating:[95,75,65,120][breed],count:n)
   case 2:durations=Array(repeating:[120,50,160,190][breed],count:n)
   case 3:durations=Array(repeating:150,count:n)
   case 4:durations=Array(repeating:95,count:n)
   case 5:durations=Array(repeating:130,count:n)
   case 6:durations=Array(repeating:425,count:n)
   default:durations=Array(repeating:120,count:n)
  }
  let filename="sprites/\(state).png"
  write(out.makeImage()!,root+"/"+filename)
  var animation:[String:Any]=["image":filename,"frames":Array(0..<n),"frameDurationMs":durations[0],"frameDurationsMs":durations]
  if row==1 {animation["facing"]="right";animation["allowMirror"]=true}
  animations[state]=animation
  report.append(["pack":folder,"state":state,"referenceFrame":chosen,"frames":n,"maxAdjacentPixelDelta":maximumStep,"maxDisplacementPixels":row==4 && breed==1 ? 10:5])
 }
 manifest["animations"]=animations;manifest["artworkVersion"]="1.1.0"
 try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:root+"/manifest.json"))
 print("\(folder): nine stable rigs, 72 frames")
}
try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:"artifacts/dogs/rig-animation-report.json"))
