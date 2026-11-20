import Foundation

@main struct AudioTests {
    static func main() async throws {
        setbuf(stdout, nil)
        let speech = LocalSpeech()
        let model = try CommandModel(data:Data(contentsOf:URL(fileURLWithPath:"Resources/orders.json")))
        try await speech.load(model: URL(fileURLWithPath:"build/vendor/ggml-base.en-q5_1.bin"), commands:model)
        let map = TerrainArt().map
        let cases: [(String,Action,Kind?,Kind?,Landmark?)] = [
            ("hold",.hold,.archers,nil,.northBridge), ("move",.move,.infantry,nil,.southBridge),
            ("attack",.attack,.cavalry,.archers,nil), ("retreat",.retreat,nil,nil,.camp)
        ]
        var failures = 0
        for (file, action, actor, target, place) in cases {
            let start = ProcessInfo.processInfo.systemUptime
            let audio = URL(fileURLWithPath:"Tests/Fixtures/\(file).wav")
            let transcript = try await speech.transcribe(audio)
            let latency = Int(1000 * (ProcessInfo.processInfo.systemUptime - start))
            do {
                let parsed = try model.interpret(transcript)
                let battle = Battle(map:map)
                let recipients = battle.living(.blue).filter { u in parsed.actors?.contains(u.kind) ?? true }
                let n = battle.issue(parsed.order,to:Set(recipients.map(\.id)))
                let okay = parsed.order.action == action && parsed.actors == actor.map { Set([$0]) } &&
                    parsed.order.focus == target && parsed.order.goal == place?.cell && n > 0 &&
                    recipients.allSatisfy { $0.order.action == action }
                print("\(okay ? "PASS" : "FAIL") \(file): “\(transcript)” → \(n) units (\(latency) ms)")
                if !okay { failures += 1 }
            } catch { print("FAIL \(file): “\(transcript)” · \(error.localizedDescription)"); failures += 1 }
        }
        if failures > 0 { throw OrderError("\(failures) recorded voice orders failed.") }
    }
}
