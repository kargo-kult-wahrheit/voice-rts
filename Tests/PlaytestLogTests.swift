import Foundation

@MainActor enum PlaytestLogTests {
    typealias Row = [String: Any]

    private static func require(_ value: Bool, _ message: String) throws {
        if !value { throw OrderError("Playtest log: " + message) }
    }

    private static func rows(_ url: URL) throws -> [Row] {
        try Data(contentsOf: url).split(separator: 0x0a).map {
            guard let row = try JSONSerialization.jsonObject(with: Data($0)) as? Row else {
                throw OrderError("Invalid JSON Lines event.")
            }
            return row
        }
    }

    static func run(_ samples: [VoiceTrace]) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let examples = URL(fileURLWithPath: "Resources/orders.json")
        let log = PlaytestLog(directory: directory)
        let game = GameStore(journal: log, examples: examples)

        game.select(.cavalry)
        game.submit("Send two archers to the north bridge.", source: "TYPED")
        let moved = game.battle.living(.blue).filter { $0.order.action == .move }.map(\.id)
        guard let id = game.dispatches.first?.id else { throw OrderError("Missing order in sidebar.") }
        game.flag(id, as: .interpretation)
        game.submit("Go there", source: "TYPED")
        for sample in samples {
            guard let transcript = sample.transcript else { throw OrderError("Missing fixture transcript.") }
            game.radio.onTranscript?(transcript.finalText, sample)
        }
        game.radio.onIssue?("recognition", "No speech heard.", VoiceTrace(recordingMS: 1200, decodingMS: 5))
        guard let enemy = game.battle.living(.red).first else { throw OrderError("Missing enemy.") }
        game.click(world: enemy.p, secondary: true, shift: false)

        // Read while the match is open. Even unflagged and rejected inputs must already be on disk.
        let events = try rows(log.fileURL)
        let orders = events.filter { $0["event"] as? String == "order" }.compactMap { $0["data"] as? Row }
        guard let first = orders.first, let assignments = first["assignments"] as? [Row] else {
            throw OrderError("Missing dispatched order.")
        }
        try require(first["id"] as? String == id.uuidString && first["text"] as? String == "Send two archers to the north bridge.", "original typed order and ID")
        try require(first["outcome"] as? String == "accepted" && !moved.isEmpty && assignments.compactMap { $0["unitID"] as? Int } == moved, "actual assigned soldiers")
        try require((first["selectionBefore"] as? [Int])?.count == 4 && (first["unitsBefore"] as? [Row])?.count == 36, "selection and live battlefield")
        try require(assignments.allSatisfy { ($0["order"] as? Row)?["goal"] is Row }, "individual formation destinations")
        let feedback = events.first { $0["event"] as? String == "review_flag" }?["data"] as? Row
        try require(feedback?["orderID"] as? String == id.uuidString && feedback?["reason"] as? String == "interpretation", "flag points to original order")
        try require(orders.contains { $0["outcome"] as? String == "rejected" && $0["stage"] as? String == "interpretation" && $0["detail"] is String }, "reason for rejected input")
        try require(orders.contains { $0["outcome"] as? String == "failed" && $0["stage"] as? String == "recognition" }, "failed voice attempt")
        try require(orders.contains { ($0["directOrder"] as? Row)?["foeID"] as? Int == enemy.id }, "map-issued target")
        let voiceOrders = orders.filter { $0["source"] as? String == "VOICE" && $0["outcome"] as? String == "accepted" }
        try require(voiceOrders.count == samples.count, "one record per speech fixture")
        for (row, sample) in zip(voiceOrders, samples) {
            let voice = row["voice"] as? Row
            let transcript = voice?["transcript"] as? Row
            try require(row["text"] as? String == sample.transcript?.finalText && transcript?["raw"] as? String == sample.transcript?.raw, "first and selected speech text")
            try require(transcript?["grammarCandidate"] as? String == sample.transcript?.grammarCandidate && transcript?["usedGrammar"] as? Bool == sample.transcript?.usedGrammar, "grammar evidence")
            try require(voice?["recordingMS"] as? Int == sample.recordingMS && voice?["decodingMS"] as? Int == sample.decodingMS, "speech timings")
        }

        game.toggleBattle()
        game.reset()
        for _ in 0..<21 { game.submit("Archers, hold", source: "TYPED") }
        game.endSession()
        let finished = try rows(log.fileURL)
        try require(game.dispatches.count == 20 && finished.filter { $0["match"] as? Int == 2 && $0["event"] as? String == "order" }.count == 21, "persistence past sidebar limit and match restart")
        try require(finished.last?["event"] as? String == "session_ended" && finished.compactMap { $0["sequence"] as? Int } == Array(1...finished.count), "ordered events through termination")
        let next = GameStore(journal: PlaytestLog(directory: directory), examples: examples)
        next.endSession()
        let original = try rows(log.fileURL)
        try require(next.journal.fileURL != log.fileURL && original.count == finished.count, "relaunch preserves prior session")
        let blocked = GameStore(journal: PlaytestLog(directory: log.fileURL), examples: examples)
        blocked.submit("Archers, hold", source: "TYPED")
        try require(blocked.logError != nil && blocked.dispatches.first?.accepted == true, "write failure visible, order dispatch still works")
        print("PASS playtest logs: recorded audio, typed and map orders, errors, flags, match restarts, relaunch, write failure")
    }
}
