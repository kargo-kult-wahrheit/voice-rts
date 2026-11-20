import AVFoundation
import Foundation

/// Serial ownership of whisper.cpp's non-thread-safe context, off the UI thread.
actor LocalSpeech {
    private var context: OpaquePointer?
    private var commands: CommandModel?
    deinit {
        if let context { whisper_free(context) }
    }

    func load(model: URL, commands: CommandModel) throws {
        guard context == nil else { return }
        var options = whisper_context_default_params()
        options.use_gpu = false
        context = model.path.withCString { whisper_init_from_file_with_params($0, options) }
        guard context != nil else { throw OrderError("The bundled Whisper model could not be opened.") }
        self.commands = commands
    }

    func transcribe(_ url: URL) throws -> String {
        guard let context else { throw OrderError("The voice model is still loading.") }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1,
              file.length > 0, file.length <= 16000 * 14,
              let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw OrderError("Voice input needs up to 14 seconds of mono 16 kHz audio.")
        }
        try file.read(into: pcm)
        guard let channel = pcm.floatChannelData?[0] else { throw OrderError("The recording was empty.") }
        var samples = Array(UnsafeBufferPointer(start: channel, count: Int(pcm.frameLength)))
        let usable = samples.lazy.filter { abs($0) > 0.004 }.prefix(160).count
        guard usable == 160 else { throw OrderError("No speech heard. Check your microphone and try again.") }
        samples.append(contentsOf: repeatElement(0, count: max(3200, 17600 - samples.count)))
        let original = try decode(samples, context: context, constrained: false)
        guard let commands, !original.isEmpty else { return original }
        let words = CommandModel.words(original)
        let wordSet = Set(words)
        // A pin is supplied here only for syntax validation. The live map resolves it on dispatch.
        if (try? commands.interpret(original, marker: Cell(0,0))) != nil { return original }
        let veto: Set<String> = ["no","not","dont","never","then","unless","if","except","without","cannot","cant"]
        guard wordSet.isDisjoint(with: veto), words.count >= 2,
              !wordSet.isDisjoint(with: ["archers","bridge","infantry","cavalry","hold","move","attack","camp","back","retreat","fire","go","march","guard","charge"]) else { return original }
        if words.contains("and") && commands.actionCount(in: words) > 1 { return original }
        if words.contains("bridge") && wordSet.isDisjoint(with: ["north","south","northern","southern","upper","lower","top","bottom"]) { return original }
        if original.hasSuffix("?") || ["who","what","where","why","when","how","should","can"].contains(words[0]) { return original }
        let candidate = try decode(samples, context: context, constrained: true)
        guard (try? commands.interpret(candidate, marker: Cell(0,0))) != nil,
              Self.similarity(original, candidate) >= 0.65 else { return original }
        return candidate
    }

    // Compare normalized character sequences so a few misheard syllables can be recovered.
    private static func similarity(_ a: String, _ b: String) -> Double {
        let left = Array(CommandModel.words(a).joined()), right = Array(CommandModel.words(b).joined())
        guard !left.isEmpty && !right.isEmpty else { return 0 }
        var previous = Array(0...right.count)
        for (i, x) in left.enumerated() {
            var row = [i+1]
            for (j, y) in right.enumerated() {
                row.append(min(previous[j+1]+1, row[j]+1, previous[j] + (x == y ? 0 : 1)))
            }
            previous = row
        }
        return 1 - Double(previous[right.count]) / Double(max(left.count,right.count))
    }

    private func decode(_ samples: [Float], context: OpaquePointer, constrained: Bool) throws -> String {
        var options = whisper_full_default_params(constrained ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY)
        options.beam_search.beam_size = 4
        if constrained { radio_grammar_apply(&options) }
        options.n_threads = 4
        options.no_context = true; options.no_timestamps = true; options.single_segment = true
        options.print_progress = false; options.print_realtime = false; options.print_timestamps = false
        options.suppress_nst = true; options.temperature_inc = 0; options.max_tokens = 48
        options.audio_ctx = min(1500, max(256, Int32(samples.count / 320 + 80)))
        let vocabulary = "Orders for the infantry, archers and light cavalry: move, attack, hold position, or fall back. Locations: North Bridge, South Bridge, Pine Grove, Slate Ridge, West Camp, East Camp."
        let code = "en".withCString { language in
            vocabulary.withCString { prompt in
                options.language = language; options.initial_prompt = prompt
                return samples.withUnsafeBufferPointer { whisper_full(context, options, $0.baseAddress, Int32($0.count)) }
            }
        }
        guard code == 0 else { throw OrderError("The local speech decoder could not read that order.") }
        var words: [String] = []
        for i in 0..<whisper_full_n_segments(context) {
            if whisper_full_get_segment_no_speech_prob(context, i) < 0.78, let value = whisper_full_get_segment_text(context, i) {
                words.append(String(cString: value))
            }
        }
        return words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
