import Foundation

/// Anzeige-Katalog wie die Website (beta/api.php?q=catalog).
final class Item: Identifiable, Hashable {
    let t: Character            // "f" Film, "s" Serie
    let id: String              // Film = Slug, Serie = Serien-ID
    let title, year, endYear, quality, lang, added: String
    let min, votes, seasons, episodes: Int
    let genres: [String]
    let rating: Double
    let card, hero, poster, logo: String
    var desc = "", tagline = ""
    var cast: [String] = []
    // 2026-10-21 wie Website: soon 1 = Bald, 2 = wird aktualisiert; prog [fertig, gesamt] Serie im Aufbau;
    // nf = Serie neu (ts), ns = [[Staffel, ts]], ne = [ts] neue Folgen
    var soon = 0
    var prog: [Int] = []
    var nf: Double = 0
    var ns: [Double] = []
    var ne: [Double] = []

    var key: String { "\(t):\(id)" }
    var isSeries: Bool { t == "s" }

    init(_ o: J, _ t: Character) {
        self.t = t; id = o.s("id"); title = o.s("title"); year = o.s("year"); endYear = o.s("endYear")
        quality = o.s("quality"); lang = o.s("lang"); added = o.s("added")
        min = o.i("min") ?? 0; votes = o.i("votes") ?? 0; seasons = o.i("seasons") ?? 0; episodes = o.i("episodes") ?? 0
        genres = o.strs("genres"); rating = o.d("rating") ?? 0
        card = unpackImg(o.s("card")); hero = unpackImg(o.s("hero")); poster = unpackImg(o.s("poster")); logo = unpackImg(o.s("logo"))
        soon = o.i("soon") ?? 0
        prog = ((o["prog"] as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.intValue }
        nf = o.d("nf") ?? 0
        ns = ((o["ns"] as? [Any]) ?? []).compactMap { (($0 as? [Any])?.last as? NSNumber)?.doubleValue }
        ne = ((o["ne"] as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
    }
    static func == (a: Item, b: Item) -> Bool { a.key == b.key }
    func hash(into h: inout Hasher) { h.combine(key) }
}

struct WebEpisode: Identifiable { let n: Int; let title, desc: String; let min: Int; let date, thumb: String; let ok: Bool; var id: Int { n } }
struct WebSeason: Identifiable { let n: Int; let episodes: [WebEpisode]; var id: Int { n } }

struct WebCatalog {
    var films: [Item] = []
    var series: [Item] = []
    var top: [Item] = []
    var trailers: [String: String] = [:]
    var by: [String: Item] = [:]
    var all: [Item] { films + series }
    var isEmpty: Bool { films.isEmpty && series.isEmpty }
    func isTop(_ it: Item) -> Bool { top.contains(it) }
    func rank(_ it: Item) -> Int { top.firstIndex(of: it) ?? -1 }

    init() {}
    init(core: J, extra: J?) {
        films = core.a("films").map { Item($0, "f") }.filter { !$0.id.isEmpty }
        series = core.a("series").map { Item($0, "s") }.filter { !$0.id.isEmpty }
        for it in films + series { by[it.key] = it }
        if let ex = extra {
            for (k, v) in ex {
                guard let a = v as? [Any], let it = by[k] else { continue }
                it.desc = a.first as? String ?? ""
                it.cast = (a.count > 1 ? a[1] as? [Any] : nil)?.compactMap { $0 as? String } ?? []
                it.tagline = a.count > 2 ? (a[2] as? String ?? "") : ""
            }
        }
        top = core.strs("top10").compactMap { by[$0] }
        let tbase = core.s("tbase")
        for (k, v) in core.o("trailers") ?? [:] { if let f = v as? String { trailers[k] = tbase + f } }
    }

    func badge(_ it: Item) -> String {
        if it.soon > 0 { return it.soon == 2 ? "WIRD AKTUALISIERT" : "BALD" }
        if !it.lang.isEmpty { return it.lang }
        if isTop(it) { return "TOP 10" }
        if it.isSeries { let n = newInfo(it); if !n.isEmpty { return n } }
        if !it.isSeries && daysAgo(it.added) < 7 { return "NEU HINZUGEFÜGT" }
        if !it.isSeries && it.quality.lowercased().contains("sd") { return "NUR SD" }
        return ""
    }
}

struct WatchProgress {
    let slug: String
    let pos, dur: Double
    let pct: Int
    let ts: Double
    let season, episode: Int?
    let seriesId: String?

    static func parse(_ any: Any?) -> [String: WatchProgress] {
        guard let o = any as? J else { return [:] }   // leer kommt als []
        var out: [String: WatchProgress] = [:]
        for (k, v) in o {
            guard let e = v as? J else { continue }
            let sid = e.s("series_id")
            out[k] = WatchProgress(slug: k, pos: e.d("pos") ?? 0, dur: e.d("dur") ?? 0, pct: e.i("pct") ?? 0, ts: e.d("ts") ?? 0,
                              season: e.i("ep_season"), episode: e.i("ep_episode"), seriesId: sid.isEmpty ? nil : sid)
        }
        return out
    }
}

struct User {
    let id, name, email, avatar, role, tier, label, until: String
    let hasPassword: Bool

    init?(_ o: J?) {
        guard let o, !o.s("id").isEmpty else { return nil }
        let m = o.o("member")
        id = o.s("id"); name = o.s("name"); email = o.s("email"); avatar = o.s("avatar"); role = o.s("role")
        tier = o.s("tier").isEmpty ? (m?.s("tier") ?? "user") : o.s("tier")
        label = o.s("label").isEmpty ? (m?.s("label") ?? "") : o.s("label")
        until = o.s("until")
        hasPassword = o["haspw"] == nil ? true : o.b("haspw")
    }
}

/// Was der Player abspielt (beta/api.php?q=play).
struct PlayInfo {
    let type: String, id, title, sub, src, vtt, poster, progressSlug: String
    let season, ep: Int?
    let intro: (Double, Double)?
    let recap: (Double, Double)?
    let credits: Double?
    let next: (season: Int, ep: Int, title: String, thumb: String)?

    init?(_ o: J) {
        guard o.b("ok"), !o.s("src").isEmpty else { return nil }
        type = o.s("type"); id = o.s("id"); title = o.s("title"); sub = o.s("sub"); src = o.s("src"); vtt = o.s("vtt")
        poster = o.s("poster"); progressSlug = o.s("progressSlug").isEmpty ? o.s("id") : o.s("progressSlug")
        season = o.i("season"); ep = o.i("ep")
        let sk = o.o("skip")
        func seg(_ n: String) -> (Double, Double)? {
            guard let a = sk?[n] as? [Any], a.count == 2, let x = (a[0] as? NSNumber)?.doubleValue, let y = (a[1] as? NSNumber)?.doubleValue else { return nil }
            return (x, y)
        }
        intro = seg("intro"); recap = seg("recap")
        credits = sk?.d("credits")
        if let n = o.o("next"), let s = n.i("season"), let e = n.i("ep") { next = (s, e, n.s("title"), n.s("thumb")) } else { next = nil }
    }
    /// Kontrollzentrum: nur Titel (ohne Jahr), Serie „Titel – S1 F3“, nie FilmFrei24.
    var mediaTitle: String {
        let t = title.replacingOccurrences(of: #"\s*[\(\[]\d{4}[\)\]]\s*$"#, with: "", options: .regularExpression)
        if type == "s", let s = season, let e = ep { return "\(t) – S\(s) F\(e)" }
        return t
    }
}

// MARK: - Hilfen wie Website

func daysAgo(_ d: String) -> Double {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
    guard let t = f.date(from: String(d.prefix(10))) else { return 1e9 }
    return Date().timeIntervalSince(t) / 86400
}

func score(_ it: Item) -> Double { it.rating * log10(10 + Double(it.votes)) }
func byScore(_ a: Item, _ b: Item) -> Bool { score(a) > score(b) }
func byAdded(_ a: Item, _ b: Item) -> Bool { a.added > b.added }

func mfmt(_ m: Int) -> String {
    guard m > 0 else { return "" }
    let h = m / 60
    return h > 0 ? "\(h) Std." + (m % 60 > 0 ? " \(m % 60) Min." : "") : "\(m) Min."
}
func seasonsText(_ n: Int) -> String { "\(n) Staffel" + (n == 1 ? "" : "n") }
func fmt1(_ d: Double) -> String { String(format: "%.1f", d) }
func eur(_ n: Double) -> String {
    let f = NumberFormatter(); f.numberStyle = .currency; f.locale = Locale(identifier: "de_DE"); return f.string(from: NSNumber(value: n)) ?? "\(n) €"
}

func genresOf(_ list: [Item]) -> [String] {
    Array(Set(list.flatMap(\.genres))).sorted { $0.compare($1, locale: Locale(identifier: "de")) == .orderedAscending }
}

func genreRows(_ list: [Item], max: Int) -> [(String, [Item])] {
    var c: [String: Int] = [:]
    list.forEach { $0.genres.forEach { c[$0, default: 0] += 1 } }
    return c.filter { $0.value >= 8 }.sorted { $0.value > $1.value }.prefix(max).map { g in
        (g.key, Array(list.filter { $0.genres.contains(g.key) }.sorted(by: byScore).prefix(30)))
    }
}

/// Serien-Kennzeichnung wie newInfo() der Website (nur 7 Tage)
func newInfo(_ it: Item) -> String {
    let now = Date().timeIntervalSince1970, fresh: (Double) -> Bool = { $0 > 0 && now - $0 < 7 * 86400 }
    if it.prog.count == 2 { return "\(it.prog[0]) VON \(it.prog[1]) FOLGEN" }
    if fresh(it.nf) { return "NEUE SERIE" }
    let ns = it.ns.filter(fresh).count
    if ns > 0 { return ns == 1 ? "NEUE STAFFEL" : "NEUE STAFFELN" }
    let ne = it.ne.filter(fresh).count
    return ne == 0 ? "" : (ne == 1 ? "NEUE FOLGE" : "NEUE FOLGEN")
}

func isSoonBadge(_ b: String) -> Bool { b == "BALD" || b == "WIRD AKTUALISIERT" }

func heroPick(_ list: [Item], _ n: Int) -> [Item] {
    Array(list.filter { $0.soon == 0 && !$0.hero.isEmpty && !$0.logo.isEmpty && $0.rating >= 5.5 }.shuffled().prefix(n))
}

func searchItems(_ all: [Item], _ q: String) -> [Item] {
    let t = q.trimmingCharacters(in: .whitespaces).lowercased()
    let w = t.split(separator: " ").map(String.init)
    guard !w.isEmpty else { return [] }
    return all.filter { it in
        let h = ([it.title] + it.genres + it.cast + [it.year]).joined(separator: " ").lowercased()
        return w.allSatisfy { h.contains($0) }
    }.sorted { a, b in
        let sa = a.title.lowercased().hasPrefix(t), sb = b.title.lowercased().hasPrefix(t)
        return sa != sb ? sa : score(a) > score(b)
    }
}

func episodeSlug(_ id: String, _ s: Int, _ e: Int) -> String { id + String(format: "S%02dE%02d", s, e) }

func titleURL(_ it: Item) -> String { "\(BASE)/#/titel/\(it.t)/" + API.enc(it.id) }
