import Foundation

struct Cell: Hashable {
    let x: Int
    let y: Int
    init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    var center: Point { Point(Double(x) + 0.5, Double(y) + 0.5) }
}

struct Point: Equatable {
    var x: Double
    var y: Double
    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    var cell: Cell { Cell(Int(floor(x)), Int(floor(y))) }
    func distance(to other: Point) -> Double { hypot(x - other.x, y - other.y) }
}

enum Ground: Int, CaseIterable {
    case meadow, forest, river, rock, bridge

    var color: (Int, Int, Int) {
        switch self {
        case .meadow: return (187, 191, 139)
        case .forest: return (112, 140, 100)
        case .river: return (83, 146, 151)
        case .rock: return (151, 145, 136)
        case .bridge: return (180, 134, 77)
        }
    }
    var walkable: Bool { self != .river && self != .rock }
    var cost: Double { self == .forest ? 1.85 : 1 }
}

enum Landmark: String, CaseIterable {
    case northBridge = "North Bridge", southBridge = "South Bridge"
    case grove = "Pine Grove", ridge = "Slate Ridge"
    case camp = "West Camp", enemyCamp = "East Camp", center = "West Bank"
    case north = "North Field", south = "South Field"

    var cell: Cell {
        switch self {
        case .northBridge: return Cell(21, 5)
        case .southBridge: return Cell(18, 18)
        case .grove: return Cell(8, 4)
        case .ridge: return Cell(29, 13)
        case .camp: return Cell(4, 12)
        case .enemyCamp: return Cell(35, 12)
        case .center: return Cell(16, 12)
        case .north: return Cell(14, 3)
        case .south: return Cell(13, 21)
        }
    }
}

struct FieldMap {
    static let columns = 40, rows = 24
    let tiles: [Ground]

    init(tiles: [Ground]) {
        precondition(tiles.count == Self.columns * Self.rows)
        self.tiles = tiles
    }

    func contains(_ c: Cell) -> Bool {
        (0..<Self.columns).contains(c.x) && (0..<Self.rows).contains(c.y)
    }
    func index(_ c: Cell) -> Int { c.y * Self.columns + c.x }
    func cell(_ i: Int) -> Cell { Cell(i % Self.columns, i / Self.columns) }
    subscript(_ c: Cell) -> Ground { contains(c) ? tiles[index(c)] : .rock }

    func neighbors(of start: Cell) -> [Cell] {
        Self.steps.compactMap { dx, dy in
            let next = Cell(start.x + dx, start.y + dy)
            guard self[next].walkable else { return nil }
            if dx != 0 && dy != 0 &&
                (!self[Cell(start.x + dx, start.y)].walkable || !self[Cell(start.x, start.y + dy)].walkable) {
                return nil
            }
            return next
        }
    }
    private static let steps = [(1,0),(0,1),(-1,0),(0,-1),(1,1),(-1,1),(-1,-1),(1,-1)]

    func closestOpen(to target: Cell, excluding used: Set<Cell> = []) -> Cell? {
        if self[target].walkable && !used.contains(target) { return target }
        return tiles.indices.lazy.map(cell).filter { self[$0].walkable && !used.contains($0) }
            .min { a, b in
                func square(_ c: Cell) -> Int {
                    let dx = c.x - target.x, dy = c.y - target.y
                    return dx * dx + dy * dy
                }
                return square(a) < square(b)
            }
    }

    // The route excludes the start and includes the goal. An unreachable goal is distinct from arrival.
    func route(from start: Cell, to goal: Cell) -> [Cell]? {
        guard self[start].walkable, self[goal].walkable else { return nil }
        if start == goal { return [] }
        let size = tiles.count, first = index(start), last = index(goal)
        var cost = Array(repeating: Double.infinity, count: size)
        var parent = Array(repeating: -1, count: size)
        var open = MinHeap()
        func estimate(_ c: Cell) -> Double {
            let dx = abs(c.x - goal.x), dy = abs(c.y - goal.y)
            return Double(max(dx, dy)) + 0.41421356237 * Double(min(dx, dy))
        }
        cost[first] = 0
        open.push((first, estimate(start)))
        while let (i, priority) = open.pop() {
            if i == last {
                var result: [Cell] = [], current = i
                while current != first { result.append(cell(current)); current = parent[current] }
                return result.reversed()
            }
            let current = cell(i)
            if priority > cost[i] + estimate(current) + 0.00001 { continue }
            for next in neighbors(of: current) {
                let n = index(next)
                let length = (current.x == next.x || current.y == next.y) ? 1.0 : 1.41421356237
                let candidate = cost[i] + length * (tiles[i].cost + tiles[n].cost) / 2
                if candidate + 0.00001 < cost[n] {
                    cost[n] = candidate
                    parent[n] = i
                    open.push((n, candidate + estimate(next)))
                }
            }
        }
        return nil
    }

    func canStep(from a: Point, to b: Point) -> Bool {
        let start = a.cell, end = b.cell
        guard self[end].walkable else { return false }
        return start.x == end.x || start.y == end.y ||
            (self[Cell(start.x, end.y)].walkable && self[Cell(end.x, start.y)].walkable)
    }

    func clearShot(from a: Point, to b: Point) -> Bool {
        let steps = max(1, Int(ceil(a.distance(to: b) * 3)))
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            if self[Point(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y)).cell] == .rock { return false }
        }
        return true
    }
}

private struct MinHeap {
    typealias Entry = (Int, Double)
    var items: [Entry] = []
    mutating func push(_ entry: Entry) {
        items.append(entry)
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard items[child].1 < items[parent].1 else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }
    mutating func pop() -> Entry? {
        guard let head = items.first else { return nil }
        if items.count == 1 { return items.removeLast() }
        items[0] = items.removeLast()
        var parent = 0
        while 2 * parent + 1 < items.count {
            var child = 2 * parent + 1
            if child + 1 < items.count && items[child + 1].1 < items[child].1 { child += 1 }
            guard items[child].1 < items[parent].1 else { break }
            items.swapAt(child, parent)
            parent = child
        }
        return head
    }
}
