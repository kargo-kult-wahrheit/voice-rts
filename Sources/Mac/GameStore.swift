import AppKit
import SwiftUI

struct DispatchEntry: Identifiable {
    let id = UUID()
    let source: String, words: String, detail: String, accepted: Bool
}

@MainActor final class FrameClock: ObservableObject { @Published var frame = 0 }

@MainActor final class GameStore: ObservableObject {
    let art: TerrainArt, battle: Battle, radio = VoiceRadio(), clock = FrameClock()
    private let model: CommandModel?
    @Published private(set) var selected: Set<Int> = []
    @Published private(set) var marker: Cell?
    @Published private(set) var dispatches: [DispatchEntry] = []
    @Published var recon = false
    @Published var showGuide = false
    @Published private(set) var time = 0
    @Published private(set) var blueCount = 18
    @Published private(set) var redCount = 18
    @Published private(set) var phase: Phase = .deployment
    @Published var focusCommand = 0
    private var timer: Timer?, keys: Any?
    private var lastTime = ProcessInfo.processInfo.systemUptime
    private var remainder = 0.0, spaceHeld = false
    private var deactivation: NSObjectProtocol?

    init() {
        let artwork = TerrainArt()
        art = artwork; battle = Battle(map: artwork.map)
        if let file = Bundle.main.url(forResource: "orders", withExtension: "json") {
            model = try? CommandModel(data: Data(contentsOf: file))
        } else { model = nil }
        selected = Set(battle.living(.blue).map(\.id))
        radio.commandModel = model
        radio.onTranscript = { [weak self] in self?.submit($0, source: "VOICE") }
    }

    func startUI() {
        guard timer == nil else { return }
        lastTime = ProcessInfo.processInfo.systemUptime
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        timer = t; RunLoop.main.add(t, forMode: .common)
        keys = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            let handled = MainActor.assumeIsolated { self?.keyboard(e) == nil }
            return handled ? nil : e
        }
        deactivation = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceHeld = false; self?.radio.cancel() }
        }
    }

    func stopUI() {
        timer?.invalidate(); timer = nil
        if let keys { NSEvent.removeMonitor(keys); self.keys = nil }
        if let deactivation { NotificationCenter.default.removeObserver(deactivation); self.deactivation = nil }
        radio.cancel()
    }

    // Keep navigation and combat on the same fixed timestep used by the headless simulation.
    private func update() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.16, max(0, now - lastTime)); lastTime = now
        guard battle.phase == .running else { return }
        remainder += dt
        while remainder >= 1.0 / 30 {
            battle.tick(1.0 / 30); remainder -= 1.0 / 30
        }
        let blue = battle.living(.blue), red = battle.living(.red)
        if time != Int(battle.elapsed) { time = Int(battle.elapsed) }
        if blueCount != blue.count { blueCount = blue.count; selected.formIntersection(blue.map(\.id)) }
        if redCount != red.count { redCount = red.count }
        if phase != battle.phase { phase = battle.phase; radio.cancel() }
        clock.frame &+= 1
    }

    private func keyboard(_ e: NSEvent) -> NSEvent? {
        if e.type == .keyUp {
            if e.keyCode == 49 && spaceHeld { spaceHeld = false; radio.release(); return nil }
            return e
        }
        if e.modifierFlags.intersection([.command,.control,.option]).isEmpty == false { return e }
        let typing = (NSApp.keyWindow?.firstResponder as? NSTextView)?.isFieldEditor == true
        if typing {
            if e.keyCode == 53 { NSApp.keyWindow?.makeFirstResponder(nil); return nil }
            return e
        }
        if e.keyCode == 49 {
            if !spaceHeld && !phase.finished && !showGuide { spaceHeld = true; radio.press() }
            return nil
        }
        guard !e.isARepeat else { return e }
        if e.keyCode == 53 { showGuide = false; return nil }
        if showGuide { return e }
        switch e.charactersIgnoringModifiers?.lowercased() {
        case "0": select(nil)
        case "1": select(.archers)
        case "2": select(.infantry)
        case "3": select(.cavalry)
        case "p": toggleBattle()
        case "v": recon.toggle()
        case "\r": focusCommand &+= 1
        default: return e
        }
        return nil
    }

    func toggleBattle() {
        if phase.finished { reset(); return }
        battle.phase = phase == .running ? .paused : .running
        phase = battle.phase; lastTime = ProcessInfo.processInfo.systemUptime; remainder = 0
    }
    func reset() {
        radio.cancel(); spaceHeld = false; battle.reset(); selected = Set(battle.living(.blue).map(\.id))
        dispatches.removeAll(); marker = nil; time = 0; blueCount = 18; redCount = 18
        remainder = 0; phase = .deployment; clock.frame &+= 1
    }
    func select(_ kind: Kind?) {
        selected = Set(battle.living(.blue).filter { kind == nil || $0.kind == kind }.map(\.id))
    }
    private func log(_ source: String, _ words: String, _ detail: String, _ accepted: Bool) {
        dispatches.insert(.init(source: source, words: words, detail: detail, accepted: accepted), at: 0)
        if dispatches.count > 20 { dispatches.removeLast() }
        clock.frame &+= 1
    }
    func submit(_ text: String, source: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !phase.finished else { return }
        do {
            guard let model else { throw OrderError("The order model is missing from the app bundle.") }
            let parsed = try model.interpret(text, marker: marker)
            let living = battle.living(.blue)
            var recipients = selected
            if let kinds = parsed.actors { recipients = Set(living.filter { kinds.contains($0.kind) }.map(\.id)) }
            else if parsed.entireArmy { recipients = Set(living.map(\.id)) }
            let count = battle.issue(parsed.order, to: recipients)
            guard count > 0 else { throw OrderError("Select a surviving unit, or name a unit type.") }
            selected = recipients
            let target = parsed.order.focus.map { "enemy " + $0.rawValue.lowercased() } ?? parsed.place
            let types = Set(living.filter { recipients.contains($0.id) }.map(\.kind))
            let group = types.count == 1 ? types.first!.rawValue.lowercased() : "troops"
            let verb = ["move":"move","attack":"engage","hold":"hold","retreat":"fall back"][parsed.order.action.rawValue]!
            log(source, text, "\(count) \(group) · \(verb)" + (target.map { " · " + $0 } ?? ""), true)
        } catch { log(source, text, error.localizedDescription, false) }
    }
    func click(world p: Point, secondary: Bool, shift: Bool) {
        guard art.map.contains(p.cell), !phase.finished else { return }
        let closest = battle.units.filter { $0.alive && (secondary ? $0.side == .red : $0.side == .blue) }
            .min { p.distance(to: $0.p) < p.distance(to: $1.p) }
        if let u = closest, p.distance(to: u.p) <= 0.66 {
            if secondary {
                let n = battle.issue(Order(.attack, foeID: u.id), to: selected)
                log("MAP", "Engage enemy \(u.kind.rawValue.lowercased())", "\(n) troops assigned", n > 0)
            } else if shift {
                if selected.contains(u.id) { selected.remove(u.id) } else { selected.insert(u.id) }
            } else { selected = [u.id] }
            return
        }
        guard art.map[p.cell].walkable else { log("MAP", "Impassable terrain", "Choose open land or a bridge.", false); return }
        marker = p.cell
        if secondary { submit("Move to the marker", source: "MAP") }
    }
    func box(_ a: Point, _ b: Point, additive: Bool) {
        let ids = battle.living(.blue).filter {
            (min(a.x,b.x)...max(a.x,b.x)).contains($0.p.x) && (min(a.y,b.y)...max(a.y,b.y)).contains($0.p.y)
        }.map(\.id)
        if additive { selected.formUnion(ids) } else { selected = Set(ids) }
    }
}
