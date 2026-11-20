import AVFoundation
import Foundation
@MainActor final class VoiceRadio: ObservableObject {
    enum State { case idle, preparing, ready, recording, processing, unavailable }
    @Published private(set) var state: State = .idle
    @Published private(set) var note = "English · on-device"
    var onTranscript: ((String, VoiceTrace) -> Void)?
    var onIssue: ((_ stage: String, _ detail: String, _ trace: VoiceTrace) -> Void)?
    var commandModel: CommandModel?
    private let speech = LocalSpeech()
    private var recorder: AVAudioRecorder?, file: URL?
    private var decoding: Task<Void, Never>?, watchdog: Task<Void, Never>?
    private var generation = 0
    private var recordedMS: Int?
    private var decodeStarted: TimeInterval?

    func press() {
        switch state {
        case .idle, .unavailable:
            state = .preparing; note = "Preparing the local voice model…"
            Task { await prepare() }
        case .ready: record()
        default: break
        }
    }

    private func prepare() async {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            fail("Allow Bannerfall in System Settings → Privacy & Security → Microphone, then retry.", stage: "preparation"); return
        }
        guard let commandModel, let model = Bundle.main.url(forResource: "ggml-base.en-q5_1", withExtension: "bin") else {
            fail("The bundled English model is missing. Rebuild the app with make app.", stage: "preparation"); return
        }
        do { try await speech.load(model: model, commands: commandModel); ready() }
        catch { fail(error.localizedDescription, stage: "preparation") }
    }

    private func ready() { state = .ready; note = "Ready · hold Space to speak" }
    private func fail(_ message: String, stage: String) {
        state = .unavailable; note = message
        onIssue?(stage, message, trace())
    }

    private func trace(_ transcript: SpeechTranscript? = nil) -> VoiceTrace {
        let recording = recorder.map { Int(($0.currentTime * 1000).rounded()) } ?? recordedMS
        let decoding = decodeStarted.map { Int(((ProcessInfo.processInfo.systemUptime - $0) * 1000).rounded()) }
        return VoiceTrace(recordingMS: recording, decodingMS: decoding, transcript: transcript)
    }

    private func record() {
        generation += 1
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bannerfall-\(UUID().uuidString).wav")
        file = url
        do {
            let settings: [String:Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
            let capture = try AVAudioRecorder(url: url, settings: settings)
            guard capture.prepareToRecord(), capture.record() else { throw OrderError("Check your Mac’s selected input device, then retry.") }
            recorder = capture; state = .recording; note = "Listening… release to issue the order"
            watchdog = Task {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                if !Task.isCancelled { release() }
            }
        } catch { cleanup(); fail(error.localizedDescription, stage: "recording") }
    }

    func release() {
        guard state == .recording, let capture = recorder, let url = file else { return }
        let duration = capture.currentTime, token = generation
        recordedMS = Int((duration * 1000).rounded())
        capture.stop(); recorder = nil
        watchdog?.cancel()
        if duration < 0.18 {
            let info = trace()
            cleanup(); ready(); note = "Hold Space while speaking, then release."
            onIssue?("recording", note, info); return
        }
        decodeStarted = ProcessInfo.processInfo.systemUptime
        state = .processing; note = "Interpreting on this Mac…"
        watchdog = Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if !Task.isCancelled { complete(token, result: .failure(OrderError("Speech timed out. Hold Space and try again."))) }
        }
        decoding = Task {
            do { complete(token, result: .success(try await speech.transcribe(url))) }
            catch { complete(token, result: .failure(error)) }
        }
    }

    private func complete(_ token: Int, result: Result<SpeechTranscript, Error>) {
        guard generation == token, state == .processing else { return }
        let info = trace(try? result.get())
        generation += 1; cleanup(); ready()
        switch result {
        case .success(let transcript):
            if let error = transcript.grammarError {
                note = error; onIssue?("recognition", note, info); return
            }
            guard !transcript.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                note = "No speech heard. Check your input and try again."
                onIssue?("recognition", note, info); return
            }
            onTranscript?(transcript.finalText, info)
        case .failure(let error):
            note = error.localizedDescription; onIssue?("recognition", note, info)
        }
    }

    func cancel(_ reason: String = "Voice input cancelled.") {
        guard state == .recording || state == .processing else { return }
        let stage = state == .recording ? "recording" : "recognition"
        let info = trace()
        generation += 1; recorder?.stop(); recorder = nil; cleanup(); ready()
        onIssue?("cancelled_" + stage, reason, info)
    }
    private func cleanup() {
        watchdog?.cancel(); watchdog = nil
        decoding?.cancel(); decoding = nil
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil; recordedMS = nil; decodeStarted = nil
    }
}
