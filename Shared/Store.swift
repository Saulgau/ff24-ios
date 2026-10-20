import Foundation
import SwiftUI

/// App-weiter Zustand (eine Datenquelle: filmfrei24.com).
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var web = WebCatalog()
    @Published var user: User?
    @Published var watchlist: [String] = []          // Reihenfolge wie Server (neueste hinten)
    @Published var progress: [String: WatchProgress] = [:]
    @Published var unread = 0
    @Published var loading = false
    @Published var error: String?
    @AppStorage("subs") var subtitlesDefault = true

    private var seasonCache: [String: [WebSeason]] = [:]
    private let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]

    private init() {
        CookieKeeper.restore()
        // erst Plattencache zeigen, dann frisch laden
        if let core = try? Data(contentsOf: cacheDir.appendingPathComponent("web_core.json")),
           let c = try? JSONSerialization.jsonObject(with: core) as? J {
            let ex = (try? Data(contentsOf: cacheDir.appendingPathComponent("web_extra.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? J }
            web = WebCatalog(core: c, extra: ex)
        }
        Task { await refresh() }
    }

    func refresh() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        async let coreReq = try? API.http.data(from: API.url("/beta/api.php?q=catalog&part=core"))
        async let extraReq = try? API.http.data(from: API.url("/beta/api.php?q=catalog&part=extra"))
        let (core, extra) = await (coreReq, extraReq)
        if let d = core?.0, let c = try? JSONSerialization.jsonObject(with: d) as? J {
            let ex = extra.flatMap { try? JSONSerialization.jsonObject(with: $0.0) as? J }
            web = WebCatalog(core: c, extra: ex)
            seasonCache.removeAll()
            try? d.write(to: cacheDir.appendingPathComponent("web_core.json"))
            if let e = extra?.0 { try? e.write(to: cacheDir.appendingPathComponent("web_extra.json")) }
            error = nil
        } else if web.isEmpty {
            error = "Keine Verbindung zu FilmFrei24."
        }
        await refreshMe()
    }

    func refreshMe() async {
        guard let o = try? await API.get("/api/app.php?action=me") as? J else { return }
        apply(me: o)
    }

    func apply(me o: J) {
        user = User(o.o("user"))
        watchlist = (o["watchlist"] as? [Any])?.compactMap { $0 as? String } ?? []
        progress = WatchProgress.parse(o["progress"])
        Task { await refreshUnread() }
    }

    func refreshUnread() async {
        guard user != nil else { unread = 0; return }
        unread = await API.getObj("/api/inbox.php?action=unread_count").i("count") ?? 0
    }

    func login(email: String, password: String) async throws {
        let o = try await API.post("/api/app.php?action=login", ["email": email, "password": password]) as? J ?? [:]
        apply(me: o)
    }
    func register(name: String, email: String, password: String) async throws {
        let o = try await API.post("/api/app.php?action=register", ["name": name, "email": email, "password": password]) as? J ?? [:]
        apply(me: o)
    }
    func redeem(code: String) async throws {
        let o = try await API.post("/api/app.php?action=redeem", ["code": code]) as? J ?? [:]
        apply(me: o)
    }
    func logout() async {
        _ = try? await API.post("/api/app.php?action=logout", [:])
        CookieKeeper.clear()
        user = nil; watchlist = []; progress = [:]; unread = 0
    }

    // MARK: Merkliste / Fortschritt

    func inList(_ it: Item) -> Bool { watchlist.contains(it.id) }

    @discardableResult
    func toggleWatchlist(_ it: Item) async -> Bool? {
        let was = inList(it)
        if was { watchlist.removeAll { $0 == it.id } } else { watchlist.append(it.id) }
        let d = await API.postObj("/api/watchlist.php", ["slug": it.id, "action": was ? "remove" : "add"])
        if !d.b("ok") {
            if was { watchlist.append(it.id) } else { watchlist.removeAll { $0 == it.id } }
            return nil
        }
        return !was
    }

    func saveProgress(slug: String, pos: Double, dur: Double, seriesId: String?, season: Int?, ep: Int?) {
        guard user != nil, dur > 0, !slug.isEmpty else { return }
        var pct = Int(min(100, max(0, pos * 100 / dur)))
        if dur - pos <= 240 { pct = max(pct, 95) }           // wie Website: Abspann zählt als gesehen
        progress[slug] = WatchProgress(slug: slug, pos: pos, dur: dur, pct: pct, ts: Date().timeIntervalSince1970, season: season, episode: ep, seriesId: seriesId)
        var f = ["action": "save", "slug": slug, "pos": "\(Int(pos))", "dur": "\(Int(dur))", "pct": "\(pct)"]
        if let seriesId, let season, let ep { f["series_id"] = seriesId; f["ep_season"] = "\(season)"; f["ep_episode"] = "\(ep)" }
        Task { _ = try? await API.postForm("/api/progress.php", f) }
    }

    func removeCont(_ it: Item) {
        let slugs = it.isSeries ? progress.filter { $0.value.seriesId == it.id }.map(\.key) : [it.id]
        slugs.forEach { progress.removeValue(forKey: $0) }
        Task { for s in slugs { _ = try? await API.postForm("/api/progress.php", ["action": "delete", "slug": s]) } }
    }

    func clearProgress(_ action: String) async -> Bool {
        let ok = ((try? await API.postForm("/api/progress.php", ["action": action])) as? J)?.b("ok") ?? false
        if ok { await refreshMe() }
        return ok
    }

    // MARK: Abgeleitet (wie contItems/wlItems/prog der Website)

    var contItems: [(Item, WatchProgress)] {
        var seen = Set<String>(), out: [(Item, WatchProgress)] = []
        for p in progress.values.sorted(by: { $0.ts > $1.ts }) {
            let it = p.seriesId != nil ? web.by["s:\(p.seriesId!)"] : web.by["f:\(p.slug)"]
            guard let it, !seen.contains(it.key), !(p.seriesId == nil && p.pct >= 95) else { continue }
            seen.insert(it.key); out.append((it, p))
        }
        return out
    }

    var wlItems: [Item] { watchlist.reversed().compactMap { web.by["f:\($0)"] ?? web.by["s:\($0)"] } }

    func last(_ it: Item) -> WatchProgress? {
        it.isSeries ? progress.values.filter { $0.seriesId == it.id }.max { $0.ts < $1.ts } : progress[it.id]
    }

    func playLabel(_ it: Item) -> String {
        let p = last(it)
        if let p, p.pct < 95 { return it.isSeries && p.season != nil ? "S\(p.season!) F\(p.episode ?? 1) fortsetzen" : "Fortsetzen" }
        if it.isSeries, p?.season != nil { return "Nächste Folge abspielen" }
        return it.isSeries ? "S1 F1 abspielen" : "Abspielen"
    }

    func seasons(_ id: String) async -> [WebSeason] {
        if let c = seasonCache[id] { return c }
        let o = await API.getObj("/beta/api.php?q=series&id=" + API.enc(id))
        let s = o.a("seasons").compactMap { s -> WebSeason? in
            guard let n = s.i("n") else { return nil }
            return WebSeason(n: n, episodes: s.a("episodes").compactMap { e in
                guard let en = e.i("n") else { return nil }
                return WebEpisode(n: en, title: e.s("title"), desc: e.s("desc"), min: e.i("min") ?? 0, date: e.s("date"), thumb: e.s("thumb"), ok: e.b("ok"))
            })
        }.filter { $0.episodes.contains(where: \.ok) }
        seasonCache[id] = s
        return s
    }

    /// Was „Abspielen“ startet (wie playItem der Website): angefangene Folge, sonst nächste, sonst S1 F1.
    func playTarget(_ it: Item) async -> (season: Int, ep: Int, start: Double)? {
        guard it.isSeries else { let p = progress[it.id]; return (0, 0, (p != nil && p!.pct < 95) ? p!.pos : 0) }
        let all = await seasons(it.id).flatMap { s in s.episodes.filter(\.ok).map { (s.n, $0.n) } }
        guard let first = all.first else { return nil }
        guard let p = last(it), let ps = p.season else { return (first.0, first.1, 0) }
        if p.pct < 95 { return (ps, p.episode ?? 1, p.pos) }
        if let i = all.firstIndex(where: { $0 == (ps, p.episode ?? 1) }), i + 1 < all.count { return (all[i + 1].0, all[i + 1].1, 0) }
        return (first.0, first.1, 0)
    }
}
