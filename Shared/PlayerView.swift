import SwiftUI
import AVKit
import MediaPlayer

/// Vollbild-Player. Daten wie Website-Player (beta/api.php?q=play): Video, Forced-VTT, Intro/Abspann, nächste Folge.
struct PlayerView: View {
    let req: PlayRequest
    @StateObject private var m = PlayerModel()
    @Environment(\.dismiss) var dismiss
    @State private var report = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let p = m.player {
                AVPlayerControllerView(player: p, info: m.info, delegate: m).ignoresSafeArea()
            }
            if !m.cue.isEmpty {
                VStack { Spacer()
                    Text(m.cue).font(.inter(19, .medium)).foregroundColor(.white).multilineTextAlignment(.center)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Color.black.opacity(0.6)).padding(.bottom, 70 * FF.scale)
                }.allowsHitTesting(false)
            }
            if m.loading && m.error == nil { ProgressView().tint(.white).scaleEffect(1.6) }

            // Intro überspringen / Nächste Folge (rechts unten, wie Website)
            VStack { Spacer(); HStack { Spacer()
                if m.showSkip {
                    Button { m.skipIntro() } label: { pill(m.skipLabel, "forward.end.fill") }.buttonStyle(FocusStyle())
                } else if let n = m.info?.next, m.showNext {
                    Button { m.playNext() } label: { pill("Nächste Folge: S\(n.season) F\(n.ep)" + (m.countdown > 0 ? " (\(m.countdown))" : ""), "forward.fill") }.buttonStyle(FocusStyle())
                }
            }.padding(.trailing, 28).padding(.bottom, 110 * FF.scale) }

            #if os(iOS)
            VStack { HStack {
                Button { close() } label: { Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundColor(.white).frame(width: 44, height: 44).background(Circle().fill(Color.black.opacity(0.45))) }
                Spacer()
                if m.info != nil && req.trailer == nil {
                    Button { m.player?.pause(); report = true } label: { Image(systemName: "flag").font(.system(size: 17, weight: .semibold)).foregroundColor(.white).frame(width: 44, height: 44).background(Circle().fill(Color.black.opacity(0.45))) }
                }
            }.padding(.horizontal, 12).padding(.top, 6); Spacer() }
            #endif

            if let e = m.error {
                VStack(spacing: 16) {
                    Text("Wiedergabe nicht möglich").font(.inter(22, .bold)).foregroundColor(.white)
                    Text(e).font(.inter(15)).foregroundColor(Color(hex: 0xCFD3D8)).multilineTextAlignment(.center).frame(maxWidth: 520)
                    HStack(spacing: 10) {
                        GreyButton(label: "Problem melden") { report = true }
                        GreyButton(label: "Schließen", white: true) { close() }
                    }
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.9))
            }
        }
        .statusBarHidden()
        .task { await m.start(req) }
        .onDisappear { m.stop() }
        .sheet(isPresented: $report) {
            ReportSheet(title: (m.info?.title ?? "") + ((m.info?.sub).map { " – \($0)" } ?? ""), url: reportURL, pos: m.player?.currentTime().seconds ?? 0)
        }
        #if os(tvOS)
        .onExitCommand { close() }
        #endif
    }

    var reportURL: String {
        guard let i = m.info else { return BASE }
        return i.type == "s" ? "\(BASE)/player/?type=series&s=\(i.id)&season=\(i.season ?? 1)&ep=\(i.ep ?? 1)" : "\(BASE)/player/?s=\(i.id)"
    }

    func close() { m.stop(); dismiss() }

    func pill(_ t: String, _ icon: String) -> some View {
        HStack(spacing: 8) { Image(systemName: icon); Text(t).font(.inter(16, .bold)) }
            .foregroundColor(FF.dark).padding(.horizontal, 20).frame(minHeight: 46 * FF.scale)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.94))).shadow(color: .black.opacity(0.45), radius: 12, y: 6)
    }
}

@MainActor
final class PlayerModel: NSObject, ObservableObject, AVPlayerViewControllerDelegate {
    @Published var player: AVPlayer?
    @Published var info: PlayInfo?
    @Published var cue = ""
    @Published var loading = true
    @Published var error: String?
    @Published var showSkip = false
    @Published var skipLabel = "Intro überspringen"
    private var skipTo = 0.0
    @Published var showNext = false
    @Published var countdown = 0

    private var cues: [(Double, Double, String)] = []
    private var obs: Any?
    private var endObs: NSObjectProtocol?
    private var statusObs: NSKeyValueObservation?
    private var lastSave = Date.distantPast
    private var nextTimer: Timer?
    private var autoNextCancelled = false

    func start(_ req: PlayRequest) async {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        if let t = req.trailer {
            info = nil
            play(url: t.url, title: t.title, poster: "", start: 0)
            return
        }
        await load(type: req.type, id: req.itemId, season: req.season, ep: req.ep, start: req.start)
    }

    func load(type: String, id: String, season: Int, ep: Int, start: Double) async {
        loading = true; error = nil; showNext = false; showSkip = false; autoNextCancelled = false; cues = []; cue = ""
        let o = await API.getObj("/beta/api.php?q=play&type=\(type)&id=" + API.enc(id) + (type == "s" ? "&season=\(season)&ep=\(ep)" : ""))
        guard let i = PlayInfo(o) else {
            loading = false
            error = o.s("error").isEmpty ? "Dieser Titel ist noch nicht verfügbar." : o.s("error"); return
        }
        info = i
        // gespeicherten Fortschritt nutzen, wenn nichts übergeben wurde
        var pos = start
        if pos < 0 { pos = Store.shared.progress[i.progressSlug].flatMap { $0.pct < 95 ? $0.pos : nil } ?? 0 }
        play(url: i.src, title: i.mediaTitle, poster: i.poster, start: pos)
        if !i.vtt.isEmpty && Store.shared.subtitlesDefault { Task { await loadVTT(i.vtt) } }
    }

    private func play(url: String, title: String, poster: String, start: Double) {
        guard let u = URL(string: url) else { error = "Ungültige Adresse."; return }
        teardownObservers()
        let item = AVPlayerItem(url: u)
        // Kontrollzentrum/Sperrbildschirm: nur Titel + Poster, nie FilmFrei24
        let meta: [AVMetadataItem] = [metaItem(.commonIdentifierTitle, title as NSString)]
        if !poster.isEmpty {
            Task {
                if let r = try? await URLSession.shared.data(from: URL(string: poster)!) {
                    item.externalMetadata = meta + [metaItem(.commonIdentifierArtwork, r.0 as NSData, dataType: kCMMetadataBaseDataType_JPEG as String)]
                }
            }
        }
        item.externalMetadata = meta
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
        if start > 5 { p.seek(to: CMTime(seconds: start, preferredTimescale: 600)) }
        obs = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor in self?.tick(t.seconds) }
        }
        endObs = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.save(force: true); if self?.info?.next != nil { self?.playNext() } }
        }
        p.play()
    }

    private func metaItem(_ id: AVMetadataIdentifier, _ v: NSCopying & NSObjectProtocol, dataType: String? = nil) -> AVMetadataItem {
        let m = AVMutableMetadataItem(); m.identifier = id; m.value = v; m.extendedLanguageTag = "und"
        if let dataType { m.dataType = dataType }
        return m.copy() as! AVMetadataItem
    }

    private func tick(_ t: Double) {
        guard t.isFinite else { return }
        // Forced-Untertitel
        let c = cues.first { t >= $0.0 && t <= $0.1 }?.2 ?? ""
        if c != cue { cue = c }
        guard let i = info else { return }
        // Rückblick vor Intro (wie Website): Knopf nur im erkannten Abschnitt, springt an sein Ende
        if let r = i.recap, t >= r.0, t < r.1 - 1 { showSkip = true; skipLabel = "Rückblick überspringen"; skipTo = r.1 }
        else if let iv = i.intro, t >= iv.0, t < iv.1 - 1 { showSkip = true; skipLabel = "Intro überspringen"; skipTo = iv.1 }
        else { showSkip = false }
        let dur = player?.currentItem?.duration.seconds ?? 0
        if i.next != nil, dur.isFinite, dur > 0 {
            let creditsAt = i.credits ?? (dur - 25)
            let inCredits = t >= creditsAt && t < dur - 1
            if inCredits && !showNext && !autoNextCancelled { showNext = true; startCountdown() }
            if !inCredits && showNext { showNext = false; nextTimer?.invalidate(); countdown = 0 }
        }
        if Date().timeIntervalSince(lastSave) > 10 { save(force: false) }
    }

    private func startCountdown() {
        countdown = 10
        nextTimer?.invalidate()
        nextTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] tm in
            Task { @MainActor in
                guard let self else { tm.invalidate(); return }
                if self.player?.rate == 0 { return }     // pausiert: warten
                self.countdown -= 1
                if self.countdown <= 0 { tm.invalidate(); self.playNext() }
            }
        }
    }

    func skipIntro() {
        guard skipTo > 0 else { return }
        player?.seek(to: CMTime(seconds: skipTo, preferredTimescale: 600)); showSkip = false
    }

    func playNext() {
        guard let i = info, let n = i.next else { return }
        save(force: true); nextTimer?.invalidate(); countdown = 0
        Task { await load(type: "s", id: i.id, season: n.season, ep: n.ep, start: 0) }
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
        nextTimer?.invalidate()
        teardownObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        // Kontrollzentrum leeren: nach dem Schließen steht dort nichts mehr (weder Titel noch Seitenname)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func teardownObservers() {
        if let obs, let p = player { p.removeTimeObserver(obs) }
        obs = nil
        if let endObs { NotificationCenter.default.removeObserver(endObs) }
        endObs = nil
        statusObs = nil
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

/// AVPlayerViewController mit Systemsteuerung (AirPlay, PiP, Spulen, Apple-TV-Fernbedienung).
struct AVPlayerControllerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let info: PlayInfo?
    let delegate: AVPlayerViewControllerDelegate

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.delegate = delegate
        vc.videoGravity = .resizeAspect
        #if os(iOS)
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.updatesNowPlayingInfoCenter = true
        #endif
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}
