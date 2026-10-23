import SwiftUI
import AVKit
import MediaPlayer

// Eigener Player wie Prime Video (2026-10-23, User-Screenshots) = gleich wie Website (beta/index.php .plr).
// Bild über AVPlayerLayer (Hardware-Dekodierung durch AVFoundation), Steuerung selbst gezeichnet.
// Apple TV: eigenes Fokus-Modell (PF) – OK/Klick drückt immer den markierten Knopf; erscheint
// „Intro überspringen“ oder „Nächste Folge“, bekommt dieser Knopf den Fokus (wie Netflix/Prime).

enum PF { case close, cc, spd, set, rw, play, ff, seek, next, skip, nextGo }

enum PSheet { case none, main, ccau, speed, subs, audio }

/// Eine Zeile im Menü-Blatt; id = Aktion (subs, audio, speed, report, cc:0/1, au:N, sp:X)
struct SItem: Identifiable { let id: String; var icon: String? = nil; let label: String; var value = ""; var chevron = false; var sel = false; var dis = false; var group = 0 }

struct PlayerView: View {
    let req: PlayRequest
    @StateObject private var m = PlayerModel()
    @Environment(\.dismiss) var dismiss
    @State private var report = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let p = m.player { VideoSurface(player: p, model: m).ignoresSafeArea() }
            #if os(tvOS)
            if m.error == nil && !report { RemoteCatcher(m: m).ignoresSafeArea() }
            #endif
            // 2026-10-22: Oberfläche bleibt im sicheren Bereich (Dynamic Island, Statusleiste, Ecken, TV-Overscan)
            GeometryReader { geo in
                let L = PLayout(w: geo.size.width, h: geo.size.height)
                ZStack {
                    if !m.cue.isEmpty {
                        VStack { Spacer()
                            Text(m.cue).font(.inter(L.cueFont, .medium)).foregroundColor(.white).multilineTextAlignment(.center)
                                .padding(.horizontal, 10).padding(.vertical, 4).background(Color.black.opacity(0.6))
                                .padding(.bottom, m.visible ? L.cueUp : L.edge)
                        }.frame(maxWidth: .infinity).allowsHitTesting(false)
                    }
                    PlayerOverlay(m: m, L: L, onReport: { m.player?.pause(); report = true })
                    if let e = m.error {
                        VStack(spacing: 16) {
                            Text("Wiedergabe nicht möglich").font(.inter(22, .bold)).foregroundColor(.white)
                            Text(e).font(.inter(15)).foregroundColor(Color(hex: 0xCFD3D8)).multilineTextAlignment(.center).frame(maxWidth: min(520 * FF.scale, L.w - 32))
                            HStack(spacing: 10) {
                                GreyButton(label: "Problem melden") { report = true }
                                GreyButton(label: "Schließen", white: true) { close() }
                            }
                        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.9).ignoresSafeArea())
                    }
                }
            }
        }
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
        .task { m.onClose = { close() }; m.onReportFromRemote = { report = true }; await m.start(req) }
        .onAppear { Orientation.landscape(true); StatusBar.hidden(true) }
        .onDisappear { m.stop(); Orientation.landscape(false); StatusBar.hidden(false) }
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
        // 2026-10-22: requestGeometryUpdate allein drehte oft nicht (iPhone blieb hochkant) → Ausrichtung über AppDelegate sperren
        AppDelegate.orientationLock = on ? .landscape : .allButUpsideDown
        for w in scene.windows {
            var vc = w.rootViewController
            while let c = vc {
                c.setNeedsUpdateOfSupportedInterfaceOrientations()
                vc = c.presentedViewController
            }
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: on ? .landscape : .portrait)) { _ in }
        #endif
    }
}

/// UIViewControllerBasedStatusBarAppearance = false (project.yml) → .statusBarHidden() von SwiftUI greift nicht,
/// deshalb Statusleiste (Uhr/Akku) im Player direkt über UIApplication ausblenden.
enum StatusBar {
    static func hidden(_ on: Bool) {
        #if os(iOS)
        let app = UIApplication.shared
        if app.responds(to: Selector(("setStatusBarHidden:"))) { app.setValue(on, forKey: "statusBarHidden") }
        #endif
    }
}

/// Maße nach echter Bildschirmgröße; Handy = kleinere Maße, nichts außerhalb des sicheren Bereichs.
/// tvOS: alles × FF.scale (Schriften skaliert .inter selbst), Ränder kommen aus dem Overscan-Sicherheitsbereich.
struct PLayout {
    let w: CGFloat, h: CGFloat
    let k = FF.scale
    #if os(tvOS)
    let tv = true
    #else
    let tv = false
    #endif
    var portrait: Bool { h > w }
    /// Handy (quer oder hochkant)
    var phone: Bool { !tv && min(w, h) < 500 }
    var edge: CGFloat { tv ? 0 : (phone ? 16 : max(28, w * 0.045)) }
    var topBtn: CGFloat { tv ? 52 * k : (phone ? 44 : 48) }
    var topIcon: CGFloat { tv ? 28 * k : (phone ? 24 : 26) }
    var topGap: CGFloat { tv ? 14 * k : (phone ? min(14, w * 0.02) : 18) }
    var spdFont: CGFloat { tv ? 22 : (phone ? 21 : 23) }
    var titleFont: CGFloat { tv ? 26 : (phone ? 20 : 26) }
    var subFont: CGFloat { tv ? 16 : (phone ? 13 : 15) }
    var logoH: CGFloat { tv ? 64 * k : (phone ? 40 : 56) }
    var logoW: CGFloat { tv ? 300 * k : (phone ? w * (portrait ? 0.48 : 0.3) : min(280, w * 0.26)) }
    var playSize: CGFloat { tv ? 80 * k : (phone ? 64 : 84) }
    var seekSize: CGFloat { phone ? 40 : 46 }
    var midGap: CGFloat { phone ? min(56, w * 0.09) : 96 }
    var timeFont: CGFloat { tv ? 16 : (phone ? 13 : 15) }
    var btnFont: CGFloat { tv ? 17 : (phone ? 15 : 16) }
    var btnH: CGFloat { tv ? 48 * k : (phone ? 42 : 48) }
    var cueFont: CGFloat { tv ? 24 : (phone ? 17 : 22) }
    var cueUp: CGFloat { tv ? 140 * k : (portrait ? 130 : (phone ? 104 : 130)) }
    /// Abstand der unteren Zeile (Pille / Intro-Knopf) vom Rand
    var bottomPad: CGFloat { tv ? 0 : (phone ? 6 : 16) }
    var fskFont: CGFloat { tv ? 22 : (phone ? 16 : 20) }
    var fskTFont: CGFloat { tv ? 18 : (phone ? 14 : 17) }
}

let SPEEDS: [Float] = [0.75, 1, 1.25, 1.5, 2]
func spdTxt(_ r: Float) -> String { r == 1 ? "1x" : (r == r.rounded() ? String(format: "%.0fx", r) : String(format: "%gx", r)) }

// MARK: - Oberfläche (wie Prime Video, User-Screenshots 2026-10-23; gleich wie Website beta/index.php .plr)

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
    let L: PLayout
    let onReport: () -> Void
    @State private var logoFailed = ""
    private var k: CGFloat { L.k }
    private var key: Bool { m.keyMode }

    var body: some View {
        ZStack {
            // Prime: Tippen blendet nur die Leiste ein/aus; Doppeltipp links/rechts = 10 s (iPhone/iPad)
            #if os(iOS)
            Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                .gesture(SpatialTapGesture(count: 2).onEnded { v in m.touched(); m.seekBy(v.location.x < L.w / 2 ? -10 : 10) }
                    .exclusively(before: TapGesture().onEnded { m.tapScreen() }))
            #endif

            // Pause-Infos (nur wenn Steuerung weg ist, nie über den Knöpfen)
            if m.pausedLong && !m.visible, let i = m.info { pauseInfo(i).transition(.opacity) }

            controls.opacity(m.visible && !m.rating ? 1 : 0).allowsHitTesting(m.visible && !m.rating)

            if m.loading && m.error == nil {
                ProgressView().tint(.white).scaleEffect(1.6 * k).allowsHitTesting(false)
            }

            // Nächste Folge / Intro überspringen: in der Pillen-Zeile unten rechts, auch bei ausgeblendeter Steuerung
            VStack { Spacer(); HStack { Spacer()
                if m.showNext && m.info?.next != nil { nextButton }
                else if m.showSkip && !m.rating { skipButton }
            } }
            .padding(.trailing, L.edge).padding(.bottom, L.bottomPad)

            if m.rating, let i = m.info, !i.fskR.isEmpty { ratingView(i).transition(.opacity) }

            if m.sheet != .none { PlayerSheet(m: m, L: L).transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.25), value: m.visible)
        .animation(.easeInOut(duration: 0.4), value: m.pausedLong)
        .animation(.easeInOut(duration: 0.5), value: m.rating)
        .animation(.easeOut(duration: 0.2), value: m.sheet)
    }

    func pauseInfo(_ i: PlayInfo) -> some View {
        let maxW = min((L.tv ? 620 : 520) * k, L.w * (L.portrait ? 0.92 : 0.55))
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(stops: [.init(color: .black.opacity(0.85), location: 0), .init(color: .black.opacity(0.3), location: 0.6), .init(color: .clear, location: 1)],
                           startPoint: L.portrait ? .bottom : .leading, endPoint: L.portrait ? .top : .trailing).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                if !i.logo.isEmpty {
                    Img(url: i.logo, mode: .fit, align: .bottomLeading).frame(width: min(360 * k, maxW), height: (L.phone ? 90 : 140) * k).padding(.bottom, 14 * k)
                } else {
                    Text(i.title).font(.inter(L.phone ? 26 : 34, .heavy)).foregroundColor(.white).lineLimit(2).minimumScaleFactor(0.7).padding(.bottom, 10 * k)
                }
                if i.type == "s" { Text(i.sub).font(.inter(L.phone ? 15 : 18, .bold)).foregroundColor(.white).lineLimit(1).padding(.bottom, 8 * k) }
                if !i.desc.isEmpty {
                    Text(i.desc).font(.inter(L.phone ? 14 : 16)).foregroundColor(Color(hex: 0xE7EAED)).lineLimit(L.phone ? 3 : 4).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: maxW, alignment: .leading)
                .padding(.leading, L.tv ? 0 : L.edge + 12).padding(.bottom, L.tv ? 20 * k : L.edge + 24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).allowsHitTesting(false)
    }

    /// Altersfreigabe beim Start (Prime: Kasten oben links + Hinweise), Steuerung so lange aus
    func ratingView(_ i: PlayInfo) -> some View {
        let box = Text("ALTERSFREIGABE " + i.fskR).font(.inter(L.fskFont, .semibold)).lineLimit(1).fixedSize()
            .padding(.horizontal, (L.phone ? 10 : 14) * k).padding(.vertical, (L.phone ? 6 : 9) * k)
            .background(RoundedRectangle(cornerRadius: 12 * k).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 12 * k).stroke(Color.white.opacity(0.55), lineWidth: 2 * k))
        let note = Text(i.fskD).font(.inter(L.fskTFont, .medium)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            .shadow(color: .black.opacity(0.8), radius: 3)
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if L.portrait {
                    VStack(alignment: .leading, spacing: 10 * k) { box; if !i.fskD.isEmpty { note } }
                } else {
                    HStack(spacing: (L.phone ? 14 : 24) * k) { box; if !i.fskD.isEmpty { note.frame(maxWidth: 720 * k, alignment: .leading) } }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }.foregroundColor(.white).padding(.horizontal, L.edge).padding(.top, L.tv ? 0 : 10).allowsHitTesting(false)
    }

    // ── Steuerung ──
    var controls: some View {
        ZStack {
            LinearGradient(stops: [.init(color: .black.opacity(0.7), location: 0), .init(color: .black.opacity(0.35), location: 0.22),
                                   .init(color: .black.opacity(0.3), location: 0.6), .init(color: .black.opacity(0.75), location: 1)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)

            // oben: ✕ links, rechts (AirPlay) · Untertitel · 1x · Zahnrad; darunter Logo bzw. Titel
            VStack(alignment: .leading, spacing: 0) {
                topBar
                titleBlock.padding(.top, (L.phone ? 4 : 12) * k)
                Spacer()
            }.padding(.horizontal, L.edge).padding(.top, L.tv ? 0 : (L.phone ? 4 : 12))

            // Mitte: 10 zurück · Play im dunklen Kreis · 10 vor; Fernseher nur Play/Pause (Spulen per Fernbedienung)
            HStack(spacing: L.midGap) {
                if !L.tv { midBtn(.rw) { WebIcon.rw.frame(width: L.seekSize, height: L.seekSize) } action: { m.seekBy(-10) } }
                midBtn(.play, circle: L.playSize) {
                    Group { if m.loading { Color.clear } else if m.playing { WebIcon.pause } else { WebIcon.play } }
                        .frame(width: L.playSize * 0.44, height: L.playSize * 0.44)
                } action: { m.toggle() }
                if !L.tv { midBtn(.ff) { WebIcon.ff.frame(width: L.seekSize, height: L.seekSize) } action: { m.seekBy(10) } }
            }

            // unten: dünne Leiste, Zeiten darunter, Pille rechts
            VStack(spacing: 0) {
                Spacer()
                let shown = m.scrub ?? m.pos
                SeekBar(m: m, shown: shown)
                HStack {
                    Text(ptime(shown)).monospacedDigit().lineLimit(1).fixedSize()
                    Spacer()
                    Text("-" + ptime(max(0, m.dur - shown))).monospacedDigit().lineLimit(1).fixedSize()
                }.font(.inter(L.timeFont, .medium)).padding(.top, 2 * k)
                HStack { Spacer()
                    if let n = m.info?.next, !m.showNext, !m.showSkip { nextPill(n) }
                }.frame(height: L.btnH).padding(.top, 6 * k)
            }.foregroundColor(.white)
                .padding(.horizontal, L.edge).padding(.bottom, L.bottomPad)
        }
    }

    var topBar: some View {
        HStack(spacing: L.topGap) {
            topBtn(.close, "Schließen") { WebIcon.x.frame(width: L.topIcon, height: L.topIcon) } action: { m.onClose?() }
                .padding(.leading, -10 * k)
            Spacer(minLength: 0)
            #if os(iOS)
            AirPlayButton().frame(width: L.topBtn, height: L.topBtn)
            #endif
            topBtn(.cc, "Untertitel und Audio") {
                Image(systemName: m.ccOn && m.hasCc ? "text.bubble.fill" : "text.bubble").font(.system(size: L.topIcon * 0.92, weight: .regular))
            } action: { m.openSheet(.ccau) }
            topBtn(.spd, "Geschwindigkeit", wide: true) { Text(spdTxt(m.speed)).font(.inter(L.spdFont)).lineLimit(1).fixedSize() } action: { m.openSheet(.speed) }
            topBtn(.set, "Einstellungen") { Image(systemName: "gearshape.fill").font(.system(size: L.topIcon * 0.95)) } action: { m.openSheet(.main) }
                .padding(.trailing, -10 * k)
        }.frame(height: L.topBtn)
    }

    /// Oben links Logo (wie Website #p-tlogo), Titeltext nur ohne Logo; Serien: „S1 F2 · Titel“ darunter.
    @ViewBuilder var titleBlock: some View {
        if let i = m.info {
            VStack(alignment: .leading, spacing: 8 * k) {
                if !i.logo.isEmpty && logoFailed != i.logo {
                    Img(url: i.logo, mode: .fit, align: .leading, onFail: { logoFailed = i.logo }).frame(width: L.logoW, height: L.logoH)
                } else {
                    Text(i.title).font(.inter(L.titleFont, .heavy)).lineLimit(2).minimumScaleFactor(0.8)
                }
                if i.type == "s" && !i.sub.isEmpty {
                    Text(i.sub).font(.inter(L.subFont, .semibold)).foregroundColor(Color(hex: 0xE2E5E8)).lineLimit(1)
                }
            }.foregroundColor(.white).frame(maxWidth: L.portrait ? L.w * 0.9 : L.w * 0.46, alignment: .leading).allowsHitTesting(false)
        }
    }

    /// Dunkle Pille unten rechts (wie Prime „X-Ray“): hier „Nächste Folge“.
    func nextPill(_ n: (season: Int, ep: Int, title: String, thumb: String)) -> some View {
        let f = key && m.focus == .next
        return HStack(spacing: 8 * k) {
            Text("Nächste Folge").font(.inter(L.btnFont, .semibold)).lineLimit(1).fixedSize()
            WebIcon.next.frame(width: 18 * k, height: 18 * k)
        }.foregroundColor(f ? FF.dark : .white)
            .padding(.horizontal, (L.phone ? 18 : 24) * k).frame(height: L.btnH)
            .background(Capsule().fill(f ? Color.white : Color(hex: 0x34363B, alpha: 0.92)))
            .scaleEffect(f ? 1.06 : 1).tap { m.playNext() }.accessibilityLabel("Nächste Folge S\(n.season) F\(n.ep)")
    }

    /// Knöpfe oben ohne Kreis; Fokus = weißer Kreis/Pille.
    func topBtn<I: View>(_ f: PF, _ label: String, wide: Bool = false, @ViewBuilder icon: () -> I, action: @escaping () -> Void) -> some View {
        let on = key && m.focus == f
        return icon()
            .foregroundColor(on ? FF.dark : .white)
            .padding(.horizontal, wide ? 8 * k : 0)
            .frame(minWidth: L.topBtn, minHeight: L.topBtn, maxHeight: L.topBtn)
            .background(Capsule().fill(on ? Color.white : Color.clear))
            .scaleEffect(on ? 1.08 : 1).animation(.easeOut(duration: 0.15), value: on)
            .tap(action).accessibilityLabel(label)
    }

    /// Mitte: Play im dunklen Kreis (Prime), 10-s-Knöpfe frei; Fokus = weißer Rand + größer.
    func midBtn<I: View>(_ f: PF, circle: CGFloat? = nil, @ViewBuilder icon: () -> I, action: @escaping () -> Void) -> some View {
        let on = key && m.focus == f
        return Group {
            if let c = circle {
                icon().frame(width: c, height: c).background(Circle().fill(Color(hex: on ? 0x3A3D43 : 0x26282D, alpha: on ? 0.95 : 0.82)))
            } else {
                icon().padding(8 * k).background(Circle().fill(Color.white.opacity(on ? 0.2 : 0)))
            }
        }.foregroundColor(.white)
            .overlay(Circle().stroke(Color.white, lineWidth: on ? 3 * k : 0))
            .scaleEffect(on ? 1.12 : 1).animation(.easeOut(duration: 0.15), value: on)
            .tap(action)
    }

    /// Weiße Pille unten rechts (Intro/Rückblick überspringen, Nächste Folge) – Text nie umbrechen.
    func whiteButton(_ label: String, icon: some View, focused: Bool, progress: Double?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10 * k) {
            Text(label).font(.inter(L.btnFont, .bold)).lineLimit(1).fixedSize()
            icon.frame(width: 18 * k, height: 18 * k)
        }.foregroundColor(Color(hex: 0x0F1114)).padding(.horizontal, 22 * k).frame(height: L.btnH)
            .background(
                ZStack(alignment: .leading) {
                    Color(hex: 0xF0F1F3).opacity(focused ? 1 : 0.95)
                    if let p = progress { GeometryReader { g in Color(hex: 0xCFD6DE).frame(width: g.size.width * p) }.animation(.linear(duration: 1), value: p) }
                }.clipShape(Capsule())
            )
            .overlay(Capsule().stroke(FF.blue, lineWidth: focused && key ? 3 * k : 0))
            .shadow(color: .black.opacity(0.45), radius: 12 * k, y: 6 * k)
            .scaleEffect(focused && key ? 1.07 : 1).animation(.easeOut(duration: 0.15), value: focused)
            .fixedSize()
            .tap(action)
    }

    var skipButton: some View {
        whiteButton(m.skipLabel, icon: WebIcon.skip, focused: m.focus == .skip && (key || !m.visible), progress: nil) { m.skipIntro() }
    }

    /// 2026-10-22 User: nur Knopf „Nächste Folge“, ohne Infos/Bild zur Folge; Countdown am Ende als Füllung.
    var nextButton: some View {
        let label = m.countdown >= 0 ? "Nächste Folge in \(m.countdown)" : "Nächste Folge"
        let prog: Double? = m.countdown >= 0 ? Double(5 - m.countdown) / 5 : nil
        return whiteButton(label, icon: WebIcon.next, focused: m.focus == .nextGo && (key || !m.visible), progress: prog) { m.playNext() }
    }
}

/// Menü als Blatt von unten (Prime): Griff, Titel, graue Gruppen; Geschwindigkeit als 5 Kacheln.
/// Apple TV: Fokus über m.sheetFocus (Fernbedienung in PlayerModel.press), iPhone/iPad: Antippen.
struct PlayerSheet: View {
    @ObservedObject var m: PlayerModel
    let L: PLayout
    private var k: CGFloat { L.k }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.62).ignoresSafeArea().tap { m.closeSheet() }
            VStack(spacing: 0) {
                Capsule().fill(Color(hex: 0x55585E)).frame(width: 44 * k, height: 5 * k).padding(.top, 12 * k).padding(.bottom, 14 * k).tap { m.closeSheet() }
                ViewThatFits(in: .vertical) {
                    content
                    ScrollView(showsIndicators: false) { content }
                }
            }
            .padding(.horizontal, 16 * k)
            .frame(maxWidth: min((L.tv ? 640 : 560) * k, L.w))
            .background(RoundedRectangle(cornerRadius: 26 * k).fill(Color(hex: 0x1B1C20)).padding(.bottom, -60 * k).ignoresSafeArea(edges: .bottom))
            .frame(maxHeight: L.h - 24 * k, alignment: .bottom)
        }.foregroundColor(.white)
    }

    @ViewBuilder var content: some View {
        let items = m.sheetItems()
        VStack(spacing: 0) {
            if let t = m.sheetTitle {
                ZStack {
                    Text(t).font(.inter(L.phone ? 20 : 24, .heavy)).lineLimit(1).padding(.horizontal, 44 * k)
                    if m.sheetBack {
                        HStack {
                            Image(systemName: "chevron.left").font(.system(size: 20 * k, weight: .semibold)).frame(width: 40 * k, height: 40 * k)
                                .tap { m.openSheet(.main) }
                            Spacer()
                        }
                    }
                }.padding(.top, 2 * k).padding(.bottom, 18 * k)
            }
            if m.sheet == .speed {
                HStack(spacing: 12 * k) {
                    ForEach(Array(items.enumerated()), id: \.1.id) { n, it in tile(it, focused: m.keyMode && m.sheetFocus == n) }
                }.padding(.bottom, 18 * k)
            } else {
                let groups = Array(Set(items.map(\.group))).sorted()
                ForEach(groups, id: \.self) { g in
                    VStack(alignment: .leading, spacing: 0) {
                        if let lbl = m.sheetGroupLabels[g] {
                            Text(lbl.uppercased()).font(.inter(12, .semibold)).foregroundColor(Color(hex: 0x9A9EA5)).padding(.leading, 20 * k).padding(.top, 8 * k).padding(.bottom, 2 * k)
                        }
                        ForEach(Array(items.enumerated()).filter { $0.1.group == g }, id: \.1.id) { n, it in row(it, focused: m.keyMode && m.sheetFocus == n) }
                    }.padding(.vertical, 6 * k).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16 * k).fill(Color(hex: 0x33353B))).padding(.bottom, 14 * k)
                }
            }
        }.padding(.bottom, 8 * k)
    }

    func row(_ it: SItem, focused f: Bool) -> some View {
        let fs: CGFloat = L.tv ? 21 : (L.phone ? 17 : 19)
        return HStack(spacing: 16 * k) {
            if let ic = it.icon { Image(systemName: ic).font(.system(size: 22 * k)).frame(width: 30 * k) }
            Text(it.label).font(.inter(fs)).lineLimit(1).opacity(it.dis ? 0.6 : 1)
            Spacer(minLength: 8 * k)
            if !it.value.isEmpty { Text(it.value).font(.inter(fs * 0.95)).foregroundColor(f ? Color(hex: 0x4A4E55) : Color(hex: 0xA3A7AD)).lineLimit(1).fixedSize() }
            if it.chevron { Image(systemName: "chevron.right").font(.system(size: 17 * k, weight: .semibold)) }
            else if it.sel { Image(systemName: "checkmark").font(.system(size: 17 * k, weight: .semibold)) }
        }.foregroundColor(f ? FF.dark : .white)
            .padding(.horizontal, 14 * k).frame(minHeight: (L.tv ? 58 : 50) * k)
            .background(RoundedRectangle(cornerRadius: 12 * k).fill(f ? Color.white : Color.clear))
            .padding(.horizontal, 6 * k)
            .tap { if !it.dis { m.sheetAct(it.id) } }
    }

    func tile(_ it: SItem, focused f: Bool) -> some View {
        let fs: CGFloat = L.tv ? 21 : (L.phone ? 17 : 19)
        return VStack(spacing: 6 * k) {
            Text(it.label).font(.inter(fs)).lineLimit(1).fixedSize()
            if it.label == "1x" { Text("Normal").font(.inter(fs * 0.85)).lineLimit(1).fixedSize() }
        }.foregroundColor(f ? FF.dark : .white)
            .frame(maxWidth: 112 * k).frame(minWidth: 56 * k).aspectRatio(1 / 1.1, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: 14 * k).fill(f ? Color.white : Color(hex: it.sel ? 0x3C3E44 : 0x34363B)))
            .overlay(RoundedRectangle(cornerRadius: 14 * k).stroke(Color(hex: 0x8B8E94), lineWidth: it.sel && !f ? 2 * k : 0))
            .tap { m.sheetAct(it.id) }
    }
}

/// Zeiten wie Prime: 00:07 / 01:50:37
func ptime(_ t: Double) -> String {
    let s = Int(max(0, t.isFinite ? t : 0))
    return s >= 3600 ? String(format: "%02d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
}

/// .seek: dünne Spur (5) + weißer Punkt; Fokus/Ziehen größer + Zeit-Blase.
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
            let th = (big ? 8 : 5) * k, kn = (big ? 18 : 14) * k
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.28)).frame(height: th)
                Capsule().fill(Color.white.opacity(0.22)).frame(width: g.size.width * CGFloat(min(1, m.buffered / d)), height: th)
                Capsule().fill(Color.white).frame(width: x, height: th)
                Circle().fill(Color.white).frame(width: kn, height: kn).shadow(color: .black.opacity(0.5), radius: 2).offset(x: x - kn / 2)
                if big && m.scrub != nil {
                    Text(ptime(shown)).font(.inter(14, .semibold)).foregroundColor(.white).monospacedDigit()
                        .padding(.horizontal, 9 * k).padding(.vertical, 5 * k)
                        .background(RoundedRectangle(cornerRadius: 6 * k).fill(Color(hex: 0x19191F, alpha: 0.96)))
                        .fixedSize().position(x: min(max(x, 40 * k), g.size.width - 40 * k), y: -20 * k)
                }
            }.frame(height: g.size.height)
            #if os(iOS)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in drag = true; m.touched(); m.scrub = Double(min(max(0, v.location.x / g.size.width), 1)) * d }
                .onEnded { _ in drag = false; if let s = m.scrub { m.seekTo(s) } })
            #endif
        }.frame(height: 24 * k)
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
    /// -1 = kein Countdown; 5…0 ab Abspann (User 2026-10-22: nach ~5 s automatisch nächste Folge)
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
    // Prime-Menüs, Tempo, Tonspuren, Altersfreigabe (2026-10-23)
    @Published var sheet: PSheet = .none
    @Published var sheetFocus = 0
    @Published var speed: Float = 1
    @Published var audioOpts: [(name: String, on: Bool)] = []
    @Published var rating = false
    private var rated = false
    private var ratingUntil = Date.distantPast
    private var audioGroup: AVMediaSelectionGroup?
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
    private var uiTimer: Timer?

    func start(_ req: PlayRequest) async {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        setupRemoteCommands()
        uiTimer?.invalidate()
        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.uiTick() } }
        if let t = req.trailer {
            info = nil
            play(url: t.url, title: t.title, poster: "", start: 0)
            return
        }
        await load(type: req.type, id: req.itemId, season: req.season, ep: req.ep, start: req.start)
        // nur Simulator-Fotos (DebugScreen)
        let args = ProcessInfo.processInfo.arguments
        guard args.contains(where: { $0.hasPrefix("player-") }) else { return }
        for _ in 0..<60 where dur <= 0 || loading { try? await Task.sleep(nanoseconds: 500_000_000) }
        if args.contains("player-film") { debugHold = true; visible = true }
        if args.contains("player-menue") { debugHold = true; openSheet(.main) }
        if args.contains("player-tempo") { debugHold = true; openSheet(.speed) }
        if args.contains("player-ut") { debugHold = true; openSheet(.ccau) }
        if args.contains("player-fsk") { debugHold = true; rating = true; ratingUntil = .distantFuture }
        if args.contains("player-pause") { player?.pause() }
        if args.contains("player-ende"), let i = info { seekTo((i.credits ?? (dur - 25)) + 0.5) }
    }

    func load(type: String, id: String, season: Int, ep: Int, start: Double) async {
        loading = true; error = nil; showNext = false; showSkip = false; nextDismissed = false; cues = []; cue = ""
        stopCountdown(); visible = true; scrub = nil; pausedLong = false; focus = .play; touchedKey(false)
        sheet = .none; rated = false; rating = false; audioOpts = []; audioGroup = nil
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
                if it.status == .readyToPlay { self.loading = false; await self.loadAudio(it) }
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
            pausedLong = false
            if !playing { visible = true }
            lastInput = Date(); updateNowPlaying()
        }
    }

    private func tick(_ t: Double) {
        guard t.isFinite else { return }
        pos = t
        // Altersfreigabe einmal pro Titel beim ersten Abspielen (~6,5 s), Steuerung so lange aus
        if !rated, playing, sheet == .none, let i = info, !i.fskR.isEmpty {
            rated = true; rating = true; ratingUntil = Date().addingTimeInterval(6.5); visible = false
        }
        if let it = player?.currentItem {
            let d = it.duration.seconds
            if d.isFinite && d > 0 { dur = d }
            if let r = it.loadedTimeRanges.first?.timeRangeValue { buffered = (r.start + r.duration).seconds }
        }
        // Forced-Untertitel
        let c = ccOn ? (cues.first { t >= $0.0 && t <= $0.1 }?.2 ?? "") : ""
        if c != cue { cue = c }
        guard let i = info else { return }
        // Rückblick vor Intro (wie Website): Knopf nur im erkannten Abschnitt, springt an sein Ende
        let wasSkip = showSkip
        if let r = i.recap, t >= r.0, t < r.1 - 1 { showSkip = true; skipLabel = "Rückblick überspringen"; skipTo = r.1 }
        else if let iv = i.intro, t >= iv.0, t < iv.1 - 1 { showSkip = true; skipLabel = "Intro überspringen"; skipTo = iv.1 }
        else { showSkip = false }
        // Knopf erscheint -> Fokus darauf, OK drückt ihn (nicht Pause)
        if showSkip && !wasSkip && (!visible || focus == .play) { focus = .skip }
        if !showSkip && focus == .skip { focus = .play }
        if i.next != nil, dur > 120 {
            let creditsAt = i.credits ?? (dur - 25)
            let inCredits = t >= creditsAt
            if inCredits && !showNext && !nextDismissed {
                showNext = true; if !visible || focus == .play || focus == .skip { focus = .nextGo }
                if playing { startCountdown() }
            }
            if !inCredits {
                nextDismissed = false
                if showNext { showNext = false; stopCountdown(); if focus == .nextGo { focus = .play } }
            }
        }
        if Date().timeIntervalSince(lastSave) > 10 { save(force: false); updateNowPlaying() }
    }

    /// Steuerung ein-/ausblenden + Pause-Infos (läuft auch bei Pause, der Zeit-Beobachter nicht).
    /// Läuft: nach 3 s (Fernbedienung 5 s) weg. Pause: nach 6 s ohne Eingabe Steuerung weg, Logo/Titel/Beschreibung da.
    private var debugHold = false
    private func uiTick() {
        if rating && Date() > ratingUntil { rating = false }
        if sheet != .none { lastInput = Date(); return }
        guard player != nil, !debugHold, error == nil, scrub == nil, !loading else { return }
        let idle = Date().timeIntervalSince(lastInput)
        if playing {
            if visible && idle > (keyMode ? 5 : 3) { hideControls() }
        } else if countdown < 0, info != nil, idle > 6, !pausedLong {
            hideControls(); pausedLong = true
        }
    }

    private func hideControls() {
        visible = false
        if focus != .skip && focus != .nextGo { focus = .play }
    }

    /// iPhone/iPad: Tipp aufs Bild
    func tapScreen() {
        touched()
        if pausedLong { pausedLong = false; visible = true } else { visible.toggle() }
    }

    func stopCountdown() { nextTimer?.invalidate(); nextTimer = nil; countdown = -1 }

    private func startCountdown() {
        guard countdown < 0, info?.next != nil else { return }
        countdown = 5
        nextTimer?.invalidate()
        nextTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] tm in
            Task { @MainActor in
                guard let self else { tm.invalidate(); return }
                self.countdown -= 1
                if self.countdown <= 0 { tm.invalidate(); self.playNext() }
            }
        }
    }

    /// Ende: Knopf „Nächste Folge“ + Countdown (falls nicht schon im Abspann gestartet); ohne nächste Folge schließen.
    private func ended() {
        save(force: true)
        guard info?.next != nil else { onClose?(); return }
        showNext = true; showSkip = false; focus = .nextGo; nextDismissed = false
        if countdown < 0 { startCountdown() }
    }

    // ── Bedienung ──
    func touched() { keyMode = false; lastInput = Date(); rating = false }
    private func touchedKey(_ k: Bool) { keyMode = k; lastInput = Date(); pausedLong = false; rating = false }
    private func show(_ f: PF? = nil) { visible = true; pausedLong = false; if let f { focus = f }; lastInput = Date() }

    func toggle() {
        guard let p = player else { return }
        // Pause während des Countdowns = nicht automatisch weiter
        if countdown >= 0 { stopCountdown(); if p.timeControlStatus != .paused { p.pause() }; lastInput = Date(); return }
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

    // ── Menü-Blatt (Prime) ──
    func openSheet(_ s: PSheet) {
        sheet = s; visible = true; pausedLong = false; lastInput = Date()
        let items = sheetItems()
        sheetFocus = items.firstIndex(where: { $0.sel && !$0.dis }) ?? items.firstIndex(where: { !$0.dis }) ?? 0
        if s == .main || s == .ccau { sheetFocus = items.firstIndex(where: { !$0.dis }) ?? 0 }
    }
    func closeSheet() { sheet = .none; lastInput = Date() }
    var sheetTitle: String? {
        switch sheet {
        case .main, .none: return nil
        case .ccau: return "Untertitel und Audio"
        case .speed: return "Geschwindigkeit"
        case .subs: return "Untertitel"
        case .audio: return "Audiosprache"
        }
    }
    var sheetBack: Bool { sheet == .subs || sheet == .audio }
    var sheetGroupLabels: [Int: String] { sheet == .ccau ? [0: "Untertitel", 1: "Audio"] : [:] }
    private var audioList: [(name: String, on: Bool)] { audioOpts.isEmpty ? [("Deutsch", true)] : audioOpts }

    func sheetItems() -> [SItem] {
        let cc = ccOn && hasCc
        let subs = [SItem(id: "cc:0", label: "Aus", sel: !cc)] + (hasCc ? [SItem(id: "cc:1", label: "Deutsch", sel: cc)] : [])
        let aud = audioList.enumerated().map { SItem(id: "au:\($0.offset)", label: $0.element.name, sel: $0.element.on, group: 1) }
        switch sheet {
        case .none: return []
        case .main:
            return [SItem(id: "subs", icon: "text.bubble", label: "Untertitel", value: cc ? "Deutsch" : "Aus", chevron: true),
                    SItem(id: "audio", icon: "waveform", label: "Audiosprache", value: audioList.first { $0.on }?.name ?? "Deutsch", chevron: true),
                    SItem(id: "speed", icon: "gauge.with.dots.needle.33percent", label: "Geschwindigkeit", value: speed == 1 ? "Normal" : spdTxt(speed), chevron: true, group: 1),
                    SItem(id: "report", icon: "flag", label: "Problem melden", chevron: true, group: 2)]
        case .subs: return subs + (hasCc ? [] : [SItem(id: "none", label: "Keine weiteren Untertitel", dis: true)])
        case .audio: return aud.map { SItem(id: $0.id, label: $0.label, sel: $0.sel) }
        case .ccau: return subs + aud
        case .speed: return SPEEDS.map { SItem(id: "sp:\($0)", label: spdTxt($0), sel: $0 == speed) }
        }
    }

    func sheetAct(_ id: String) {
        lastInput = Date()
        switch id {
        case "subs": openSheet(.subs)
        case "audio": openSheet(.audio)
        case "speed": openSheet(.speed)
        case "report": closeSheet(); player?.pause(); onReportFromRemote?()
        case "cc:0": ccOn = false
        case "cc:1": ccOn = true
        default:
            if id.hasPrefix("au:"), let n = Int(id.dropFirst(3)) { selectAudio(n) }
            if id.hasPrefix("sp:"), let r = Float(id.dropFirst(3)) { setSpeed(r); closeSheet() }
        }
    }

    func setSpeed(_ r: Float) {
        speed = r
        player?.defaultRate = r
        if playing { player?.rate = r }
    }

    /// Tonspuren (Name auf Deutsch aus der Sprache, sonst Anzeigename)
    private func loadAudio(_ item: AVPlayerItem) async {
        guard let g = try? await item.asset.loadMediaSelectionGroup(for: .audible), !g.options.isEmpty else { audioOpts = []; audioGroup = nil; return }
        audioGroup = g
        let sel = item.currentMediaSelection.selectedMediaOption(in: g)
        let de = Locale(identifier: "de_DE")
        var list: [(name: String, on: Bool)] = g.options.map { o in
            let n = o.locale?.language.languageCode.flatMap { de.localizedString(forLanguageCode: $0.identifier) } ?? o.displayName
            return (n.prefix(1).uppercased() + n.dropFirst(), o == sel)
        }
        if Set(list.map(\.name)).count < list.count { list = list.enumerated().map { ("\($0.element.name) \($0.offset + 1)", $0.element.on) } }
        if !list.contains(where: { $0.on }), !list.isEmpty { list[0].on = true }
        audioOpts = list
    }

    private func selectAudio(_ n: Int) {
        guard let g = audioGroup, let it = player?.currentItem, g.options.indices.contains(n) else { return }
        it.select(g.options[n], in: g)
        audioOpts = audioOpts.enumerated().map { ($0.element.name, $0.offset == n) }
    }

    func playNext() {
        guard let i = info, let n = i.next, !going else { return }
        going = true
        save(force: true); stopCountdown()
        Task { await load(type: "s", id: i.id, season: n.season, ep: n.ep, start: 0); going = false }
    }

    enum Key { case ok, playPause, back, left, right, up, down }

    private func topRow() -> [PF] { [.close, .cc, .spd, .set] }
    private func bottomRow() -> [PF] { [.seek] + (info?.next != nil && !showNext && !showSkip ? [.next] : []) }
    private func overlay() -> PF? { showNext && info?.next != nil ? .nextGo : (showSkip ? .skip : nil) }

    private func activate(_ f: PF) {
        switch f {
        case .cc: openSheet(.ccau)
        case .spd: openSheet(.speed)
        case .set: openSheet(.main)
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
        #if os(tvOS)
        let mid: [PF] = [.play]
        #else
        let mid: [PF] = [.rw, .play, .ff]
        #endif
        let row = topRow().contains(focus) ? topRow() : mid.contains(focus) ? mid : bottomRow().contains(focus) ? bottomRow() : [focus]
        switch k {
        case .left, .right:
            if let i = row.firstIndex(of: focus) {
                let j = i + (k == .right ? 1 : -1)
                if row.indices.contains(j) { focus = row[j] }
            }
        case .up:
            if topRow().contains(focus) { break }
            if mid.contains(focus) { focus = .cc }
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
        // Menü offen: hoch/runter (Tempo: links/rechts) wählt, OK übernimmt, Zurück = Ebene zurück bzw. zu
        if sheet != .none {
            let items = sheetItems()
            let ok = items.indices.filter { !items[$0].dis }
            let horiz = sheet == .speed
            func step(_ d: Int) { if let i = ok.firstIndex(of: sheetFocus), ok.indices.contains(i + d) { sheetFocus = ok[i + d] } else if !ok.contains(sheetFocus), let f = ok.first { sheetFocus = f } }
            switch k {
            case .back: if sheetBack { openSheet(.main) } else { closeSheet() }
            case .ok: if items.indices.contains(sheetFocus), !items[sheetFocus].dis { sheetAct(items[sheetFocus].id) }
            case .playPause: toggle()
            case .up: if !horiz { step(-1) }
            case .down: if !horiz { step(1) }
            case .left: if horiz { step(-1) } else if sheetBack { openSheet(.main) }
            case .right: if horiz { step(1) } else if items.indices.contains(sheetFocus), items[sheetFocus].chevron { sheetAct(items[sheetFocus].id) }
            }
            return
        }
        let step: Double = repeatCount > 16 ? 60 : (repeatCount > 4 ? 30 : 10)
        switch k {
        case .playPause: toggle(); show()
        case .back:
            if scrub != nil { scrubTask?.cancel(); scrub = nil }
            else if visible { visible = false; if let o = overlay() { focus = o } }
            else if showNext { stopCountdown(); showNext = false; nextDismissed = true; focus = .play }
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
        nextTimer?.invalidate(); scrubTask?.cancel(); uiTimer?.invalidate(); uiTimer = nil
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
