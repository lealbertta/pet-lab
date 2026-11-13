// Repack a generated 4 x 9 grid into uniform square cells; no artwork is redrawn.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Usage: prepare-dog-atlas.swift INPUT OUTPUT") }
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
let source = CGImageSourceCreateWithURL(input as CFURL, nil)!
let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let cellWidth = Double(sheet.width) / 4, cellHeight = Double(sheet.height) / 9
let size = 256
// Generated rows are not perfectly regular: a jumping ear can cross a nominal
// cell boundary. Find each column's nine occupied bands before cutting cells.
let pixels = CGContext(data: nil, width: sheet.width, height: sheet.height, bitsPerComponent: 8,
    bytesPerRow: sheet.width*4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
pixels.draw(sheet, in: CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
let rgba = pixels.data!.assumingMemoryBound(to: UInt8.self)
var bands: [[ClosedRange<Int>]] = []
for col in 0..<4 {
    var found: [ClosedRange<Int>] = [], start: Int? = nil, last = 0
    for y in 0..<sheet.height {
        let occupied = (Int(Double(col)*cellWidth)..<Int(Double(col+1)*cellWidth)).reduce(0) {
            $0 + (rgba[(y*sheet.width+$1)*4+3] > 180 ? 1 : 0)
        } >= 8
        if occupied { if start == nil { start = y }; last = y }
        else if let first = start, y-last > 6 {
            if last-first > 30 { found.append(first...last) }; start = nil
        }
    }
    if let first = start, last-first > 30 { found.append(first...last) }
    precondition(found.count == 9, "Expected nine isolated sprite bands in column \(col)")
    bands.append(found)
}
let context = CGContext(data: nil, width: size*4, height: size*9, bitsPerComponent: 8,
    bytesPerRow: size*16, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.interpolationQuality = .high
for row in 0..<9 { for col in 0..<4 {
    let band = bands[col][row]
    let top = max(0, band.lowerBound-4), bottom = min(sheet.height, band.upperBound+5)
    let rect = CGRect(x: Double(col)*cellWidth, y: Double(top),
                      width: cellWidth, height: Double(bottom-top)).integral
    let frame = sheet.cropping(to: rect)!
    let height = Double(frame.height)*232/cellHeight
    context.draw(frame, in: CGRect(x: Double(col*size+12), y: Double((8-row)*size+24), width: 232, height: height))
}}
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
print("Repacked \(sheet.width)x\(sheet.height) grid into 36 256px frames")
