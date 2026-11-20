import Foundation

@main struct CoreTests {
    static func main() throws {
        let model = try CommandModel(data:Data(contentsOf:URL(fileURLWithPath:"Resources/orders.json")))
        let cases: [(String,Action,Kind?,Kind?,Landmark?)] = [
            ("Archers, hold the north bridge",.hold,.archers,nil,.northBridge),
            ("Send the light cavalry over to the southern bridge",.move,.cavalry,nil,.southBridge),
            ("Infantry, stand your ground",.hold,.infantry,nil,nil),
            ("Bowmen, open fire on enemy cavalry",.attack,.archers,.cavalry,nil),
            ("Target their archers",.attack,nil,.archers,nil),
            ("Cavalry attack infantry",.attack,.cavalry,.infantry,nil),
            ("Attack their archers with the cavalry",.attack,.cavalry,.archers,nil),
            ("Everybody pull back to our camp",.retreat,nil,nil,.camp),
            ("Have the riders make their way to Pine Grove",.move,.cavalry,nil,.grove),
            ("Infantry guard Slate Ridge",.hold,.infantry,nil,.ridge),
            ("Bring the horsemen home",.retreat,.cavalry,nil,.camp),
            ("Archers, wait here",.hold,.archers,nil,nil)
        ]
        for (line,action,actor,foe,place) in cases {
            let result: Interpretation
            do { result = try model.interpret(line) }
            catch { throw OrderError("Language: \(line) — \(error.localizedDescription)") }
            try expect(result.order.action == action && result.actors == actor.map { Set([$0]) } &&
                       result.order.focus == foe && result.order.goal == place?.cell, "Language: \(line)")
        }
        let pin = Cell(9,3)
        let marked = try model.interpret("Go there",marker:pin)
        try expect(marked.order.goal == pin, "Map pin grounded")
        for rejected in ["archers", "where are my archers?", "do not attack", "move to the bridge",
                         "go to the moon", "hold then charge", "go there", "good morning", "hold fire",
                         "archers north bridge", "strangers, attack the enemy archers"] {
            var rejectedCorrectly = false
            do { _ = try model.interpret(rejected) } catch { rejectedCorrectly = true }
            try expect(rejectedCorrectly,"Reject: \(rejected)")
        }
        let map = TerrainArt().map
        for type in Ground.allCases { try expect(map.tiles.contains(type), "Terrain class \(type) detected") }
        for cell in [Landmark.northBridge.cell,Landmark.southBridge.cell] { try expect(map[cell] == .bridge,"Recognized bridge \(cell)") }
        try expect(map[Cell(8,4)] == .forest && map[Cell(29,15)] == .rock && map[Cell(19,12)] == .river, "Known terrain landmarks")
        for bridge in [Landmark.northBridge, .southBridge] {
            let west = Cell(3,bridge.cell.y), east = Cell(36,bridge.cell.y)
            guard let route = map.route(from:west,to:east) else { throw OrderError("No cross-river route") }
            try expect(route.contains { map[$0] == .bridge && abs($0.y - bridge.cell.y) <= 1 }, "Uses \(bridge.rawValue)")
            try expect(zip([west]+route,route).allSatisfy { map.neighbors(of:$0.0).contains($0.1) }, "Every step legal")
        }
        var blocked = Array(repeating:Ground.rock,count:FieldMap.columns*FieldMap.rows)
        blocked[0] = .meadow; blocked[FieldMap.columns+1] = .meadow
        try expect(FieldMap(tiles:blocked).route(from:Cell(0,0),to:Cell(1,1)) == nil,"No diagonal corner cutting")
        let open = FieldMap(tiles:Array(repeating:.meadow,count:blocked.count))
        var costly = open.tiles
        for x in 3...10 { costly[open.index(Cell(x,4))] = .forest }
        let detour = FieldMap(tiles:costly).route(from:Cell(2,4),to:Cell(11,4))
        try expect(detour?.contains { $0.y != 4 } == true,"Planner considers forest speed")

        let battle = Battle(map:map)
        try expect(battle.living(.blue).count == 18 && battle.living(.red).count == 18,"Balanced deployment")
        let riders = battle.living(.blue).filter { $0.kind == .cavalry }
        let order = try model.interpret("Cavalry move to East Camp")
        let n = battle.issue(order.order,to:Set(riders.map(\.id)))
        try expect(n == 4 && Set(riders.compactMap { $0.order.goal }).count == 4,"Distinct formation slots")
        try expect(battle.living(.blue).filter { $0.kind != .cavalry }.allSatisfy { $0.order.action == .hold },"Recipient isolation")
        let before = riders.map(\.p)
        battle.tick(1/30); try expect(riders.map(\.p) == before,"Deployment freezes time")
        battle.phase = .running
        var crossed = false, injured = false
        for _ in 0..<(30*220) {
            battle.tick(1.0/30)
            if battle.units.contains(where: { !map[$0.p.cell].walkable }) { throw OrderError("Unit entered blocked terrain") }
            if riders.contains(where: { $0.p.x > 23 && $0.alive }) { crossed = true }
            if battle.units.contains(where: { $0.hp < $0.kind.hp }) { injured = true }
            if battle.phase.finished { break }
        }
        try expect(crossed && injured,"Units crossed the river and dealt damage")
        try expect(battle.phase.finished,"Match reaches a result in 220 simulation seconds")
        print("Match: \(battle.phase) in \(Int(battle.elapsed))s, west \(battle.living(.blue).count), east \(battle.living(.red).count)")
        battle.reset()
        try expect(battle.phase == .deployment && battle.elapsed == 0 && battle.units.allSatisfy { $0.hp == $0.kind.hp },"Clean rematch")
        for kind in Kind.allCases {
            let line = kind == .archers ? Cell(5,10) : (kind == .cavalry ? Cell(8,10) : Cell(7,11))
            let ids = Set(battle.living(.blue).filter { $0.kind == kind }.map(\.id))
            battle.issue(Order(.hold,goal:line),to:ids)
        }
        battle.phase = .running
        for tick in 0..<(30*150) {
            if tick == 30*17 {
                battle.issue(Order(.attack,focus:.archers),to:Set(battle.living(.blue).map(\.id)))
            }
            battle.tick(1.0/30)
            if battle.phase.finished { break }
        }
        try expect(battle.phase == .victory && battle.living(.red).isEmpty,"Player can win by concentrating forces and focusing archers")
        print("PASS language, terrain recognition, routing, formations, combat, rematch")
    }
    static func expect(_ condition: Bool, _ reason: String) throws {
        if !condition { throw OrderError(reason) }
    }
}
