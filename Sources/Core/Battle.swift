import Foundation

enum Side: Int { case blue, red }
enum Kind: String, CaseIterable, Encodable {
    case archers = "Archers", infantry = "Infantry", cavalry = "Light cavalry"
    var hp: Double { switch self { case .archers: return 58; case .infantry: return 134; case .cavalry: return 82 } }
    var speed: Double { switch self { case .archers: return 1.45; case .infantry: return 1.18; case .cavalry: return 2.52 } }
    var reach: Double { self == .archers ? 4.65 : 1.02 }
    var reload: Double { switch self { case .archers: return 1.65; case .infantry: return 1.18; case .cavalry: return 1.12 } }
    var power: Double { switch self { case .archers: return 12; case .infantry: return 11; case .cavalry: return 10 } }
    var role: String { switch self { case .archers: return "Ranged"; case .infantry: return "Armored melee"; case .cavalry: return "Fast melee" } }
    var symbol: String { switch self { case .archers: return "scope"; case .infantry: return "shield.lefthalf.filled"; case .cavalry: return "hare.fill" } }
}
enum Action: String, CaseIterable, Encodable { case move, attack, hold, retreat }
enum Phase: String, Encodable { case deployment, running, paused, victory, defeat, draw
    var finished: Bool { self == .victory || self == .defeat || self == .draw }
}

struct Order: Encodable {
    let action: Action
    var goal: Cell?
    var focus: Kind?
    var foeID: Int?
    init(_ action: Action, goal: Cell? = nil, focus: Kind? = nil, foeID: Int? = nil) {
        self.action = action; self.goal = goal; self.focus = focus; self.foeID = foeID
    }
}

final class Soldier: Identifiable {
    let id: Int, side: Side, kind: Kind
    var p: Point, hp: Double, order: Order, anchor: Cell
    var route: [Cell] = [], step = 0, routeGoal: Cell?
    var targetID: Int?, cooldown: Double, facing: Double, flash = 0.0, gait = 0.0
    var alive: Bool { hp > 0 }
    init(id: Int, side: Side, kind: Kind, at cell: Cell) {
        self.id = id; self.side = side; self.kind = kind
        p = cell.center; anchor = cell; hp = kind.hp
        order = Order(side == .blue ? .hold : .attack)
        cooldown = 0.10 * Double(id % 8); facing = side == .blue ? 1 : -1
    }
    func stop() { routeGoal = nil; route.removeAll(keepingCapacity: true); step = 0 }
}

struct Strike {
    let start: Point, end: Point, side: Side, ranged: Bool
    var age = 0.0
    var duration: Double { ranged ? 0.29 : 0.15 }
}

final class Battle {
    let map: FieldMap
    private(set) var units: [Soldier] = [], strikes: [Strike] = []
    var phase: Phase = .deployment
    private(set) var elapsed = 0.0
    private var nextDecision = 0.0

    init(map: FieldMap) { self.map = map; reset() }
    func reset() {
        units.removeAll(); strikes.removeAll()
        elapsed = 0; nextDecision = 0; phase = .deployment
        for side in [Side.blue, .red] {
            var used = Set<Cell>()
            for kind in Kind.allCases {
                let count = kind == .infantry ? 8 : (kind == .archers ? 6 : 4)
                for n in 0..<count {
                    let x: Int, y: Int
                    switch kind {
                    case .archers: x = 3 + n % 2; y = 8 + n / 2
                    case .infantry: x = 7 + n % 2; y = 10 + n / 2
                    case .cavalry: x = 5 + n % 2; y = 15 + n / 2
                    }
                    let cell = Cell(side == .blue ? x : FieldMap.columns - 1 - x, y)
                    if let spawn = map.closestOpen(to: cell, excluding: used) {
                        used.insert(spawn)
                        units.append(Soldier(id: units.count, side: side, kind: kind, at: spawn))
                    }
                }
            }
        }
    }
    func living(_ side: Side) -> [Soldier] { units.filter { $0.alive && $0.side == side } }

    @discardableResult
    func issue(_ order: Order, to ids: Set<Int>, onAssigned: ((Soldier) -> Void)? = nil) -> Int {
        guard !phase.finished else { return 0 }
        let soldiers = living(.blue).filter { ids.contains($0.id) }
        let goal = order.goal
        var used = Set<Cell>()
        let slots = formationOffsets(count: soldiers.count)
        for (n, u) in soldiers.enumerated() {
            var assigned = order
            if let goal {
                let offset = slots[n]
                let result = map.closestOpen(to: Cell(goal.x + offset.x, goal.y + offset.y), excluding: used)
                if let result { used.insert(result) }
                assigned.goal = result
            } else if assigned.action == .retreat {
                assigned.goal = map.closestOpen(to: Cell(Landmark.camp.cell.x + slots[n].x, Landmark.camp.cell.y + slots[n].y), excluding: used)
                if let goal = assigned.goal { used.insert(goal) }
            }
            u.order = assigned; u.anchor = assigned.goal ?? u.p.cell; u.targetID = nil
            u.stop()
            if let target = assigned.goal { plan(u, to: target) }
            onAssigned?(u)
        }
        nextDecision = 0
        return soldiers.count
    }

    private func formationOffsets(count: Int) -> [Cell] {
        let radius = max(1, Int(ceil(sqrt(Double(count)))))
        var slots: [Cell] = []
        for y in -radius...radius { for x in -radius...radius { slots.append(Cell(x,y)) } }
        return Array(slots.sorted {
            let a = $0.x * $0.x + $0.y * $0.y, b = $1.x * $1.x + $1.y * $1.y
            if a != b { return a < b }
            return $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y
        }.prefix(count))
    }

    private func plan(_ unit: Soldier, to goal: Cell) {
        if unit.routeGoal == goal { return }
        unit.routeGoal = goal; unit.step = 0
        guard let route = map.route(from: unit.p.cell, to: goal) else {
            unit.stop(); return
        }
        // Rejoin the centerline on replanning so turning mid-step cannot cut a blocked corner.
        unit.route = unit.p.distance(to: unit.p.cell.center) > 0.08 ? [unit.p.cell] + route : route
    }

    private func canHit(_ unit: Soldier, _ foe: Soldier) -> Bool {
        unit.p.distance(to: foe.p) <= unit.kind.reach && map.clearShot(from: unit.p, to: foe.p)
    }

    private func choose(_ unit: Soldier, among enemies: [Soldier]) {
        let order = unit.order
        var goal = order.goal
        var target: Soldier?
        switch order.action {
        case .retreat:
            break
        case .move:
            if goal == nil || unit.p.distance(to: unit.anchor.center) < 0.16 {
                unit.order = Order(.hold); goal = nil
            }
        case .hold:
            if goal != nil && unit.p.distance(to: unit.anchor.center) > 0.3 {
                break
            }
            unit.order.goal = nil
            goal = unit.anchor
            let nearby = enemies.filter { $0.p.distance(to: unit.anchor.center) <= unit.kind.reach + 0.85 }
            target = nearby.min { unit.p.distance(to: $0.p) < unit.p.distance(to: $1.p) }
        case .attack:
            if let id = order.foeID { target = enemies.first { $0.id == id } }
            if target == nil {
                var candidates = enemies
                if let focus = order.focus {
                    let matches = candidates.filter { $0.kind == focus }
                    if !matches.isEmpty { candidates = matches }
                }
                if let rally = order.goal {
                    // En route to a named location, only interrupt the march for nearby enemies.
                    if unit.p.distance(to: rally.center) > 0.65 {
                        candidates = candidates.filter { unit.p.distance(to: $0.p) < unit.kind.reach + 2 }
                    } else { unit.order.goal = nil; goal = nil }
                }
                target = candidates.min { unit.p.distance(to: $0.p) < unit.p.distance(to: $1.p) }
            }
        }
        unit.targetID = target?.id
        if let foe = target {
            if canHit(unit, foe) {
                goal = nil
            } else {
                // Prefer a reachable neighboring contact point when a rock wall separates the pair.
                let slots = map.neighbors(of: foe.p.cell).filter {
                    $0.center.distance(to: foe.p) <= unit.kind.reach && map.clearShot(from: $0.center, to: foe.p)
                }
                goal = slots.min { unit.p.distance(to: $0.center) < unit.p.distance(to: $1.center) } ?? foe.p.cell
            }
        }
        if order.action == .retreat, let home = goal, unit.p.distance(to: home.center) < 0.15 {
            unit.order = Order(.hold); unit.anchor = home; goal = nil
        }
        if let goal { plan(unit, to: goal) } else { unit.stop() }
    }

    private func advance(_ u: Soldier, dt: Double) {
        guard u.step < u.route.count else { return }
        let next = u.route[u.step].center
        let dx = next.x - u.p.x, dy = next.y - u.p.y, distance = hypot(dx, dy)
        let speed = u.kind.speed / map[u.p.cell].cost
        let travel = min(speed * dt, distance)
        if distance < 0.001 { u.step += 1; return }
        let p = Point(u.p.x + dx * travel / distance, u.p.y + dy * travel / distance)
        if map.canStep(from: u.p, to: p) {
            u.p = p; u.gait += travel
            if abs(dx) > 0.09 { u.facing = dx > 0 ? 1 : -1 }
            if travel >= distance { u.step += 1 }
        } else { u.stop() }
    }

    func tick(_ dt: Double) {
        guard phase == .running, dt > 0 else { return }
        elapsed += dt; nextDecision -= dt
        let blue = living(.blue), red = living(.red)
        if nextDecision <= 0 {
            nextDecision = 0.33
            for u in blue { choose(u, among: red) }
            for u in red { choose(u, among: blue) }
        }
        for i in strikes.indices { strikes[i].age += dt }
        strikes.removeAll { $0.age >= $0.duration }
        var damage: [Int: Double] = [:]
        for u in blue + red {
            u.cooldown = max(0, u.cooldown - dt); u.flash = max(0, u.flash - dt)
            if let id = u.targetID, units[id].alive, canHit(u, units[id]) {
                let enemy = units[id]; u.facing = u.p.x < enemy.p.x ? 1 : -1
                if u.cooldown <= 0 {
                    u.cooldown = u.kind.reload
                    let armor = enemy.kind == .infantry && u.kind == .archers ? 0.65 : 1.0
                    let bonus = u.kind == .cavalry && enemy.kind == .archers ? 1.35 : 1.0
                    damage[id, default: 0] += u.kind.power * armor * bonus
                    strikes.append(Strike(start: u.p, end: enemy.p, side: u.side, ranged: u.kind == .archers))
                }
            } else { advance(u, dt: dt) }
        }
        for (id, amount) in damage { units[id].hp = max(0, units[id].hp - amount); units[id].flash = 0.18 }
        separate(blue, dt: dt); separate(red, dt: dt)
        let b = blue.contains(where: \.alive), r = red.contains(where: \.alive)
        if !b || !r { phase = b && !r ? .victory : (r ? .defeat : .draw) }
    }

    private func separate(_ group: [Soldier], dt: Double) {
        var offsets = Array(repeating: Point(0, 0), count: group.count)
        for (n, a) in group.enumerated() where a.alive {
            for j in (n + 1)..<group.count where group[j].alive {
                let b = group[j]
                let dx = a.p.x - b.p.x, dy = a.p.y - b.p.y, distance = hypot(dx, dy)
                guard distance < 0.54 else { continue }
                let shove = (0.54 - distance) * 0.14
                let nx = distance > 0.001 ? dx / distance : (a.id.isMultiple(of: 2) ? 1.0 : -1.0)
                let ny = distance > 0.001 ? dy / distance : 0.0
                offsets[n].x += nx * shove; offsets[n].y += ny * shove
                offsets[j].x -= nx * shove; offsets[j].y -= ny * shove
            }
        }
        for (i, u) in group.enumerated() where u.alive {
            let offset = offsets[i], length = hypot(offset.x, offset.y)
            guard length > 0.0001 else { continue }
            // Several converging friends must never push harder than a soldier can walk.
            let limit = dt * u.kind.speed / map[u.p.cell].cost * (u.step < u.route.count ? 0.25 : 0.72)
            let scale = min(1, limit / length)
            let p = Point(u.p.x + offset.x * scale, u.p.y + offset.y * scale)
            if map.canStep(from: u.p, to: p) { u.p = p }
        }
    }
}
