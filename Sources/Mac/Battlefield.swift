import AppKit
import SwiftUI

extension Color {
    init(rgb: Int) {
        self.init(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
    static let ink = Color(rgb: 0x182725), slate = Color(rgb: 0x273b35), paper = Color(rgb: 0xf1edde)
    static let gold = Color(rgb: 0xe7c37c), blueBanner = Color(rgb: 0x2c7893), redBanner = Color(rgb: 0xab4b3e)
}

private func polygon(_ p: [(Double,Double)], close: Bool = true) -> Path {
    var shape = Path()
    shape.move(to: CGPoint(x:p[0].0,y:p[0].1))
    for (x,y) in p.dropFirst() { shape.addLine(to: CGPoint(x:x,y:y)) }
    if close { shape.closeSubpath() }
    return shape
}

/// The same ink-and-color miniature is used on the map and in the roster.
func drawFighter(_ kind: Kind, _ side: Side, context c: GraphicsContext, flash: Bool = false, stride: Double = 0) {
    let dark = Color(rgb:0x33342a), jacket = flash ? Color.white : (side == .blue ? Color.blueBanner : .redBanner)
    let pale = Color(rgb:0xe8d8ac), skin = Color(rgb:0xe3bc8d), steel = Color(rgb:0xc8cec3)
    func line(_ points: [(Double,Double)], _ color: Color, _ width: Double) {
        c.stroke(polygon(points, close:false), with:.color(color), style:StrokeStyle(lineWidth:width,lineCap:.round,lineJoin:.round))
    }
    func fill(_ points: [(Double,Double)], _ color: Color, _ edge: Double = 0.047) {
        let p = polygon(points); c.fill(p,with:.color(color))
        if edge > 0 { c.stroke(p,with:.color(dark),style:StrokeStyle(lineWidth:edge,lineJoin:.round)) }
    }
    func oval(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Color) {
        c.fill(Path(ellipseIn:CGRect(x:x,y:y,width:w,height:h)),with:.color(color))
    }
    oval(-0.40,0.19,0.83,0.21,.black.opacity(0.21))
    let step = 0.07 * sin(stride * 8)
    switch kind {
    case .infantry:
        line([(-0.14,0),(-0.16-step,0.26)],dark,0.13); line([(0.13,0),(0.17+step,0.26)],dark,0.13)
        fill([(-0.22,-0.28),(0.13,-0.27),(0.23,0.12),(-0.26,0.12)],jacket)
        oval(-0.15,-0.53,0.34,0.32,skin)
        fill([(-0.18,-0.39),(-0.16,-0.53),(0.02,-0.62),(0.16,-0.52),(0.22,-0.39)],steel)
        line([(0.33,0.25),(0.39,-0.64)],dark,0.06)
        fill([(0.34,-0.60),(0.40,-0.85),(0.44,-0.59)],steel,0.027)
        fill([(-0.28,-0.24),(0.05,-0.24),(0.06,-0.01),(-0.08,0.18),(-0.26,0.06)],jacket,0.06)
        line([(-0.11,-0.19),(-0.11,0.075)],pale,0.046)
    case .archers:
        line([(-0.11,0),(-0.19-step,0.25)],dark,0.095); line([(0.06,0),(0.15+step,0.24)],dark,0.095)
        fill([(-0.15,-0.25),(0.07,-0.27),(0.17,0.12),(-0.27,0.09)],jacket)
        fill([(-0.22,-0.36),(-0.14,-0.57),(0.07,-0.55),(0.21,-0.35),(0,-0.24)],jacket)
        oval(-0.015,-0.45,0.16,0.16,skin)
        var bow = Path(); bow.move(to:CGPoint(x:0.23,y:-0.55))
        bow.addQuadCurve(to:CGPoint(x:0.23,y:0.14),control:CGPoint(x:0.68,y:-0.20))
        c.stroke(bow,with:.color(dark),lineWidth:0.066)
        line([(0.23,-0.55),(0.16,-0.20),(0.23,0.14)],pale,0.032)
        line([(-0.04,-0.19),(0.38,-0.2)],skin,0.075)
        line([(-0.23,-0.22),(-0.38,-0.52)],dark,0.08)
    case .cavalry:
        for (x,dx) in [(-0.30,-step),(-0.13,step),(0.17,-step),(0.32,step)] {
            line([(x,0.02),(x+dx,0.20),(x+dx-0.05,0.33)],dark,0.075)
        }
        fill([(-0.47,-0.17),(-0.32,-0.25),(0.15,-0.20),(0.32,-0.48),(0.53,-0.42),(0.64,-0.22),
              (0.51,-0.14),(0.37,-0.21),(0.27,0.08),(-0.27,0.14),(-0.42,0.02)],Color(rgb:0x895f3e))
        line([(-0.39,-0.17),(-0.51,-0.04),(-0.59,-0.02)],dark,0.10)
        fill([(-0.23,-0.23),(0.09,-0.22),(0.09,0.01),(-0.12,0.04)],jacket)
        fill([(-0.12,-0.46),(0.04,-0.47),(0.16,-0.20),(-0.16,-0.19)],jacket)
        oval(-0.11,-0.65,0.25,0.23,skin)
        fill([(-0.13,-0.55),(-0.08,-0.68),(0.06,-0.71),(0.16,-0.56)],steel)
        line([(0.07,-0.36),(0.64,-0.61)],pale,0.06)
    }
}

@MainActor struct Battlefield: View {
    @ObservedObject var game: GameStore
    @ObservedObject var clock: FrameClock

    var body: some View {
        ZStack {
            Canvas { c, size in
                let box = CGRect(origin:.zero,size:size)
                c.draw(Image(decorative:game.art.image,scale:1),in:box)
                let scale = size.width / Double(FieldMap.columns)
                var world = c; world.scaleBy(x:scale,y:scale)
                if game.recon { drawRecon(world) }
                camp(world, x:3.9, y:12.6, side:.blue); camp(world, x:35.7, y:12.6, side:.red)
                if !game.recon {
                    for (name,x,y) in [("Pine Grove",8.3,6.8),("North Bridge",21.1,3.7),("South Bridge",19.1,20.3),
                                       ("Slate Ridge",29.7,17.7),("West Camp",3.3,14.2),("East Camp",36.5,14.2)] {
                        let text = Text(name).font(.system(size:max(10,scale * 0.55),weight:.semibold,design:.serif).italic()).foregroundColor(.ink)
                        c.draw(text,at:CGPoint(x:x*scale,y:y*scale))
                    }
                }
                if let mark = game.marker {
                    let x = mark.center.x, y = mark.center.y
                    world.stroke(Path(ellipseIn:CGRect(x:x-0.43,y:y-0.43,width:0.86,height:0.86)),with:.color(.ink),lineWidth:0.075)
                    world.stroke(polygon([(x-0.62,y),(x+0.62,y)],close:false),with:.color(.ink),lineWidth:0.055)
                    world.stroke(polygon([(x,y-0.62),(x,y+0.62)],close:false),with:.color(.ink),lineWidth:0.055)
                }
                for u in game.battle.units.sorted(by: { $0.p.y < $1.p.y }) where u.alive {
                    var sprite = world
                    sprite.translateBy(x:u.p.x,y:u.p.y)
                    if game.selected.contains(u.id) {
                        let ring = Path(ellipseIn:CGRect(x:-0.45,y:0.02,width:0.9,height:0.40))
                        sprite.stroke(ring,with:.color(.ink.opacity(0.68)),lineWidth:0.10)
                        sprite.stroke(ring,with:.color(.gold),lineWidth:0.055)
                    }
                    sprite.scaleBy(x:u.facing,y:1)
                    drawFighter(u.kind,u.side,context:sprite,flash:u.flash > 0,stride:u.gait)
                    if u.hp < u.kind.hp {
                        let r = CGRect(x:u.p.x-0.34,y:u.p.y-0.90,width:0.68,height:0.096)
                        world.fill(Path(r),with:.color(.ink))
                        world.fill(Path(CGRect(x:r.minX,y:r.minY,width:r.width*u.hp/u.kind.hp,height:r.height)),with:.color(u.side == .blue ? .blueBanner : .redBanner))
                    }
                }
                for hit in game.battle.strikes {
                    let t = min(1, hit.age / hit.duration), dx = hit.end.x-hit.start.x, dy = hit.end.y-hit.start.y
                    if hit.ranged {
                        let x = hit.start.x + t*dx, y = hit.start.y + t*dy - 0.46*sin(.pi*t)
                        let p = polygon([(x-dx*0.10,y-dy*0.10),(x,y)],close:false)
                        world.stroke(p,with:.color(.ink),lineWidth:0.095)
                        world.stroke(p,with:.color(.gold),lineWidth:0.043)
                    } else {
                        let p = polygon([(hit.end.x-0.20,hit.end.y+0.12),(hit.end.x+0.18,hit.end.y-0.36)],close:false)
                        world.stroke(p,with:.color(.white.opacity(1-t)),lineWidth:0.10)
                    }
                }
                let compass = CGPoint(x:size.width-27,y:35)
                c.draw(Text("N").font(.system(size:10,weight:.bold,design:.serif)).foregroundColor(.ink),at:CGPoint(x:compass.x,y:compass.y-18))
                c.fill(polygon([(compass.x,compass.y-9),(compass.x-5,compass.y+8),(compass.x,compass.y+4)]),with:.color(.ink))
                c.fill(polygon([(compass.x,compass.y-9),(compass.x+5,compass.y+8),(compass.x,compass.y+4)]),with:.color(.paper))
            }
            MapInput(game:game)
        }
        .aspectRatio(CGFloat(FieldMap.columns)/CGFloat(FieldMap.rows),contentMode:.fit)
        .overlay(Rectangle().strokeBorder(.black.opacity(0.32),lineWidth:1))
        .accessibilityLabel("Alder Crossing battlefield")
    }

    private func camp(_ c: GraphicsContext, x: Double, y: Double, side: Side) {
        let cloth = side == .blue ? Color.blueBanner : .redBanner
        for (dx,dy) in [(-0.45,0.20),(0.37,-0.08)] {
            let xx=x+dx, yy=y+dy
            c.fill(polygon([(xx-0.49,yy+0.32),(xx,yy-0.50),(xx+0.52,yy+0.32)]),with:.color(.paper))
            c.fill(polygon([(xx,yy-0.50),(xx+0.52,yy+0.32),(xx+0.08,yy+0.32)]),with:.color(cloth))
            c.stroke(polygon([(xx-0.49,yy+0.32),(xx,yy-0.50),(xx+0.52,yy+0.32)]),with:.color(.ink),lineWidth:0.046)
        }
        c.stroke(polygon([(x-0.8,y+0.15),(x-0.8,y-1.01)],close:false),with:.color(.ink),lineWidth:0.068)
        c.fill(polygon([(x-0.8,y-1.01),(x-0.16,y-0.97),(x-0.38,y-0.71),(x-0.8,y-0.72)]),with:.color(cloth))
    }
    private func drawRecon(_ c: GraphicsContext) {
        for i in game.art.map.tiles.indices {
            let tile = game.art.map.tiles[i], cell = game.art.map.cell(i)
            let rect = Path(CGRect(x:cell.x,y:cell.y,width:1,height:1))
            if !tile.walkable { c.fill(rect,with:.color(.red.opacity(0.31))) }
            if tile == .forest { c.fill(rect,with:.color(.ink.opacity(0.19))) }
            if tile == .bridge { c.fill(rect,with:.color(.gold.opacity(0.58))) }
            c.stroke(rect,with:.color(.ink.opacity(0.22)),lineWidth:0.025)
        }
        for u in game.battle.units where u.alive && game.selected.contains(u.id) && u.step < u.route.count {
            var route = Path(); route.move(to:CGPoint(x:u.p.x,y:u.p.y))
            for cell in u.route[u.step...] { route.addLine(to:CGPoint(x:cell.center.x,y:cell.center.y)) }
            c.stroke(route,with:.color(.ink.opacity(0.52)),lineWidth:0.13)
            c.stroke(route,with:.color(.gold),style:StrokeStyle(lineWidth:0.068,dash:[0.26,0.13]))
        }
    }
}

private struct MapInput: NSViewRepresentable {
    let game: GameStore
    func makeNSView(context: Context) -> MapHitView { let v = MapHitView(); v.game = game; return v }
    func updateNSView(_ nsView: MapHitView, context: Context) { nsView.game = game }
}

private final class MapHitView: NSView {
    weak var game: GameStore?
    private var start: CGPoint?, dragAt: CGPoint?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private func world(_ p: CGPoint) -> Point { Point(p.x/bounds.width*Double(FieldMap.columns),p.y/bounds.height*Double(FieldMap.rows)) }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self); start = convert(event.locationInWindow,from:nil)
    }
    override func mouseDragged(with event: NSEvent) { dragAt = convert(event.locationInWindow,from:nil); needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        let end = convert(event.locationInWindow,from:nil), shift = event.modifierFlags.contains(.shift)
        if let start, hypot(start.x-end.x,start.y-end.y) > 5 { game?.box(world(start),world(end),additive:shift) }
        else { game?.click(world:world(end),secondary:false,shift:shift) }
        start = nil; dragAt = nil; needsDisplay = true
    }
    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        game?.click(world:world(convert(event.locationInWindow,from:nil)),secondary:true,shift:false)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let a = start, let b = dragAt else { return }
        let box = NSBezierPath(rect:NSRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y)))
        NSColor.systemYellow.withAlphaComponent(0.13).setFill(); box.fill()
        NSColor.white.withAlphaComponent(0.89).setStroke(); box.lineWidth = 1; box.stroke()
    }
}
