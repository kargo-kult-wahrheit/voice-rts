import CoreGraphics
import Foundation

/// The simulation receives a grid measured from the finished terrain layer.
/// Unit sprites, place labels, and the optional debug overlay are drawn later.
struct TerrainArt {
    static let scale = 28
    static let width = FieldMap.columns * scale, height = FieldMap.rows * scale
    let image: CGImage
    let map: FieldMap

    init() {
        let w = Self.width, h = Self.height, s = Double(Self.scale)
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let wy = (Double(y) + 0.5) / s, bank = Self.riverX(wy)
            for x in 0..<w {
                let wx = (Double(x) + 0.5) / s
                let ground = Self.paintAt(wx, wy, bank)
                let (r, g, b) = ground.color
                let grain = (Self.hash(x, y) % 9) - 4
                let wash = Int(3 * sin(wx * 0.44 + wy * 0.65) + 3 * cos(wx * 1.8 - wy * 0.71))
                let n = grain + wash
                let i = (y * w + x) * 4
                pixels[i] = UInt8(r + n); pixels[i + 1] = UInt8(g + n); pixels[i + 2] = UInt8(b + n)
            }
        }
        pixels.withUnsafeMutableBytes { buffer in
            let cg = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            cg.translateBy(x: 0, y: CGFloat(h))
            cg.scaleBy(x: s, y: -s)
            cg.setLineCap(.round); cg.setLineJoin(.round)
            Self.decorate(cg)
        }
        let data = Data(pixels) as CFData
        image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        map = Self.recognize(pixels)
    }

    static func recognize(_ rgba: [UInt8]) -> FieldMap {
        precondition(rgba.count == width * height * 4)
        let colors = Ground.allCases.map(\.color)
        var tiles: [Ground] = []
        // A majority vote tolerates grass strokes, individual trees, and plank outlines.
        for row in 0..<FieldMap.rows {
            for col in 0..<FieldMap.columns {
                var votes = Array(repeating: 0, count: colors.count)
                for y in [4, 9, 14, 19, 24] {
                    for x in [4, 9, 14, 19, 24] {
                        let i = ((row * scale + y) * width + col * scale + x) * 4
                        let r = Int(rgba[i]), g = Int(rgba[i + 1]), b = Int(rgba[i + 2])
                        var best = 0, distance = Int.max
                        for (j, c) in colors.enumerated() {
                            let dr = r - c.0, dg = g - c.1, db = b - c.2
                            let d = dr * dr + dg * dg + db * db
                            if d < distance { best = j; distance = d }
                        }
                        votes[best] += 1
                    }
                }
                let winner = votes.indices.max { votes[$0] < votes[$1] }!
                tiles.append(Ground(rawValue: winner)!)
            }
        }
        return FieldMap(tiles: tiles)
    }

    static func hash(_ x: Int, _ y: Int) -> Int {
        var n = UInt32(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263)
        n = (n ^ (n >> 13)) &* 1274126177
        return Int(n ^ (n >> 16))
    }
    private static func riverX(_ y: Double) -> Double { 20 + 1.65 * sin(y * 0.32) + 0.63 * sin(y * 0.74) }
    private static let woods = [(8.4,4.2,3.7,2.35),(11.5,19.5,3.6,2.4),(30.7,4.2,4.2,2.2),
                                (31.5,20.5,3.7,2.2),(24.9,10.2,2.1,1.7),(2.0,1.2,2.3,1.4)]
    private static let rocks = [(12.3,9.0,2.5,1.45),(29.7,15.7,2.8,1.55),(24.5,1.3,1.75,1.1),
                                (4.1,21.7,2.0,1.25)]
    private static func paintAt(_ x: Double, _ y: Double, _ bank: Double) -> Ground {
        for crossing in [5.5, 18.5] where abs(y - crossing) < 0.79 && abs(x - riverX(crossing)) < 2.8 { return .bridge }
        if abs(x - bank) < 1.32 + 0.13 * sin(y * 1.43) { return .river }
        let rough = 0.13 * sin(x * 3.7 + y * 2.5) + 0.10 * cos(y * 4.3 - x * 2)
        for (cx, cy, rx, ry) in woods {
            let dx = (x - cx) / rx, dy = (y - cy) / ry
            if dx * dx + dy * dy < 1 + rough { return .forest }
        }
        for (cx, cy, rx, ry) in rocks {
            let dx = (x - cx) / rx, dy = (y - cy) / ry
            if dx * dx + dy * dy < 1 + rough { return .rock }
        }
        return .meadow
    }

    private static func decorate(_ c: CGContext) {
        func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
            CGColor(red: r, green: g, blue: b, alpha: a)
        }
        func stroke(_ pts: [(Double, Double)], _ ink: CGColor, _ width: Double) {
            c.beginPath(); c.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
            for p in pts.dropFirst() { c.addLine(to: CGPoint(x: p.0, y: p.1)) }
            c.setStrokeColor(ink); c.setLineWidth(width); c.strokePath()
        }
        func shape(_ pts: [(Double, Double)], _ ink: CGColor) {
            c.beginPath(); c.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
            for p in pts.dropFirst() { c.addLine(to: CGPoint(x: p.0, y: p.1)) }
            c.closePath(); c.setFillColor(ink); c.fillPath()
        }
        let grass = color(0.36, 0.41, 0.23, 0.44), wood = color(0.29, 0.39, 0.26)
        let needles = color(0.39, 0.51, 0.34), light = color(0.59, 0.66, 0.44)
        let stone = color(0.46, 0.45, 0.43), facet = color(0.68, 0.66, 0.59)
        for row in 0..<(FieldMap.rows * 2) {
            for col in 0..<(FieldMap.columns * 2) {
                let h = hash(col, row)
                let x = Double(col) / 2 + Double(h % 39) / 100
                let y = Double(row) / 2 + Double((h >> 8) % 37) / 100
                switch paintAt(x, y, riverX(y)) {
                case .meadow where h % 5 == 0:
                    stroke([(x-0.08,y-0.10),(x,y),(x+0.06,y-0.16)], grass, 0.035)
                    if h % 3 == 0 { stroke([(x+0.16,y+0.03),(x+0.22,y-0.05)], grass, 0.03) }
                case .forest:
                    let z = 0.32 + Double(h % 17) / 100
                    stroke([(x,y),(x,y+0.14)], wood, 0.067)
                    shape([(x-z*0.48,y+0.02),(x,y-z*1.24),(x+z*0.49,y+0.02)], wood)
                    shape([(x-z*0.37,y-z*0.12),(x,y-z*1.21),(x+z*0.02,y-z*0.16)], needles)
                    stroke([(x-z*0.25,y-z*0.52),(x,y-z*1.2)], light, 0.027)
                case .rock where h % 3 != 0:
                    let z = 0.24 + Double(h % 25) / 100
                    shape([(x-z,y),(x-0.04,y-z*0.87),(x+z*0.29,y-z*0.72),(x+z,y+z*0.07)], stone)
                    shape([(x-z,y),(x-0.04,y-z*0.87),(x+z*0.07,y-z*0.31)], facet)
                    stroke([(x-z*0.7,y+0.09),(x+z*0.69,y+0.10)], stone, 0.035)
                case .river where h % 2 == 0:
                    stroke([(x-0.21,y),(x-0.08,y-0.04),(x+0.17,y-0.02)], color(0.76,0.85,0.76,0.53), 0.034)
                default: break
                }
            }
        }
        for side in [-1.0, 1.0] {
            var line: [(Double,Double)] = []
            for j in 0...240 {
                let y = Double(j) / 10
                if abs(y-5.5) < 0.87 || abs(y-18.5) < 0.87 {
                    if line.count > 1 { stroke(line, color(0.87,0.84,0.62,0.85), 0.085) }
                    line.removeAll(); continue
                }
                line.append((riverX(y) + side * (1.32 + 0.13 * sin(y*1.43)), y))
            }
            if line.count > 1 { stroke(line, color(0.87,0.84,0.62,0.85), 0.085) }
        }
        for y in [5.5,18.5] {
            let x = riverX(y), rail = color(0.41,0.30,0.19)
            for j in 0...17 {
                let px = x - 2.74 + Double(j) * 0.32
                stroke([(px,y-0.72),(px+0.03,y+0.72)], color(0.51,0.38,0.25), 0.051)
            }
            for d in [-0.74, 0.74] {
                stroke([(x-2.78,y+d),(x+2.78,y+d)], rail, 0.11)
                for post in [-2.7,-1.35,0,1.35,2.7] {
                    c.setFillColor(rail); c.fillEllipse(in: CGRect(x:x+post-0.09,y:y+d-0.09,width:0.18,height:0.18))
                }
            }
        }
    }
}
