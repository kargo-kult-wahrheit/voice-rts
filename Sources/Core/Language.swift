import Foundation

struct Interpretation: Encodable {
    let order: Order
    let actors: Set<Kind>?
    let entireArmy: Bool
    let place: String?
    let confidence: Double
}

struct OrderError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Multinomial naive Bayes trained locally on labeled utterances. Only the four intent
/// scores are predicted. Unit names and locations are grounded against the actual map.
struct CommandModel {
    private let labels = Action.allCases
    private let weights: [String: [Double]]
    private let actionWords: Set<String>
    private static let stop: Set<String> = ["a","an","the","at","to","for","in","of","on","you","your","their",
        "please","our","my","now","them","this","by","up","out","over","there","here","everyone","some","it"]
    private static let unitWords: [Kind: Set<String>] = [
        .archers: ["archer","archers","archery","bow","bows","bowmen","bowman","ranged"],
        .infantry: ["infantry","footmen","footman","swordsmen","swordsman","swords","shields","shield","tanks","tank"],
        .cavalry: ["cavalry","calvary","horse","horses","horsemen","horseman","riders","rider","knights","knight"]
    ]
    private static let hostile: Set<String> = ["enemy","enemies","hostile","hostiles","opposing","their","red"]
    private static let targets: Set<String> = ["attack","engage","shoot","charge","focus","target","hit","fight",
        "flank","outflank","strike","eliminate","storm","fire","assault","chase","pursue","overrun"]
    private static let aliases: [(Landmark,[String])] = [
        (.northBridge,["north bridge","northern bridge","north crossing","upper bridge","top bridge","upper crossing"]),
        (.southBridge,["south bridge","southern bridge","south crossing","lower bridge","bottom bridge","lower crossing"]),
        (.enemyCamp,["enemy camp","their camp","red camp","east camp","east bank","enemy base","their base","red base"]),
        (.camp,["west camp","blue camp","our camp","home camp","our base","blue base","home base","west base","base camp"]),
        (.grove,["pine grove","grove","pines","forest","woods","woodland"]),
        (.ridge,["slate ridge","ridge","rocks","rocky hill","mountain"]),
        (.center,["west bank","center","centre","middle"]),
        (.north,["north","northern field","upper field","top"]),
        (.south,["south","southern field","lower field","bottom"]),
        (.enemyCamp,["east","right"]),(.camp,["west","left","home","camp","base"])
    ]

    init(data: Data) throws {
        let training = try JSONDecoder().decode([String:[String]].self, from: data)
        let phrases = training.values.flatMap { $0 }.map(Self.words)
        actionWords = Set(phrases.compactMap(\.first))
        var counts = Array(repeating: [String:Int](), count: labels.count)
        var totals = Array(repeating: 0, count: labels.count), vocabulary: Set<String> = []
        for (i, label) in labels.enumerated() {
            guard let samples = training[label.rawValue], !samples.isEmpty else { throw OrderError("Missing examples for \(label.rawValue).") }
            for line in samples {
                for f in Self.features(Self.words(line)) {
                    counts[i][f,default: 0] += 1; totals[i] += 1; vocabulary.insert(f)
                }
            }
        }
        let smoothing = 0.22
        var matrix: [String:[Double]] = [:]
        for f in vocabulary {
            matrix[f] = labels.indices.map { i in
                log((Double(counts[i][f,default: 0]) + smoothing) / (Double(totals[i]) + smoothing * Double(vocabulary.count)))
            }
        }
        weights = matrix
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "'", with: "")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
    private static func features(_ words: [String]) -> [String] {
        let single = words.filter { !stop.contains($0) }
        let pairs = zip(words, words.dropFirst()).map { $0 + "_" + $1 }
        return single + pairs
    }
    private func intent(_ words: [String]) throws -> (Action, Double) {
        var scores = Array(repeating: 0.0, count: labels.count)
        var seen = false
        for f in Self.features(words) {
            if let row = weights[f] {
                seen = true
                for i in scores.indices { scores[i] += row[i] }
            }
        }
        let best = scores.indices.max { scores[$0] < scores[$1] }!
        let confidence = 1 / scores.reduce(0.0) { $0 + exp($1 - scores[best]) }
        guard seen, confidence >= 0.57 else {
            throw OrderError("I didn’t catch an order. Try “Archers, hold the north bridge.”")
        }
        return (labels[best], confidence)
    }

    func actionCount(in words: [String]) -> Int { Set(words).intersection(actionWords).count }

    func interpret(_ text: String, marker: Cell? = nil) throws -> Interpretation {
        let w = Self.words(text)
        guard !w.isEmpty else { throw OrderError("Give one order to your troops.") }
        let words = Set(w)
        if !words.isDisjoint(with: ["not","dont","never","cant","cannot","unless","if","except","without","neither","onlyif"]) ||
           ["who","what","why","when","where","how","should","is","are"].contains(w[0]) || text.hasSuffix("?") {
            throw OrderError("Give a direct order, for example “Infantry, hold position.”")
        }
        if words.contains("then") || words.contains("and") || text.contains(";") {
            throw OrderError("Give one order at a time.")
        }
        guard !words.isDisjoint(with: actionWords) else { throw OrderError("Name an action: move, attack, hold, or fall back.") }
        let (action, score) = try intent(w)
        if w.joined(separator: " ").contains("hold fire") || w.joined(separator: " ").contains("cease fire") {
            throw OrderError("Hold position lets units defend themselves. Cease-fire is unavailable.")
        }
        let hostileAt = w.firstIndex(where: Self.hostile.contains)
        let attackAt = w.firstIndex(where: Self.targets.contains)
        var actors: Set<Kind> = [], foes: Set<Kind> = []
        for (i, word) in w.enumerated() {
            guard let kind = Kind.allCases.first(where: { Self.unitWords[$0]!.contains(word) }) else { continue }
            let markedEnemy = hostileAt.map { $0 < i } ?? false
            let afterVerb = action == .attack && (attackAt.map { $0 < i } ?? false)
            let followsWith = w[..<i].lastIndex(of: "with").map { $0 > (attackAt ?? -1) } ?? false
            if (markedEnemy || afterVerb) && !followsWith { foes.insert(kind) } else { actors.insert(kind) }
        }
        guard foes.count <= 1 else { throw OrderError("Name one enemy unit type to focus.") }
        if let comma = text.firstIndex(of: ","), actors.isEmpty {
            let opening = Set(Self.words(String(text[..<comma])))
            let context: Set<String> = ["please","okay","all","army","units","everyone","everybody","selected","troops"]
            if opening.isDisjoint(with: actionWords) && opening.isDisjoint(with: context) {
                throw OrderError("Which troops? Say archers, infantry, light cavalry, or all units.")
            }
        }
        let padded = " " + w.joined(separator: " ") + " "
        var place = Self.aliases.first { _, names in names.contains { padded.contains(" " + $0 + " ") } }?.0
        if words.contains("bridge") || words.contains("crossing") {
            guard place == .northBridge || place == .southBridge else { throw OrderError("Which crossing? Say “north bridge” or “south bridge.”") }
        }
        if words.contains("north") && words.contains("south") || words.contains("via") && place != nil {
            throw OrderError("Name one destination per order.")
        }
        if action == .retreat && place == nil { place = .camp }
        let wantsPin = !words.isDisjoint(with: ["marker","mark","pin","there","here"]) && place == nil &&
            (action == .move || words.contains("marker") || words.contains("pin") || words.contains("mark"))
        if wantsPin && marker == nil { throw OrderError("Click the ground to mark a destination first.") }
        let goal = wantsPin ? marker : place?.cell
        if action == .move && goal == nil {
            throw OrderError("Name a destination, such as “Pine Grove” or “North Bridge.”")
        }
        if action != .attack && !foes.isEmpty { throw OrderError("Use an attack order to target enemy units.") }
        return Interpretation(order: Order(action, goal: goal, focus: foes.first),
                              actors: actors.isEmpty ? nil : actors, entireArmy: !words.isDisjoint(with: ["all","everyone","everybody","army"]),
                              place: wantsPin ? "Map pin" : place?.rawValue, confidence: score)
    }
}
