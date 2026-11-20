import Foundation

struct SpeechTranscript: Encodable {
    let raw: String
    var grammarCandidate: String?
    var usedGrammar = false
    var grammarError: String?

    var finalText: String {
        if usedGrammar, let grammarCandidate { return grammarCandidate }
        return raw
    }
}

struct VoiceTrace: Encodable {
    var recordingMS: Int?
    var decodingMS: Int?
    var transcript: SpeechTranscript?
}

struct LoggedCommand: Encodable {
    struct Unit: Encodable {
        let id: Int
        let kind: Kind
        let side: String
        let cell: Cell

        init(_ soldier: Soldier) {
            id = soldier.id; kind = soldier.kind
            side = soldier.side == .blue ? "blue" : "red"
            cell = soldier.p.cell
        }
    }

    struct Assignment: Encodable {
        let unitID: Int
        let kind: Kind
        let order: Order

        init(_ soldier: Soldier) {
            unitID = soldier.id; kind = soldier.kind; order = soldier.order
        }
    }

    let id = UUID()
    let source: String
    let text: String?
    let voice: VoiceTrace?
    let selectionBefore: [Int]
    let marker: Cell?
    let unitsBefore: [Unit]
    var interpretation: Interpretation?
    var directOrder: Order?
    var clickedCell: Cell?
    var assignments: [Assignment] = []
    var outcome = "rejected"
    var stage = "interpretation"
    var detail = ""
    var handlingMS: Double?
}

enum ReviewFlag: String, Encodable, CaseIterable {
    case transcription, interpretation, unitBehavior

    var label: String {
        switch self {
        case .transcription: return "Heard me wrong"
        case .interpretation: return "Misunderstood my order"
        case .unitBehavior: return "Units acted differently"
        }
    }
}

/// All callers append on the main actor. Closing each line makes it readable during play and after quitting.
final class PlaytestLog {
    private struct Line<Details: Encodable>: Encodable {
        let schema = 1
        let sessionID: UUID
        let sequence: Int
        let timestamp: String
        let version: String
        let match: Int
        let matchSeconds: Double
        let phase: Phase
        let event: String
        let data: Details
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Bannerfall", isDirectory: true)
    }

    let fileURL: URL
    private let sessionID = UUID()
    private let dates = ISO8601DateFormatter()
    private let encoder = JSONEncoder()
    private let version: String
    private var sequence = 0

    init(directory: URL = PlaytestLog.defaultDirectory) {
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let stamp = dates.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        fileURL = directory.appendingPathComponent("session-\(stamp)-\(sessionID.uuidString).jsonl")
    }

    @MainActor
    func append<T: Encodable>(_ event: String, match: Int, battle: Battle, data: T) throws {
        let line = Line(sessionID: sessionID, sequence: sequence + 1, timestamp: dates.string(from: Date()),
                        version: version, match: match, matchSeconds: battle.elapsed, phase: battle.phase,
                        event: event, data: data)
        var bytes = try encoder.encode(line)
        bytes.append(0x0a)
        let files = FileManager.default
        if !files.fileExists(atPath: fileURL.path) {
            try files.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                      attributes: [.posixPermissions: 0o700])
            guard files.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let file = try FileHandle(forWritingTo: fileURL)
        defer { try? file.close() }
        let start = try file.seekToEnd()
        do { try file.write(contentsOf: bytes) }
        catch {
            try? file.truncate(atOffset: start)
            throw error
        }
        sequence += 1
    }
}
