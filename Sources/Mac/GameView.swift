import SwiftUI

struct SmallCaps: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size:10,weight:.bold,design:.monospaced)).tracking(1.35) }
}

private struct Crest: View {
    var body: some View {
        Canvas { c, size in
            let s = size.width / 36
            var g = c; g.scaleBy(x:s,y:s)
            var p = Path(); p.move(to:CGPoint(x:4,y:3)); p.addLine(to:CGPoint(x:32,y:3))
            p.addLine(to:CGPoint(x:30,y:25)); p.addLine(to:CGPoint(x:18,y:34))
            p.addLine(to:CGPoint(x:6,y:25)); p.closeSubpath()
            g.stroke(p,with:.color(.gold),lineWidth:1.3)
            for x in [12,18,24] {
                let top = x == 18 ? 7.0 : 12.0
                var line = Path(); line.move(to:CGPoint(x:Double(x),y:26)); line.addLine(to:CGPoint(x:Double(x),y:top))
                g.stroke(line,with:.color(.gold),lineWidth:1.5)
                var point = Path(); point.move(to:CGPoint(x:Double(x)-2.1,y:top+4))
                point.addLine(to:CGPoint(x:Double(x),y:top)); point.addLine(to:CGPoint(x:Double(x)+2.1,y:top+4))
                g.stroke(point,with:.color(.gold),lineWidth:1.1)
            }
        }.frame(width:36,height:36)
    }
}

@MainActor struct GameView: View {
    @ObservedObject var game: GameStore
    @State private var draft = ""
    @FocusState private var typing: Bool
    private let examples = ["Archers, hold the north bridge","Cavalry, attack enemy archers","Infantry, fall back to camp"]
    var body: some View {
        VStack(spacing:0) {
            header
            HStack(spacing:0) {
                VStack(alignment:.leading,spacing:0) {
                    HStack(alignment:.center) {
                        VStack(alignment:.leading,spacing:2) {
                            SmallCaps("BATTLEFIELD").foregroundStyle(Color.ink.opacity(0.58))
                            Text("Alder Crossing").font(.system(size:32,weight:.medium,design:.serif)).foregroundStyle(Color.ink)
                        }
                        Spacer()
                        Button { game.recon.toggle() } label: {
                            Label(game.recon ? "Hide recon" : "Recon grid",systemImage:"square.grid.3x3")
                                .font(.system(size:12,weight:.semibold)).padding(.horizontal,10).padding(.vertical,7)
                                .background(game.recon ? Color.ink : .clear,in:RoundedRectangle(cornerRadius:5))
                                .foregroundStyle(game.recon ? Color.gold : .ink)
                                .overlay(RoundedRectangle(cornerRadius:5).strokeBorder(Color.ink.opacity(0.28)))
                        }.buttonStyle(.plain).help("Show terrain classifications and selected routes (V)")
                    }.padding(.bottom,12)
                    Spacer(minLength:0)
                    Battlefield(game:game,clock:game.clock)
                    Spacer(minLength:0)
                    HStack(spacing:6) {
                        if game.recon {
                            labelDot(.red.opacity(0.55),"Blocked"); labelDot(.slate,"Slow forest"); labelDot(.gold,"Bridge / route")
                        } else {
                            Image(systemName:"cursorarrow").font(.system(size:10))
                            Text("Click a unit to select · Drag for a group · Right-click to order")
                        }
                        Spacer(minLength:2)
                        Text("\(game.selected.count) selected").fontWeight(.semibold)
                    }.font(.system(size:11)).foregroundStyle(Color.ink.opacity(0.77)).padding(.top,10)
                }.padding(18).frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.paper)
                Rectangle().fill(Color.ink.opacity(0.25)).frame(width:1)
                sidebar.frame(width:240)
            }
            commandBar
        }
        .frame(minWidth:880,minHeight:580)
        .onAppear { game.startUI() }.onDisappear { game.stopUI() }
        .onChange(of:game.focusCommand) { typing = true }
        .sheet(isPresented:$game.showGuide) { guide }
    }
    private func labelDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing:4) { Circle().fill(color).frame(width:8,height:8); Text(text) }
    }
    private var header: some View {
        HStack(spacing:12) {
            Crest()
            Text("Bannerfall").font(.system(size:29,weight:.semibold,design:.serif)).foregroundStyle(Color.paper)
            Rectangle().fill(.white.opacity(0.23)).frame(width:1,height:25).padding(.horizontal,5)
            SmallCaps("FIELD COMMAND").foregroundStyle(Color.gold)
            Spacer()
            HStack(spacing:7) {
                Circle().fill(game.phase == .running ? Color(rgb:0x8cbb8f) : .gold).frame(width:7,height:7)
                Text(phaseName).font(.system(size:12,weight:.medium))
                Text(String(format:"%02d:%02d",game.time/60,game.time%60))
                    .font(.system(size:12,design:.monospaced)).foregroundStyle(.white.opacity(0.63))
            }.foregroundStyle(Color.paper)
            Button { typing = false; game.toggleBattle() } label: {
                Label(battleButton,systemImage:game.phase == .running ? "pause.fill" : "play.fill")
                    .font(.system(size:12,weight:.bold)).foregroundStyle(Color.ink)
                    .padding(.horizontal,12).padding(.vertical,8).background(Color.gold,in:RoundedRectangle(cornerRadius:5))
            }.buttonStyle(.plain).help("Begin, pause or resume the battle (P)")
            Button { game.showGuide.toggle() } label: { Image(systemName:"questionmark.circle").font(.system(size:16)) }
                .buttonStyle(.plain).foregroundStyle(Color.paper).help("Controls and example orders").accessibilityLabel("Field guide")
        }.padding(.horizontal,19).padding(.vertical,10).background(Color.ink)
    }
    private var phaseName: String {
        switch game.phase {
        case .deployment: return "Deployment"; case .running: return "In battle"; case .paused: return "Paused"
        case .victory: return "Victory"; case .defeat: return "Defeat"; case .draw: return "Draw"
        }
    }
    private var battleButton: String {
        switch game.phase { case .deployment: return "Begin battle"; case .running: return "Pause"
        case .paused: return "Resume"; default: return "New battle" }
    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:0) {
            SmallCaps("FORCES").foregroundStyle(Color.gold)
            HStack(spacing:16) {
                strength("West · You",game.blueCount,Color(rgb:0x73b2cb))
                strength("East · AI",game.redCount,Color(rgb:0xe99880))
            }.padding(.vertical,10)
            GeometryReader { geo in
                HStack(spacing:2) {
                    Rectangle().fill(Color.blueBanner).frame(width:max(0,(geo.size.width-2)*Double(game.blueCount)/Double(max(1,game.blueCount+game.redCount))))
                    Rectangle().fill(Color.redBanner)
                }
            }.frame(height:4).clipShape(Capsule())
            divider
            HStack { SmallCaps("YOUR TROOPS"); Spacer(); Button("All [0]") { game.select(nil); typing = false }.buttonStyle(.plain).font(.caption).foregroundStyle(Color.gold) }
            ForEach(Array(Kind.allCases.enumerated()),id:\.element) { i,kind in
                let alive = game.battle.living(.blue).filter { $0.kind == kind }
                let ids = Set(alive.map(\.id)), active = !ids.isEmpty && ids == game.selected
                Button {
                    game.select(kind); typing = false
                } label: {
                    HStack(spacing:9) {
                        Canvas { context,size in
                            var c = context; c.translateBy(x:size.width/2,y:size.height*0.65); c.scaleBy(x:26,y:26)
                            drawFighter(kind,.blue,context:c)
                        }.frame(width:34,height:34).background(Color.paper,in:RoundedRectangle(cornerRadius:5))
                        VStack(alignment:.leading,spacing:2) {
                            Text(kind.rawValue).font(.system(size:13,weight:.semibold))
                            Text(kind.role).font(.system(size:10)).foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer()
                        Text("\(alive.count)").font(.system(size:17,design:.serif))
                        Text("\(i+1)").font(.system(size:9,design:.monospaced)).foregroundStyle(.white.opacity(0.70))
                            .frame(width:14,height:14).overlay(RoundedRectangle(cornerRadius:2).strokeBorder(.white.opacity(0.25)))
                    }.padding(5).background(active ? Color.white.opacity(0.13) : .clear,in:RoundedRectangle(cornerRadius:5))
                }.buttonStyle(.plain).disabled(alive.isEmpty).accessibilityLabel("Select \(kind.rawValue)")
            }.padding(.top,5)
            divider
            HStack {
                SmallCaps("ORDER LOG").foregroundStyle(Color.gold)
                Spacer()
                Button("Show logs") { game.revealLog() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(Color.gold)
                    .help("Reveal this playtest log in Finder")
            }.padding(.bottom,8)
            if let error = game.logError {
                Text("Couldn’t save the playtest log. \(error)")
                    .font(.caption).foregroundStyle(Color(rgb:0xffad96)).padding(.bottom,6)
            }
            if game.dispatches.isEmpty {
                Text("Give orders during deployment, then begin the battle. Defeat the eastern army.")
                    .font(.system(size:12)).foregroundStyle(Color.paper.opacity(0.85)).fixedSize(horizontal:false,vertical:true)
                Button("Example orders ↗") { game.showGuide = true }.buttonStyle(.plain).font(.caption).foregroundStyle(Color.gold).padding(.top,8)
            } else {
                ScrollView {
                    VStack(alignment:.leading,spacing:10) {
                        ForEach(game.dispatches) { d in
                            VStack(alignment:.leading,spacing:3) {
                                HStack {
                                    Text(d.source).font(.system(size:9,weight:.bold,design:.monospaced)).tracking(1).foregroundStyle(Color.paper.opacity(0.57))
                                    Spacer()
                                    Menu {
                                        ForEach(ReviewFlag.allCases, id: \.self) { reason in
                                            if reason != .transcription || d.source == "VOICE" {
                                                Button(reason.label) { game.flag(d.id, as: reason) }
                                            }
                                        }
                                        if d.flag != nil { Button("Clear flag") { game.flag(d.id, as: nil) } }
                                    } label: {
                                        Image(systemName: d.flag == nil ? "flag" : "flag.fill")
                                            .foregroundStyle(d.flag == nil ? Color.paper.opacity(0.65) : Color.gold)
                                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                        .help(d.flag?.label ?? "Flag this order for review")
                                        .accessibilityLabel("Flag order for review")
                                }
                                Text(d.words).font(.system(size:12,weight:.medium))
                                Text(d.detail).font(.system(size:11)).foregroundStyle(d.accepted ? Color.gold : Color(rgb:0xffad96))
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }
                    }
                }
            }
            Spacer(minLength:2)
            if game.phase != .deployment && !game.phase.finished {
                Button("Restart battle") { typing = false; game.reset() }.buttonStyle(.plain).font(.caption).foregroundStyle(Color.paper.opacity(0.7)).padding(.top,6)
            }
        }.padding(16).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(Color.slate).foregroundStyle(Color.paper)
    }
    private func strength(_ name: String,_ count: Int,_ color: Color) -> some View {
        VStack(alignment:.leading,spacing:1) {
            Text("\(count)").font(.system(size:27,weight:.semibold,design:.serif))
            labelDot(color,name).font(.system(size:10,weight:.medium))
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private var divider: some View { Rectangle().fill(.white.opacity(0.19)).frame(height:1).padding(.vertical,13) }
    private var commandBar: some View {
        HStack(spacing:16) {
            RadioControl(radio:game.radio,finished:game.phase.finished,onPress:{ typing = false })
            Rectangle().fill(.white.opacity(0.2)).frame(width:1,height:35)
            VStack(alignment:.leading,spacing:4) {
                SmallCaps("WRITTEN ORDER").foregroundStyle(Color.gold)
                HStack {
                    TextField("e.g. Archers, hold the north bridge",text:$draft).textFieldStyle(.plain)
                        .font(.system(size:14)).focused($typing).onSubmit(sendDraft)
                        .accessibilityLabel("Written order")
                    Button { sendDraft() } label: { Image(systemName:"return").padding(.horizontal,6) }
                        .buttonStyle(.plain).disabled(draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || game.phase.finished)
                        .accessibilityLabel("Send written order")
                }
            }.disabled(game.phase.finished)
        }.padding(.horizontal,19).padding(.vertical,11).background(Color.ink).foregroundStyle(Color.paper).environment(\.colorScheme,.dark)
    }
    private func sendDraft() {
        guard !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        game.submit(draft,source:"TYPED"); draft = ""; typing = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
    private var guide: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Field guide").font(.system(size:29,weight:.semibold,design:.serif))
            Text("Command the blue western army. The red army advances when you begin the battle.").font(.body)
            SmallCaps("TRY AN ORDER")
            ForEach(examples,id:\.self) { order in
                Button { game.showGuide = false; game.submit(order,source:"GUIDE") } label: {
                    HStack { Text(order); Spacer(); Image(systemName:"arrow.turn.down.left") }.contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(game.phase.finished)
            }
            Divider()
            Text("Space  Hold to talk after enabling voice\nReturn  Type an order    ·    Esc  Leave the text field\n0  All troops    ·    1  Archers    ·    2  Infantry    ·    3  Cavalry\nP  Begin / pause    ·    V  Terrain and routes")
                .font(.system(size:12,design:.monospaced)).lineSpacing(4)
            Text("Click the ground to mark “there.” Right-click ground to move, or an enemy to attack. Drag to select a group. Hold Shift to add units.")
                .font(.callout)
            Button("Back to map") { game.showGuide = false }.keyboardShortcut(.defaultAction)
        }.padding(24).frame(width:448).background(Color.paper).foregroundStyle(Color.ink)
    }
}

@MainActor private struct RadioControl: View {
    @ObservedObject var radio: VoiceRadio
    let finished: Bool
    let onPress: () -> Void
    @State private var held = false
    private var title: String {
        switch radio.state { case .idle:return "Enable voice"; case .preparing:return "Preparing voice"
        case .ready:return "Hold to talk"; case .recording:return "Listening"; case .processing:return "Decoding"
        case .unavailable:return "Retry voice" }
    }
    var body: some View {
        HStack(spacing:10) {
            Image(systemName:radio.state == .recording ? "waveform" : "mic.fill")
                .font(.system(size:19,weight:.semibold)).foregroundStyle(radio.state == .recording ? Color.white : .ink)
                .frame(width:37,height:37).background(radio.state == .recording ? Color.redBanner : .gold,in:RoundedRectangle(cornerRadius:7))
            VStack(alignment:.leading,spacing:3) {
                Text(title).font(.system(size:14,weight:.bold))
                Text(radio.note).font(.system(size:10)).foregroundStyle(Color.paper.opacity(0.76)).lineLimit(3)
            }
        }.frame(width:245,alignment:.leading).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onChanged { _ in
                guard !held, !finished else { return }; held = true; onPress(); radio.press()
            }.onEnded { _ in held = false; radio.release() })
            .accessibilityElement(children:.combine).accessibilityAddTraits(.isButton)
            .accessibilityAction { if radio.state == .recording { radio.release() } else if !finished { radio.press() } }
            .help("Enable once, then hold Space or hold this button while speaking.")
    }
}
