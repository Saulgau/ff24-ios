#if os(iOS)
import SwiftUI
import UIKit

/*
 * 2026-10-22: Offline-Downloads wie Prime Video (nur iPhone/iPad – Apple TV kann nicht offline speichern).
 * Die MP4s liegen öffentlich im Storage -> Hintergrund-URLSession lädt weiter, auch wenn die App zu ist.
 * Ablage: Application Support/Downloads (nicht im iCloud-Backup). Schlüssel = Fortschritts-Slug
 * (Film-ID bzw. SerieID+SxxExx). Die rohe q=play-Antwort wird mitgespeichert -> Abspielen komplett offline.
 */
struct DLItem: Codable, Identifiable, Equatable {
    var key: String
    var type: String          // "f" / "s"
    var itemId: String
    var season: Int?
    var ep: Int?
    var title: String
    var sub: String
    var poster: String
    var src: String
    var vtt: String
    var play: Data            // q=play-JSON
    var added: Date
    var bytes: Int64 = 0
    var done: Int64 = 0
    var state: String = "queued"   // queued | loading | done | failed
    var id: String { key }
    var isEpisode: Bool { type == "s" }
    var pct: Int { bytes > 0 ? Int(done * 100 / bytes) : 0 }
}

final class Downloads: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = Downloads()
    static let sessionId = "com.filmfrei24.app.downloads"

    @Published private(set) var items: [DLItem] = []
    @Published var wifiOnly: Bool = UserDefaults.standard.object(forKey: "dl_wifi") as? Bool ?? true {
        didSet { UserDefaults.standard.set(wifiOnly, forKey: "dl_wifi") }
    }
    /// vom AppDelegate (Hintergrund-Ereignisse fertig)
    var bgCompletion: (() -> Void)?

    let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var d = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        var v = URLResourceValues(); v.isExcludedFromBackup = true
        try? d.setResourceValues(v)
        return d
    }()
    private var metaURL: URL { dir.appendingPathComponent("downloads.json") }
    private var lastPublish: [String: Date] = [:]
    private let lock = NSLock()

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.background(withIdentifier: Downloads.sessionId)
        c.isDiscretionary = false
        c.sessionSendsLaunchEvents = true
        c.allowsCellularAccess = true          // pro Anfrage über allowsCellularAccess gesteuert
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    override init() {
        super.init()
        if let d = try? Data(contentsOf: metaURL), let l = try? JSONDecoder().decode([DLItem].self, from: d) { items = l }
        reconcile()
    }

    // MARK: Dateien

    private func safe(_ k: String) -> String { k.replacingOccurrences(of: #"[^A-Za-z0-9._-]"#, with: "_", options: .regularExpression) }
    func file(_ key: String) -> URL { dir.appendingPathComponent(safe(key) + ".mp4") }
    func subFile(_ key: String) -> URL { dir.appendingPathComponent(safe(key) + ".de-forced.vtt") }
    func item(_ key: String) -> DLItem? { items.first { $0.key == key } }
    func ready(_ key: String) -> Bool { item(key)?.state == "done" && FileManager.default.fileExists(atPath: file(key).path) }

    var usedBytes: Int64 {
        let fs = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return fs.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    var freeBytes: Int64 {
        (try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
    }

    static func size(_ b: Int64) -> String {
        if b >= 1 << 30 { return String(format: "%.1f GB", Double(b) / Double(1 << 30)).replacingOccurrences(of: ".", with: ",") }
        if b >= 1 << 20 { return "\(b >> 20) MB" }
        return "\(b >> 10) KB"
    }

    static func key(type: String, id: String, season: Int?, ep: Int?) -> String {
        type == "s" ? episodeSlug(id, season ?? 1, ep ?? 1) : id
    }

    // MARK: Starten / Löschen

    /// Holt die Abspieldaten (wie der Player) und startet den Download. Rückgabe = Fehlertext oder nil.
    @MainActor
    func start(type: String, id: String, season: Int? = nil, ep: Int? = nil) async -> String? {
        let k = Downloads.key(type: type, id: id, season: season, ep: ep)
        if let x = item(k), x.state != "failed" { return nil }
        let o = await API.getObj("/beta/api.php?q=play&type=\(type)&id=" + API.enc(id) + (type == "s" ? "&season=\(season ?? 1)&ep=\(ep ?? 1)" : ""))
        guard let pi = PlayInfo(o), let u = URL(string: pi.src) else { return o.s("error").isEmpty ? "Nicht verfügbar" : o.s("error") }
        let raw = (try? JSONSerialization.data(withJSONObject: o)) ?? Data()
        remove(k)
        var it = DLItem(key: k, type: type, itemId: id, season: pi.season ?? season, ep: pi.ep ?? ep, title: pi.title, sub: pi.sub,
                        poster: pi.poster, src: pi.src, vtt: pi.vtt, play: raw, added: Date())
        it.state = "queued"
        var req = URLRequest(url: u)
        req.allowsCellularAccess = !wifiOnly
        req.setValue("FilmFrei24-iOS", forHTTPHeaderField: "User-Agent")
        let t = session.downloadTask(with: req)
        t.taskDescription = k
        items.append(it)
        save()
        t.resume()
        if !pi.vtt.isEmpty, let vu = URL(string: pi.vtt) {
            let dest = subFile(k)
            Task.detached { if let (d, _) = try? await URLSession.shared.data(from: vu) { try? d.write(to: dest) } }
        }
        return nil
    }

    /// Alle verfügbaren, noch nicht geladenen Folgen einer Staffel.
    @MainActor
    func startSeason(id: String, season: Int, episodes: [Int]) async -> Int {
        var n = 0
        for e in episodes where item(episodeSlug(id, season, e)) == nil {
            if await start(type: "s", id: id, season: season, ep: e) == nil { n += 1 }
        }
        return n
    }

    @MainActor
    func remove(_ key: String) {
        session.getAllTasks { ts in ts.filter { $0.taskDescription == key }.forEach { $0.cancel() } }
        try? FileManager.default.removeItem(at: file(key))
        try? FileManager.default.removeItem(at: subFile(key))
        items.removeAll { $0.key == key }
        save()
    }

    @MainActor
    func removeAll() { items.map(\.key).forEach(remove) }

    // MARK: Offline abspielen

    /// q=play-Daten mit lokaler Datei statt Netz-Adresse (nil = nicht fertig geladen).
    func offlinePlay(_ key: String) -> [String: Any]? {
        guard ready(key), let it = item(key), var o = (try? JSONSerialization.jsonObject(with: it.play)) as? [String: Any] else { return nil }
        o["src"] = file(key).absoluteString
        o["vtt"] = FileManager.default.fileExists(atPath: subFile(key).path) ? subFile(key).absoluteString : ""
        return o
    }

    /// Nächste heruntergeladene Folge derselben Serie (offline „Nächste Folge“).
    func nextDownloaded(after key: String) -> DLItem? {
        guard let d = item(key), d.isEpisode else { return nil }
        return items.filter { $0.itemId == d.itemId && $0.isEpisode && ready($0.key) }
            .sorted { ($0.season ?? 0, $0.ep ?? 0) < ($1.season ?? 0, $1.ep ?? 0) }
            .first { ($0.season ?? 0, $0.ep ?? 0) > (d.season ?? 0, d.ep ?? 0) }
    }

    // MARK: Zustand

    private func save() {
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: metaURL, options: .atomic) }
    }

    private func update(_ key: String, _ f: @escaping (inout DLItem) -> Void) {
        DispatchQueue.main.async {
            guard let i = self.items.firstIndex(where: { $0.key == key }) else { return }
            var x = self.items[i]; f(&x); self.items[i] = x
            if x.state != "loading" { self.save() }
        }
    }

    /// Nach Neustart: laufende Aufgaben zuordnen, verwaiste neu starten.
    private func reconcile() {
        session.getAllTasks { ts in
            let running = Set(ts.compactMap(\.taskDescription))
            DispatchQueue.main.async {
                for it in self.items where it.state != "done" && !running.contains(it.key) {
                    if FileManager.default.fileExists(atPath: self.file(it.key).path) { self.update(it.key) { $0.state = "done" } }
                    else if let u = URL(string: it.src) {
                        var req = URLRequest(url: u); req.allowsCellularAccess = !self.wifiOnly
                        let t = self.session.downloadTask(with: req); t.taskDescription = it.key; t.resume()
                        self.update(it.key) { $0.state = "queued" }
                    }
                }
            }
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let k = downloadTask.taskDescription else { return }
        let now = Date()
        // höchstens 2x pro Sekunde neu zeichnen
        lock.lock()
        let throttle = lastPublish[k].map { now.timeIntervalSince($0) < 0.5 } ?? false
        if !throttle { lastPublish[k] = now }
        lock.unlock()
        if throttle { return }
        update(k) { $0.state = "loading"; $0.done = totalBytesWritten; if totalBytesExpectedToWrite > 0 { $0.bytes = totalBytesExpectedToWrite } }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let k = downloadTask.taskDescription else { return }
        if let r = downloadTask.response as? HTTPURLResponse, r.statusCode >= 400 { update(k) { $0.state = "failed" }; return }
        let dest = file(k)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            let size = Int64((try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            update(k) { $0.state = "done"; $0.bytes = size; $0.done = size }
        } catch { update(k) { $0.state = "failed" } }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let k = task.taskDescription, let e = error as NSError? else { return }
        if e.code == NSURLErrorCancelled { return }   // gelöscht
        update(k) { $0.state = "failed" }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { self.bgCompletion?(); self.bgCompletion = nil }
    }
}

/// Hintergrund-Downloads: iOS weckt die App, wenn sie fertig sind.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        if identifier == Downloads.sessionId { Downloads.shared.bgCompletion = completionHandler } else { completionHandler() }
    }
}

// MARK: - Oberfläche

/// Reiter „Downloads“ (wie Prime): Filme einzeln, Serien als Gruppe.
struct DownloadsView: View {
    @EnvironmentObject var router: Router
    @ObservedObject var dl = Downloads.shared
    @State private var openSeries: String?
    @State private var ask: DLItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    if openSeries != nil { Button { openSeries = nil } label: {
                        Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                            .frame(width: 44, height: 44).background(Circle().fill(FF.btn.opacity(0.85)))
                    }.buttonStyle(PressStyle()) }
                    Text(openSeries.flatMap { s in dl.items.first { $0.itemId == s }?.title } ?? "Downloads").font(.inter(24, .bold)).foregroundColor(.white).lineLimit(1)
                    Spacer()
                }.padding(.horizontal, FF.pad).padding(.top, 10).padding(.bottom, 8)

                if dl.items.isEmpty {
                    EmptyState(title: "Keine Videos heruntergeladen",
                               text: "Lade Filme und Folgen herunter, um sie ohne Internet anzusehen – z. B. im Flugzeug oder unterwegs.") {
                        Cta(label: "Videos entdecken", icon: nil) { router.switchTab("home"); router.list("filme") }
                    }
                    VStack(spacing: 12) {
                        Text("Nur über WLAN herunterladen: " + (dl.wifiOnly ? "Ein" : "Aus")).font(.inter(15)).foregroundColor(FF.text2)
                        Button { router.go(.settings) } label: { Text("Downloads verwalten").font(.inter(16, .semibold)).foregroundColor(FF.blue) }
                    }.frame(maxWidth: .infinity)
                } else {
                    Text("\(dl.items.count) \(dl.items.count == 1 ? "Video" : "Videos") · \(Downloads.size(dl.usedBytes)) belegt · \(Downloads.size(dl.freeBytes)) frei")
                        .font(.inter(14)).foregroundColor(FF.text2).padding(.horizontal, FF.pad).padding(.bottom, 12)
                    VStack(spacing: 12) {
                        if let s = openSeries {
                            ForEach(dl.items.filter { $0.itemId == s && $0.isEpisode }.sorted { ($0.season ?? 0, $0.ep ?? 0) < ($1.season ?? 0, $1.ep ?? 0) }) { d in
                                row(d, title: d.sub.components(separatedBy: " · ").dropFirst().joined(separator: " · "), sub: (d.sub.components(separatedBy: " · ").first ?? "") + sizeText(d), wide: true)
                            }
                        } else {
                            ForEach(groups, id: \.0) { k, g in
                                if let d = g.first, d.isEpisode {
                                    let running = g.filter { $0.state != "done" && $0.state != "failed" }.count
                                    Button { openSeries = d.itemId } label: {
                                        rowBody(d, title: d.title, sub: "\(g.count) \(g.count == 1 ? "Folge" : "Folgen") · \(Downloads.size(g.reduce(0) { $0 + $1.bytes }))" + (running > 0 ? " · \(running) lädt" : ""),
                                                wide: false, series: true)
                                    }.buttonStyle(PressStyle())
                                } else if let d = g.first {
                                    row(d, title: d.title, sub: d.sub + sizeText(d), wide: false)
                                }
                            }
                        }
                    }.padding(.horizontal, FF.pad)
                }
            }.padding(.bottom, 120)
        }
        .background(FF.bg.ignoresSafeArea())
        .alert("Download löschen?", isPresented: Binding(get: { ask != nil }, set: { if !$0 { ask = nil } })) {
            Button("Löschen", role: .destructive) { if let a = ask { dl.remove(a.key) }; ask = nil }
            Button("Abbrechen", role: .cancel) { ask = nil }
        } message: { Text(ask.map { $0.title + ($0.isEpisode ? " – " + ($0.sub.components(separatedBy: " · ").first ?? "") : "") } ?? "") }
    }

    private var groups: [(String, [DLItem])] {
        var order: [String] = []; var m: [String: [DLItem]] = [:]
        for d in dl.items.sorted(by: { $0.added > $1.added }) {
            let k = d.isEpisode ? "s:" + d.itemId : "f:" + d.key
            if m[k] == nil { order.append(k) }
            m[k, default: []].append(d)
        }
        return order.map { ($0, m[$0]!) }
    }

    private func sizeText(_ d: DLItem) -> String { d.bytes > 0 ? " · " + Downloads.size(d.bytes) : "" }

    func row(_ d: DLItem, title: String, sub: String, wide: Bool) -> some View {
        HStack(spacing: 0) {
            Button { if d.state == "done" { router.playDownload(d) } } label: { rowBody(d, title: title, sub: sub, wide: wide, series: false) }.buttonStyle(PressStyle())
            Button { ask = d } label: {
                Image(systemName: "trash").font(.system(size: 19)).foregroundColor(Color(hex: 0xDFE3E7)).frame(width: 44, height: 44)
            }.buttonStyle(PressStyle()).padding(.trailing, 6)
        }.background(RoundedRectangle(cornerRadius: 8).fill(FF.box))
    }

    func rowBody(_ d: DLItem, title: String, sub: String, wide: Bool, series: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                FF.skel
                Img(url: d.poster)
                if d.state == "done" && !series {
                    Image(systemName: "play.fill").font(.system(size: 15)).foregroundColor(.white).frame(width: 34, height: 34).background(Circle().fill(Color.black.opacity(0.7)))
                }
            }.frame(width: wide ? 128 : 72, height: wide ? 72 : 108).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.inter(17, .semibold)).foregroundColor(.white).lineLimit(2).multilineTextAlignment(.leading)
                Text(sub).font(.inter(14)).foregroundColor(FF.text2).lineLimit(2)
                if !series && d.state != "done" {
                    Text(d.state == "failed" ? "Fehlgeschlagen – bitte erneut herunterladen" : d.state == "queued" ? (dl.wifiOnly ? "Wartet (nur WLAN)" : "In Warteschlange") : "Wird heruntergeladen · \(d.pct) %")
                        .font(.inter(13, .semibold)).foregroundColor(d.state == "failed" ? FF.red : FF.blue).padding(.top, 2)
                    if d.state != "failed" { ProgressLine(pct: max(d.pct, 1), height: 3).clipShape(Capsule()).padding(.top, 2) }
                }
            }
            Spacer(minLength: 0)
            if series { Image(systemName: "chevron.right").foregroundColor(.white).padding(.trailing, 6) }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

/// Grauer Knopf „Herunterladen“ unter „Abspielen“ (Film) bzw. „Staffel n herunterladen“ (Serie).
struct DownloadButton: View {
    let it: Item
    var season: Int? = nil
    var episodes: [Int] = []
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @ObservedObject var dl = Downloads.shared
    @State private var ask = false

    var body: some View {
        let d = it.isSeries ? nil : dl.item(it.id)
        Cta(label: label(d), icon: d?.state == "done" ? "checkmark" : "arrow.down.to.line", dark: true) {
            if store.user == nil { router.go(.login(register: false)); return }
            if it.isSeries {
                guard let s = season else { return }
                Task {
                    let n = await dl.startSeason(id: it.id, season: s, episodes: episodes)
                    router.toast = n == 0 ? "Alle Folgen sind schon heruntergeladen." : "\(n) Folgen werden heruntergeladen"
                }
            } else if d == nil || d?.state == "failed" {
                Task {
                    if let e = await dl.start(type: "f", id: it.id) { router.toast = e }
                    else { router.toast = dl.wifiOnly ? "Download gestartet (nur über WLAN)" : "Download gestartet" }
                }
            } else { ask = true }
        }
        .confirmationDialog(it.title, isPresented: $ask, titleVisibility: .visible) {
            if d?.state == "done" { Button("Offline ansehen") { if let d { router.playDownload(d) } } }
            else { Button("Zu den Downloads") { router.switchTab("downloads") } }
            Button(d?.state == "done" ? "Download löschen" : "Download abbrechen", role: .destructive) { dl.remove(it.id) }
        }
    }

    func label(_ d: DLItem?) -> String {
        if it.isSeries { return "Staffel \(season ?? 1) herunterladen" }
        guard let d else { return "Herunterladen" }
        switch d.state {
        case "done": return "Heruntergeladen"
        case "failed": return "Fehlgeschlagen – erneut versuchen"
        case "queued": return "In Warteschlange …"
        default: return "Wird heruntergeladen · \(d.pct) %"
        }
    }
}

/// Download-Symbol rechts neben jeder Folge: Pfeil / Fortschrittskreis / Haken.
struct EpisodeDownloadIcon: View {
    let id: String, season: Int, ep: Int
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @ObservedObject var dl = Downloads.shared

    var body: some View {
        let k = episodeSlug(id, season, ep)
        let d = dl.item(k)
        Button {
            if store.user == nil { router.go(.login(register: false)); return }
            if let d, d.state != "failed" { if d.state == "done" { router.playDownload(d) } else { router.switchTab("downloads") }; return }
            Task { if let e = await dl.start(type: "s", id: id, season: season, ep: ep) { router.toast = e } }
        } label: {
            ZStack {
                if d == nil || d?.state == "failed" { Image(systemName: "arrow.down.to.line").font(.system(size: 20, weight: .medium)).foregroundColor(.white) }
                else if d?.state == "done" { Image(systemName: "checkmark").font(.system(size: 20, weight: .bold)).foregroundColor(FF.blue) }
                else {
                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 3)
                    Circle().trim(from: 0, to: CGFloat(d?.pct ?? 0) / 100).stroke(FF.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                }
            }.frame(width: 26, height: 26).frame(width: 44, height: 44)
        }.buttonStyle(PressStyle())
    }
}

/// Einstellungen „Streamen und herunterladen“.
struct DownloadSettings: View {
    @ObservedObject var dl = Downloads.shared
    @State private var ask = false
    var body: some View {
        BoxCard(title: "Streamen und herunterladen") {
            SetRow(title: "Nur über WLAN herunterladen", sub: "Spart mobile Daten. Gilt für neue Downloads.") {
                Toggle("", isOn: $dl.wifiOnly).labelsHidden().tint(FF.blue)
            }
            SetRow(title: "Belegter Speicher", sub: "\(dl.items.count) Downloads · \(Downloads.size(dl.usedBytes)) · \(Downloads.size(dl.freeBytes)) frei", last: dl.items.isEmpty) { EmptyView() }
            if !dl.items.isEmpty {
                SetRow(title: "Alle Downloads löschen", last: true) { GreyButton(label: "Löschen") { ask = true } }
            }
        }
        .alert("Alle Downloads löschen?", isPresented: $ask) {
            Button("Alle löschen", role: .destructive) { dl.removeAll() }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("\(dl.items.count) Videos werden vom Gerät entfernt.") }
    }
}
#endif
