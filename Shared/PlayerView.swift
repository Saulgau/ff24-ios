import SwiftUI
import AVKit
import MediaPlayer

// Eigener Player wie der Web-PC-Player (beta/index.php .plr), 2026-10-22 (User: „100 % gleich wie PC-Player, aber nativ“).
// Bild über AVPlayerLayer (Hardware-Dekodierung durch AVFoundation), Steuerung selbst gezeichnet.
// Apple TV: eigenes Fokus-Modell (PF) – OK/Klick drückt immer den markierten Knopf; erscheint
// „Intro überspringen“ oder „Nächste Folge“, bekommt dieser Knopf den Fokus (wie Netflix/Prime).

enum PF { case rep, cc, air, close, rw, play, ff, seek, next, skip, nextGo }

struct PlayerView: View {
    let req: PlayRequest
    @StateObject private var m = PlayerModel()
    @Environment(\.dismiss) var dismiss
    @State private var report = false

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 480 && FF.scale == 1
            ZStack {
                Color.black.ignoresSafeArea()
                if let p = m.player { VideoSurface(player: p, model: m).ignoresSafeArea() }
                if !m.cue.isEmpty {
                    VStack { Spacer()
                        Text(m.cue).font(.inter(compact ? 17 : 22, .medium)).foregroundColor(.white).multilineTextAlignment(.center)
                            .padding(.horizontal, 10).padding(.vertical, 4).background(Color.black.opacity(0.6))
                            .padding(.bottom, (m.visible ? 120 : 50) * FF.scale)
                    }.allowsHitTesting(false)
                }
                #if os(tvOS)
                if m.error == nil && !report { RemoteCatcher(m: m).ignoresSafeArea() }
                #endif
                PlayerOverlay(m: m, compact: compact, onReport: { m.player?.pause(); report = true })
                if let e = m.error {
                    VStack(spacing: 16) {
                        Text("Wiedergabe nicht möglich").font(.inter(22, .bold)).foregroundColor(.white)
                        Text(e).font(.inter(15)).foregroundColor(Color(hex: 0xCFD3D8)).multilineTextAlignment(.center).frame(maxWidth: 520 * FF.scale)
                        HStack(spacing: 10) {
                            GreyButton(label: "Problem melden") { report = true }
                            GreyButton(label: "Schließen", white: true) { close() }
                        }
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.9))
                }
            }
        }
        .ignoresSafeArea()
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
        .task { m.onClose = { close() }; m.onReportFromRemote = { report = true }; await m.start(req) }
        .onAppear { Orientation.landscape(true) }
        .onDisappear { m.stop(); Orientation.landscape(false) }
        .sheet(isPresented: $report) {
            ReportSheet(title: (m.info?.title ?? "") + ((m.info?.sub).map { " – \($0)" } ?? ""), url: reportURL, pos: m.player?.currentTime().seconds ?? 0)
        }
    }

    var reportURL: String {
        guard let i = m.info else { return BASE }
        return i.type == "s" ? "\(BASE)/player/?type=series&s=\(i.id)&season=\(i.season ?? 1)&ep=\(i.ep ?? 1)" : "\(BASE)/player/?s=\(i.id)"
    }

    func close() { m.stop(); dismiss() }
}

/// iPhone: Player quer wie Netflix/Prime, beim Schließen zurück hochkant.
enum Orientation {
    static func landscape(_ on: Bool) {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .phone,
              let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: on ? .landscape : .portrait)) { _ in }
        #endif
    }
}

// MARK: - Oberfläche (Maße = Web-CSS in px; tvOS × FF.scale wie Android TV)

private extension View {
    /// Antippen nur auf iPhone/iPad – auf Apple TV gibt es nur die Fernbedienung (sonst stiehlt SwiftUI den Fokus).
    @ViewBuilder func tap(_ a: @escaping () -> Void) -> some View {
        #if os(tvOS)
        self
        #else
        self.contentShape(Rectangle()).onTapGesture(perform: a)
        #endif
    }
}

struct PlayerOverlay: View {
    @ObservedObject var m: PlayerModel
    let compact: Bool
    let onReport: () -> Void
    private let k = FF.scale
    private var key: Bool { m.keyMode }

    var body: some View {
        ZStack {
            // Doppeltipp links/rechts = 10 s, einfacher Tipp = Steuerung ein/aus (iPhone/iPad)
            #if os(iOS)
            Color.clear.contentShape(Rectangle())
                .gesture(SpatialTapGesture(count: 2).onEnded { v in m.touched(); m.seekBy(v.location.x < UIScreen.main.bounds.width / 2 ? -10 : 10) }
                    .exclusively(before: TapGesture().onEnded { m.touched(); m.visible.toggle() }))
            #endif

            // Pause-Infos wie .plr.pl .pause
            if m.pausedLong, let i = m.info {
                LinearGradient(stops: [.init(color: .black.opacity(0.8), location: 0), .init(color: .black.opacity(0.25), location: 0.6), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing).allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                    if !i.logo.isEmpty {
                        Img(url: i.logo, mode: .fit).frame(maxWidth: 380 * k, maxHeight: 150 * k, alignment: .bottomLeading).padding(.bottom, 16 * k)
                    } else {
                        Text(i.title).font(.inter(34, .heavy)).foregroundColor(.white).padding(.bottom, 10 * k)
                    }
                    if i.type == "s" { Text(i.sub).font(.inter(18, .bold)).foregroundColor(.white).padding(.bottom, 10 * k) }
                    if !i.desc.isEmpty { Text(i.desc).font(.inter(16)).foregroundColor(Color(hex: 0xE7EAED)).lineLimit(4).lineSpacing(5) }
                }.frame(maxWidth: 560 * k, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, (compact ? 28 : 48) * k).padding(.bottom, (compact ? 100 : 140) * k).allowsHitTesting(false).transition(.opacity)
            }

            controls.opacity(m.visible ? 1 : 0).allowsHitTesting(m.visible).animation(.easeInOut(duration: 0.3), value: m.visible)

            if m.loading && m.error == nil {
                ProgressView().tint(.white).scaleEffect(1.8 * k).allowsHitTesting(false)
            }

            // Nächste-Folge-Karte / Intro überspringen (auch bei ausgeblendeter Steuerung)
            VStack { Spacer(); HStack { Spacer()
                if m.showNext, let n = m.info?.next { nextCard(n) }
                else if m.showSkip { skipButton }
            } }
            .padding(.trailing, (compact ? 16 : 28) * k).padding(.bottom, (compact ? 96 : 110) * k)
        }
    }

    // ── Steuerung ──
    var controls: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.72), .clear], startPoint: .top, endPoint: .bottom).frame(height: (compact ? 100 : 130) * k)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom).frame(height: (compact ? 110 : 140) * k)
            }.allowsHitTesting(false)

            // oben: Titel mittig, Knöpfe rechts (Melden, Untertitel, AirPlay, Schließen)
            VStack { ZStack(alignment: .top) {
                VStack(spacing: 2 * k) {
                    Text(m.info?.title ?? "").font(.inter(compact ? 16 : 20, .bold)).lineLimit(1)
                    if let s = m.info?.sub, !s.isEmpty { Text(s).font(.inter(compact ? 13 : 15)).foregroundColor(Color(hex: 0xD4D8DC)).lineLimit(1) }
                }.foregroundColor(.white).frame(maxWidth: 0.52 * screenW).padding(.top, (compact ? 14 : 22) * k)
                HStack(spacing: 6 * k) {
                    Spacer()
                    roundBtn(.rep, "Problem melden") { WebIcon.flag } action: { onReport() }
                    if m.hasCc { roundBtn(.cc, "Untertitel", active: m.ccOn) { WebIcon.cc } action: { m.toggleCc() } }
                    #if os(iOS)
                    AirPlayButton().frame(width: (compact ? 40 : 48), height: (compact ? 40 : 48))
                    #endif
                    roundBtn(.close, "Schließen") { WebIcon.x } action: { m.onClose?() }
                }.padding(.horizontal, (compact ? 8 : 28) * k).padding(.top, (compact ? 8 : 20) * k)
            }; Spacer() }

            // Mitte: 10 zurück / Play / 10 vor
            HStack(spacing: (compact ? 44 : 96) * k) {
                midBtn(.rw, (compact ? 44 : 60) * k) { s in WebIcon.rw.frame(width: s, height: s) } action: { m.seekBy(-10) }
                midBtn(.play, (compact ? 62 : 96) * k) { s in
                    Group { if m.loading { Color.clear } else if m.playing { WebIcon.pause } else { WebIcon.play } }.frame(width: s, height: s)
                } action: { m.toggle() }
                midBtn(.ff, (compact ? 44 : 60) * k) { s in WebIcon.ff.frame(width: s, height: s) } action: { m.seekBy(10) }
            }

            // unten: Zeit | Leiste | Rest | Nächste Folge
            VStack { Spacer()
                HStack(spacing: (compact ? 10 : 16) * k) {
                    let shown = m.scrub ?? m.pos
                    Text(ptime(shown)).font(.inter(compact ? 13 : 15, .semibold)).monospacedDigit()
                    SeekBar(m: m, shown: shown)
                    Text("-" + ptime(max(0, m.dur - shown))).font(.inter(compact ? 13 : 15, .semibold)).monospacedDigit()
                    if let n = m.info?.next, !m.showNext {
                        let f = key && m.focus == .next
                        HStack(spacing: 8 * k) {
                            Text("Nächste Folge").font(.inter(compact ? 13 : 16, .bold))
                            WebIcon.next.frame(width: 20 * k, height: 20 * k)
                        }.foregroundColor(f ? FF.dark : .white)
                            .padding(.horizontal, (compact ? 10 : 16) * k).padding(.vertical, (compact ? 8 : 10) * k)
                            .background(RoundedRectangle(cornerRadius: 8 * k).fill(f ? Color.white : Color(hex: 0x33373D, alpha: 0.85)))
                            .scaleEffect(f ? 1.06 : 1).tap { m.playNext() }.accessibilityLabel("Nächste Folge S\(n.season) F\(n.ep)")
                    }
                }.foregroundColor(.white)
                .padding(.horizontal, (compact ? 14 : 28) * k).padding(.bottom, (compact ? 14 : 24) * k)
            }
        }
    }

    var screenW: CGFloat {
        #if os(iOS)
        UIScreen.main.bounds.width
        #else
        1920
        #endif
    }

    func roundBtn<I: View>(_ f: PF, _ label: String, active: Bool = false, @ViewBuilder icon: () -> I, action: @escaping () -> Void) -> some View {
        let on = key && m.focus == f
        let s = (compact ? 40 : 48) * k
        return icon().frame(width: (compact ? 24 : 28) * k, height: (compact ? 24 : 28) * k)
            .foregroundColor(on ? FF.dark : (active ? FF.blue : .white))
            .frame(width: s, height: s).background(Circle().fill(on ? Color.white : Color.clear))
            .scaleEffect(on ? 1.12 : 1).animation(.easeOut(duration: 0.15), value: on)
            .tap(action).accessibilityLabel(label)
    }

    func midBtn<I: View>(_ f: PF, _ s: CGFloat, @ViewBuilder icon: (CGFloat) -> I, action: @escaping () -> Void) -> some View {
        let on = key && m.focus == f
        return icon(s).foregroundColor(.white).shadow(color: .black.opacity(0.5), radius: 10, y: 2)
            .padding(10 * k)
            .background(Circle().fill(Color.white.opacity(on ? 0.2 : 0)))
            .overlay(Circle().stroke(Color.white, lineWidth: on ? 2 * k : 0))
            .scaleEffect(on ? 1.18 : 1).animation(.easeOut(duration: 0.15), value: on)
            .tap(action)
    }

    var skipButton: some View {
        let on = m.focus == .skip && (key || !m.visible)
        return HStack(spacing: 8 * k) {
            Text(m.skipLabel).font(.inter(compact ? 15 : 16, .bold))
            WebIcon.skip.frame(width: 20 * k, height: 20 * k)
        }.foregroundColor(FF.dark).padding(.horizontal, (compact ? 16 : 20) * k).frame(minHeight: (compact ? 42 : 46) * k)
            .background(RoundedRectangle(cornerRadius: 8 * k).fill(Color.white.opacity(on ? 1 : 0.94)))
            .overlay(RoundedRectangle(cornerRadius: 8 * k).stroke(FF.blue, lineWidth: on && key ? 3 * k : 0))
            .shadow(color: .black.opacity(0.45), radius: 12 * k, y: 6 * k)
            .scaleEffect(on && key ? 1.08 : 1).animation(.easeOut(duration: 0.15), value: on)
            .tap { m.skipIntro() }
    }

    func nextCard(_ n: (season: Int, ep: Int, title: String, thumb: String)) -> some View {
        let on = m.focus == .nextGo && (key || !m.visible)
        let prog = m.countdown >= 0 ? Double(10 - m.countdown) / 10 : 0
        return VStack(spacing: 0) {
            if !compact {
                ZStack(alignment: .bottomLeading) {
                    Color(hex: 0x111111)
                    if !n.thumb.isEmpty { Img(url: n.thumb) }
                    bar(prog)
                }.aspectRatio(16 / 9, contentMode: .fit).clipped()
            } else { bar(prog) }
            HStack(spacing: 12 * k) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NÄCHSTE FOLGE").font(.inter(12, .bold)).kerning(0.7 * k).foregroundColor(FF.text2)
                    Text("S\(n.season) F\(n.ep)" + (n.title.isEmpty ? "" : " · \(n.title)")).font(.inter(16, .bold)).foregroundColor(.white).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text("Abspielen").font(.inter(15, .bold)).foregroundColor(FF.dark).padding(.horizontal, 16 * k).frame(minHeight: 42 * k)
                    .background(RoundedRectangle(cornerRadius: 8 * k).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 8 * k).stroke(FF.blue, lineWidth: on && key ? 3 * k : 0))
                    .scaleEffect(on && key ? 1.06 : 1).tap { m.playNext() }
            }.padding(.horizontal, 14 * k).padding(.vertical, 12 * k)
        }.frame(width: (compact ? 300 : 380) * k)
            .background(Color(hex: 0x191E25, alpha: 0.97)).clipShape(RoundedRectangle(cornerRadius: 10 * k))
            .shadow(color: .black.opacity(0.6), radius: 20 * k, y: 10 * k)
    }

    func bar(_ p: Double) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) { Color.white.opacity(0.25); FF.blue.frame(width: g.size.width * p) }
        }.frame(height: 4 * k)
    }
}

func ptime(_ t: Double) -> String {
    let s = Int(max(0, t.isFinite ? t : 0))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

/// .seek: Spur 4 (Fokus/Ziehen 8 + Knopf), weiß gesehen, 40 % gepuffert.
struct SeekBar: View {
    @ObservedObject var m: PlayerModel
    let shown: Double
    @State private var drag = false
    private let k = FF.scale

    var body: some View {
        GeometryReader { g in
            let big = drag || (m.keyMode && m.focus == .seek)
            let d = max(m.dur, 1)
            let x = g.size.width * CGFloat(min(1, max(0, shown / d)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.3)).frame(height: (big ? 8 : 4) * k)
                Capsule().fill(Color.white.opacity(0.4)).frame(width: g.size.width * CGFloat(min(1, m.buffered / d)), height: (big ? 8 : 4) * k)
                Capsule().fill(Color.white).frame(width: x, height: (big ? 8 : 4) * k)
                if big {
                    Circle().fill(Color.white).frame(width: 18 * k, height: 18 * k).offset(x: x - 9 * k)
                    if m.scrub != nil {
                        Text(ptime(shown)).font(.inter(14, .semibold)).foregroundColor(.white).monospacedDigit()
                            .padding(.horizontal, 9 * k).padding(.vertical, 5 * k)
                            .background(RoundedRectangle(cornerRadius: 5 * k).fill(Color(hex: 0x191E25, alpha: 0.96)))
                            .fixedSize().position(x: min(max(x, 40 * k), g.size.width - 40 * k), y: -20 * k)
                    }
                }
            }.frame(height: g.size.height)
            #if os(iOS)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in drag = true; m.touched(); m.scrub = Double(min(max(0, v.location.x / g.size.width), 1)) * d }
                .onEnded { _ in drag = false; if let s = m.scrub { m.seekTo(s) } })
            #endif
        }.frame(height: 28 * k)
    }
}

// MARK: - Website-Icons (gleiche SVG-Pfade, 24er bzw. 48er Raster)

enum WebIcon {
    static var play: some View { Glyph(grid: 24, fill: true) { p in
        p.move(to: .init(x: 7, y: 4.8)); p.addLine(to: .init(x: 19.5, y: 12)); p.addLine(to: .init(x: 7, y: 19.2)); p.closeSubpath()
    }.overlay(Glyph(grid: 24, fill: false, width: 1.6) { p in
        p.move(to: .init(x: 7.8, y: 5.6)); p.addLine(to: .init(x: 18.7, y: 12)); p.addLine(to: .init(x: 7.8, y: 18.4)); p.closeSubpath()
    }) }
    static var pause: some View { Glyph(grid: 24, fill: true) { p in
        p.addRoundedRect(in: CGRect(x: 6, y: 4.5, width: 4, height: 15), cornerSize: CGSize(width: 1, height: 1))
        p.addRoundedRect(in: CGRect(x: 14, y: 4.5, width: 4, height: 15), cornerSize: CGSize(width: 1, height: 1))
    } }
    static func seek(back: Bool) -> some View {
        ZStack {
            Glyph(grid: 48, fill: false, width: 2.4) { p in
                if back {
                    p.addArc(center: .init(x: 24, y: 24), radius: 13, startAngle: .degrees(180), endAngle: .degrees(225), clockwise: true)
                    p.move(to: .init(x: 11, y: 9)); p.addLine(to: .init(x: 11, y: 15.5)); p.addLine(to: .init(x: 17.5, y: 15.5))
                } else {
                    p.addArc(center: .init(x: 24, y: 24), radius: 13, startAngle: .degrees(0), endAngle: .degrees(315), clockwise: false)
                    p.move(to: .init(x: 37, y: 9)); p.addLine(to: .init(x: 37, y: 15.5)); p.addLine(to: .init(x: 30.5, y: 15.5))
                }
            }
            GeometryReader { g in
                Text("10").font(.system(size: g.size.width * 12.5 / 48, weight: .bold)).foregroundColor(.white)
                    .position(x: g.size.width * (back ? 24.5 : 23.5) / 48, y: g.size.height * 24.6 / 48)
            }
        }
    }
    static var rw: some View { seek(back: true) }
    static var ff: some View { seek(back: false) }
    static var x: some View { Glyph(grid: 24, fill: false, width: 2.2) { p in
        p.move(to: .init(x: 6, y: 6)); p.addLine(to: .init(x: 18, y: 18)); p.move(to: .init(x: 18, y: 6)); p.addLine(to: .init(x: 6, y: 18))
    } }
    static var flag: some View { Glyph(grid: 24, fill: false, width: 1.9) { p in
        p.move(to: .init(x: 5, y: 21)); p.addLine(to: .init(x: 5, y: 4))
        p.move(to: .init(x: 5, y: 4)); p.addLines([.init(x: 16, y: 4), .init(x: 14.5, y: 8), .init(x: 16, y: 12), .init(x: 5, y: 12)])
    } }
    static var cc: some View { Glyph(grid: 24, fill: false, width: 1.9) { p in
        p.addLines([.init(x: 4, y: 5), .init(x: 20, y: 5), .init(x: 21, y: 6), .init(x: 21, y: 16), .init(x: 20, y: 17), .init(x: 11, y: 17),
                    .init(x: 6.5, y: 20.5), .init(x: 6.5, y: 17), .init(x: 4, y: 17), .init(x: 3, y: 16), .init(x: 3, y: 6)]); p.closeSubpath()
        p.move(to: .init(x: 7, y: 10)); p.addLine(to: .init(x: 11, y: 10)); p.move(to: .init(x: 13, y: 10)); p.addLine(to: .init(x: 17, y: 10))
        p.move(to: .init(x: 7, y: 13.5)); p.addLine(to: .init(x: 14, y: 13.5))
    } }
    static var skip: some View { Glyph(grid: 24, fill: true) { p in
        p.addLines([.init(x: 5, y: 5.5), .init(x: 5, y: 18.5), .init(x: 13, y: 12)]); p.closeSubpath()
        p.addLines([.init(x: 13, y: 5.5), .init(x: 13, y: 18.5), .init(x: 21, y: 12)]); p.closeSubpath()
    } }
    static var next: some View { Glyph(grid: 24, fill: true) { p in
        p.addLines([.init(x: 6, y: 5.5), .init(x: 6, y: 18.5), .init(x: 15, y: 12)]); p.closeSubpath()
        p.addRect(CGRect(x: 16, y: 5.5, width: 2.5, height: 13))
    } }
}

/// Ein Pfad im SVG-Raster, auf die Rahmengröße skaliert; Farbe = foregroundColor.
struct Glyph: View {
    let grid: CGFloat
    let fill: Bool
    var width: CGFloat = 0
    let build: (inout Path) -> Void

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height) / grid
            let path = { () -> Path in var p = Path(); build(&p); return p }().applying(CGAffineTransform(scaleX: s, y: s))
            if fill { path.fill() } else { path.stroke(style: StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round)) }
        }
    }
}

// MARK: - Bild (AVPlayerLayer = Hardware-Overlay, Bild-in-Bild auf iPhone/iPad)

struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    let model: PlayerModel

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        #if os(iOS)
        var pip: AVPictureInPictureController?
        #endif
    }

    func makeUIView(context: Context) -> LayerView {
        let v = LayerView()
        v.backgroundColor = .black
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        #if os(iOS)
        if AVPictureInPictureController.isPictureInPictureSupported() {
            v.pip = AVPictureInPictureController(playerLayer: v.playerLayer)
            v.pip?.canStartPictureInPictureAutomaticallyFromInline = true
        }
        #endif
        return v
    }

    func updateUIView(_ v: LayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}

#if os(iOS)
/// AirPlay-Knopf (#p-air) – System-Auswahl der Geräte.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white; v.activeTintColor = UIColor(red: 0.1, green: 0.6, blue: 1, alpha: 1)
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}
#endif

#if os(tvOS)
// MARK: - Apple-TV-Fernbedienung: eine unsichtbare, fokussierte Fläche fängt alle Tasten/Wischgesten

struct RemoteCatcher: UIViewRepresentable {
    let m: PlayerModel

    final class RemoteView: UIView {
        weak var m: PlayerModel?
        private var holdTimer: Timer?
        private var holdCount = 0
        override var canBecomeFocused: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, gestureRecognizers?.isEmpty ?? true else { return }
            for d: UISwipeGestureRecognizer.Direction in [.left, .right, .up, .down] {
                let g = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
                g.direction = d
                addGestureRecognizer(g)
            }
            DispatchQueue.main.async { [weak self] in
                self?.window?.rootViewController?.setNeedsFocusUpdate()
                self?.window?.rootViewController?.updateFocusIfNeeded()
            }
        }

        @objc func swiped(_ g: UISwipeGestureRecognizer) {
            switch g.direction {
            case .left: m?.press(.left, repeatCount: 0)
            case .right: m?.press(.right, repeatCount: 0)
            case .up: m?.press(.up, repeatCount: 0)
            default: m?.press(.down, repeatCount: 0)
            }
        }

        private func map(_ t: UIPress.PressType) -> PlayerModel.Key? {
            switch t {
            case .select: return .ok
            case .playPause: return .playPause
            case .menu: return .back
            case .leftArrow: return .left
            case .rightArrow: return .right
            case .upArrow: return .up
            case .downArrow: return .down
            default: return nil
            }
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var rest = Set<UIPress>()
            for p in presses {
                guard let k = map(p.type) else { rest.insert(p); continue }
                m?.press(k, repeatCount: 0)
                // gedrückt halten links/rechts = weiter spulen, immer schneller
                if k == .left || k == .right {
                    holdTimer?.invalidate(); holdCount = 0
                    holdTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                        guard let self else { return }
                        self.holdCount += 1
                        if self.holdCount > 2 { Task { @MainActor in self.m?.press(k, repeatCount: self.holdCount) } }
                    }
                }
            }
            if !rest.isEmpty { super.pressesBegan(rest, with: event) }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            holdTimer?.invalidate(); holdTimer = nil
            let rest = presses.filter { map($0.type) == nil }
            if !rest.isEmpty { super.pressesEnded(rest, with: event) }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            holdTimer?.invalidate(); holdTimer = nil
            let rest = presses.filter { map($0.type) == nil }
            if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
        }
    }

    func makeUIView(context: Context) -> RemoteView { let v = RemoteView(); v.m = m; return v }
    func updateUIView(_ v: RemoteView, context: Context) { v.m = m }
}
#endif

// MARK: - Logik

@MainActor
final class PlayerModel: NSObject, ObservableObject {
    @Published var player: AVPlayer?
    @Published var info: PlayInfo?
    @Published var cue = ""
    @Published var loading = true
    @Published var error: String?
    @Published var showSkip = false
    @Published var skipLabel = "Intro überspringen"
    private var skipTo = 0.0
    @Published var showNext = false
    /// -1 = kein Countdown; 10…0 am Folgenende (blauer Balken wie Web)
    @Published var countdown = -1
    // eigene Steuerung
    @Published var visible = true
    @Published var focus: PF = .play
    @Published var keyMode = false
    @Published var pos = 0.0
    @Published var dur = 0.0
    @Published var buffered = 0.0
    @Published var playing = false
    @Published var scrub: Double?
    @Published var pausedLong = false
    @Published var ccOn = true
    @Published var hasCc = false
    var onClose: (() -> Void)?

    private var cues: [(Double, Double, String)] = []
    private var obs: Any?
    private var endObs: NSObjectProtocol?
    private var statusObs: NSKeyValueObservation?
    private var rateObs: NSKeyValueObservation?
    private var lastSave = Date.distantPast
    private var lastInput = Date()
    private var nextTimer: Timer?
    private var nextDismissed = false
    private var going = false
    private var scrubTask: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?

    func start(_ req: PlayRequest) async {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        setupRemoteCommands()
        if let t = req.trailer {
            info = nil
            play(url: t.url, title: t.title, poster: "", start: 0)
            return
        }
        await load(type: req.type, id: req.itemId, season: req.season, ep: req.ep, start: req.start)
    }

    func load(type: String, id: String, season: Int, ep: Int, start: Double) async {
        loading = true; error = nil; showNext = false; showSkip = false; nextDismissed = false; cues = []; cue = ""
        countdown = -1; nextTimer?.invalidate(); scrub = nil; pausedLong = false; focus = .play; touchedKey(false)
        var o = await API.getObj("/beta/api.php?q=play&type=\(type)&id=" + API.enc(id) + (type == "s" ? "&season=\(season)&ep=\(ep)" : ""))
        #if os(iOS)
        // 2026-10-22: heruntergeladen -> lokale Datei; ohne Internet komplett aus den gespeicherten Daten
        let dk = Downloads.key(type: type, id: id, season: season, ep: ep)
        if var l = Downloads.shared.offlinePlay(dk) {
            if PlayInfo(o) != nil { o["src"] = l["src"]; o["vtt"] = l["vtt"] }
            else {
                if let n = Downloads.shared.nextDownloaded(after: dk) {
                    l["next"] = ["season": n.season ?? 1, "ep": n.ep ?? 1, "title": n.sub, "thumb": n.poster] as [String: Any]
                } else { l["next"] = nil }
                o = l
            }
        }
        #endif
        guard let i = PlayInfo(o) else {
            loading = false
            error = o.s("error").isEmpty ? "Dieser Titel ist noch nicht verfügbar." : o.s("error"); return
        }
        info = i
        hasCc = !i.vtt.isEmpty; ccOn = Store.shared.subtitlesDefault
        // gespeicherten Fortschritt nutzen, wenn nichts übergeben wurde
        var pos = start
        if pos < 0 { pos = Store.shared.progress[i.progressSlug].flatMap { $0.pct < 95 ? $0.pos : nil } ?? 0 }
        play(url: i.src, title: i.mediaTitle, poster: i.poster, start: pos)
        if hasCc { Task { await loadVTT(i.vtt) } }
    }

    private func play(url: String, title: String, poster: String, start: Double) {
        guard let u = URL(string: url) else { error = "Ungültige Adresse."; return }
        teardownObservers()
        let item = AVPlayerItem(url: u)
        item.preferredForwardBufferDuration = 30
        // Kontrollzentrum/Sperrbildschirm: nur Titel + Poster, nie FilmFrei24
        var np: [String: Any] = [MPMediaItemPropertyTitle: title]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = np
        if !poster.isEmpty, let pu = URL(string: poster) {
            Task {
                if let r = try? await URLSession.shared.data(from: pu), let img = UIImage(data: r.0) {
                    np[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                    nowPlayingBase = np; updateNowPlaying()
                }
            }
        }
        nowPlayingBase = np
        if let p = player { p.replaceCurrentItem(with: item) } else { player = AVPlayer(playerItem: item) }
        guard let p = player else { return }
        statusObs = item.observe(\.status) { [weak self] it, _ in
            Task { @MainActor in
                guard let self else { return }
                if it.status == .readyToPlay { self.loading = false }
                if it.status == .failed {
                    self.loading = false
                    self.error = "Das Video konnte nicht geladen werden. " + (it.error?.localizedDescription ?? "")
                }
            }
        }
        rateObs = p.observe(\.timeControlStatus) { [weak self] pl, _ in
            Task { @MainActor in self?.statusChanged(pl.timeControlStatus) }
        }
        if start > 5 { p.seek(to: CMTime(seconds: start, preferredTimescale: 600)) }
        obs = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor in self?.tick(t.seconds) }
        }
        endObs = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.ended() }
        }
        p.play()
    }

    private var nowPlayingBase: [String: Any] = [:]
    private func updateNowPlaying() {
        var d = nowPlayingBase
        d[MPMediaItemPropertyPlaybackDuration] = dur
        d[MPNowPlayingInfoPropertyElapsedPlaybackTime] = pos
        d[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = d
    }

    private var remoteSet = false
    private func setupRemoteCommands() {
        guard !remoteSet else { return }
        remoteSet = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.player?.play() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.player?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        c.skipForwardCommand.preferredIntervals = [10]; c.skipBackwardCommand.preferredIntervals = [10]
        c.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.seekBy(10) }; return .success }
        c.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.seekBy(-10) }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent { Task { @MainActor in self?.seekTo(e.positionTime) } }
            return .success
        }
    }

    private func statusChanged(_ s: AVPlayer.TimeControlStatus) {
        let was = playing
        playing = s == .playing
        if s == .waitingToPlayAtSpecifiedRate { loading = true } else if s == .playing { loading = false }
        if was != playing {
            if !playing { save(force: true) }
            // wie Web: nach 5 s Pause Logo/Titel/Beschreibung
            pauseTask?.cancel(); pausedLong = false
            if s == .paused && error == nil {
                pauseTask = Task { try? await Task.sleep(nanoseconds: 5_000_000_000); if !Task.isCancelled && !self.playing { self.pausedLong = true } }
            }
            lastInput = Date(); updateNowPlaying()
        }
    }

    private func tick(_ t: Double) {
        guard t.isFinite else { return }
        pos = t
        if let it = player?.currentItem {
            let d = it.duration.seconds
            if d.isFinite && d > 0 { dur = d }
            if let r = it.loadedTimeRanges.first?.timeRangeValue { buffered = (r.start + r.duration).seconds }
        }
        // Forced-Untertitel
        let c = ccOn ? (cues.first { t >= $0.0 && t <= $0.1 }?.2 ?? "") : ""
        if c != cue { cue = c }
        // Steuerung nach 3 s ausblenden (Fernbedienung 5 s), nicht bei Pause/Spulen
        if visible && playing && scrub == nil && Date().timeIntervalSince(lastInput) > (keyMode ? 5 : 3) {
            visible = false
            if focus != .skip && focus != .nextGo { focus = .play }
        }
        guard let i = info else { return }
        // Rückblick vor Intro (wie Website): Knopf nur im erkannten Abschnitt, springt an sein Ende
        let wasSkip = showSkip
        if let r = i.recap, t >= r.0, t < r.1 - 1 { showSkip = true; skipLabel = "Rückblick überspringen"; skipTo = r.1 }
        else if let iv = i.intro, t >= iv.0, t < iv.1 - 1 { showSkip = true; skipLabel = "Intro überspringen"; skipTo = iv.1 }
        else { showSkip = false }
        // Knopf erscheint -> Fokus darauf, OK drückt ihn (nicht Pause)
        if showSkip && !wasSkip && (!visible || focus == .play) { focus = .skip }
        if !showSkip && focus == .skip { focus = .play }
        if i.next != nil, dur > 120, countdown < 0 {
            let creditsAt = i.credits ?? (dur - 25)
            let inCredits = t >= creditsAt
            if inCredits && !showNext && !nextDismissed { showNext = true; if !visible || focus == .play || focus == .skip { focus = .nextGo } }
            if !inCredits { nextDismissed = false; if showNext { showNext = false; if focus == .nextGo { focus = .play } } }
        }
        if Date().timeIntervalSince(lastSave) > 10 { save(force: false); updateNowPlaying() }
    }

    /// Ende: wie Web Karte + 10 s Countdown, dann nächste Folge; ohne nächste Folge schließen.
    private func ended() {
        save(force: true)
        guard info?.next != nil else { onClose?(); return }
        showNext = true; showSkip = false; focus = .nextGo; countdown = 10
        nextTimer?.invalidate()
        nextTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] tm in
            Task { @MainActor in
                guard let self else { tm.invalidate(); return }
                self.countdown -= 1
                if self.countdown <= 0 { tm.invalidate(); self.playNext() }
            }
        }
    }

    // ── Bedienung ──
    func touched() { keyMode = false; lastInput = Date() }
    private func touchedKey(_ k: Bool) { keyMode = k; lastInput = Date() }
    private func show(_ f: PF? = nil) { visible = true; if let f { focus = f }; lastInput = Date() }

    func toggle() {
        guard let p = player else { return }
        if countdown >= 0 { return }
        if p.timeControlStatus == .paused { p.play() } else { p.pause() }
        lastInput = Date()
    }

    func seekTo(_ s: Double) {
        guard let p = player else { return }
        let t = min(max(0, s), max(0, dur - 0.5))
        p.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        pos = t; scrub = nil; lastInput = Date(); updateNowPlaying()
    }

    func seekBy(_ d: Double) { seekTo((player?.currentTime().seconds ?? pos) + d) }

    /// Fernbedienung: Ziel sammeln, nach kurzer Ruhe springen
    private func scrubBy(_ d: Double) {
        guard dur > 0 else { return }
        scrub = min(max(0, (scrub ?? pos) + d), dur - 0.5)
        lastInput = Date()
        scrubTask?.cancel()
        scrubTask = Task { try? await Task.sleep(nanoseconds: 650_000_000); if !Task.isCancelled, let s = self.scrub { self.seekTo(s) } }
    }

    func skipIntro() {
        guard skipTo > 0 else { return }
        seekTo(skipTo); showSkip = false
        if focus == .skip { focus = .play }
    }

    func toggleCc() { ccOn.toggle(); lastInput = Date() }

    func playNext() {
        guard let i = info, let n = i.next, !going else { return }
        going = true
        save(force: true); nextTimer?.invalidate(); countdown = -1
        Task { await load(type: "s", id: i.id, season: n.season, ep: n.ep, start: 0); going = false }
    }

    enum Key { case ok, playPause, back, left, right, up, down }

    private func topRow() -> [PF] { [.rep] + (hasCc ? [.cc] : []) + [.close] }
    private func bottomRow() -> [PF] { [.seek] + (info?.next != nil && !showNext ? [.next] : []) }
    private func overlay() -> PF? { showNext && info?.next != nil ? .nextGo : (showSkip ? .skip : nil) }

    private func activate(_ f: PF) {
        switch f {
        case .rep: player?.pause(); onReportFromRemote?()
        case .cc: toggleCc()
        case .air: break
        case .close: onClose?()
        case .rw: seekBy(-10)
        case .play: toggle()
        case .ff: seekBy(10)
        case .seek: if let s = scrub { seekTo(s) } else { toggle() }
        case .next, .nextGo: playNext()
        case .skip: skipIntro()
        }
    }
    var onReportFromRemote: (() -> Void)?

    private func move(_ k: Key) {
        let mid: [PF] = [.rw, .play, .ff]
        let row = topRow().contains(focus) ? topRow() : mid.contains(focus) ? mid : bottomRow().contains(focus) ? bottomRow() : [focus]
        switch k {
        case .left, .right:
            if let i = row.firstIndex(of: focus) {
                let j = i + (k == .right ? 1 : -1)
                if row.indices.contains(j) { focus = row[j] }
            }
        case .up:
            if topRow().contains(focus) { break }
            if mid.contains(focus) { focus = topRow().last ?? .close }
            else if focus == .skip || focus == .nextGo { focus = .play }
            else { focus = overlay() ?? .play }
        case .down:
            if topRow().contains(focus) { focus = .play }
            else if mid.contains(focus) { focus = overlay() ?? .seek }
            else if focus == .skip || focus == .nextGo { focus = .seek }
        default: break
        }
    }

    /// Fernbedienung (Apple TV). OK drückt immer den markierten Knopf; ausgeblendet: OK = Skip/Nächste Folge, sonst Pause.
    func press(_ k: Key, repeatCount: Int) {
        touchedKey(true)
        let step: Double = repeatCount > 16 ? 60 : (repeatCount > 4 ? 30 : 10)
        switch k {
        case .playPause: toggle(); show()
        case .back:
            if scrub != nil { scrubTask?.cancel(); scrub = nil }
            else if visible { visible = false; if let o = overlay() { focus = o } }
            else if showNext && countdown < 0 { showNext = false; nextDismissed = true; focus = .play }
            else { onClose?() }
        case .ok:
            if !visible {
                if let o = overlay(), focus == o || focus == .play { activate(o) } else { toggle(); show(.play) }
            } else { activate(focus) }
        case .left, .right:
            let d = k == .right ? step : -step
            if !visible { show(.seek); scrubBy(d) }
            else if focus == .seek { scrubBy(d) }
            else if repeatCount == 0 { move(k) }
        case .up, .down:
            if !visible { show(overlay() ?? .play) } else { move(k) }
        }
    }

    func save(force: Bool) {
        guard let i = info, let p = player, let it = p.currentItem else { return }
        let pos = p.currentTime().seconds, dur = it.duration.seconds
        guard pos.isFinite, dur.isFinite, dur > 0, pos >= 5 else { return }
        lastSave = Date()
        Store.shared.saveProgress(slug: i.progressSlug, pos: pos, dur: dur, seriesId: i.type == "s" ? i.id : nil, season: i.season, ep: i.ep)
    }

    func stop() {
        save(force: true)
        nextTimer?.invalidate(); scrubTask?.cancel(); pauseTask?.cancel()
        teardownObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        // Kontrollzentrum leeren: nach dem Schließen steht dort nichts mehr (weder Titel noch Seitenname)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        let c = MPRemoteCommandCenter.shared()
        for cmd in [c.playCommand, c.pauseCommand, c.togglePlayPauseCommand, c.skipForwardCommand, c.skipBackwardCommand, c.changePlaybackPositionCommand] as [MPRemoteCommand] {
            cmd.removeTarget(nil)
        }
        remoteSet = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func teardownObservers() {
        if let obs, let p = player { p.removeTimeObserver(obs) }
        obs = nil
        if let endObs { NotificationCenter.default.removeObserver(endObs) }
        endObs = nil
        statusObs = nil
        rateObs = nil
    }

    // MARK: VTT (einfacher Parser für die deutschen Forced-Untertitel)

    private func loadVTT(_ url: String) async {
        guard let u = URL(string: url), let r = try? await URLSession.shared.data(from: u), let s = String(data: r.0, encoding: .utf8) else { return }
        func sec(_ x: String) -> Double {
            let p = x.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":").compactMap { Double($0) }
            return p.reversed().enumerated().reduce(0) { $0 + $1.element * pow(60, Double($1.offset)) }
        }
        var out: [(Double, Double, String)] = []
        for block in s.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n").map(String.init)
            guard let ti = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[ti].components(separatedBy: "-->")
            guard parts.count == 2 else { continue }
            let end = parts[1].split(separator: " ").first.map(String.init) ?? parts[1]
            let text = lines[(ti + 1)...].joined(separator: "\n").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            if !text.isEmpty { out.append((sec(parts[0]), sec(end), text)) }
        }
        cues = out
    }
}
