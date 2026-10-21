import TVServices

// Apple-TV-Startbildschirm (Top Shelf), 2026-10-21: steht man auf dem FilmFrei24-Symbol, zeigt der Startbildschirm
// die Top 10 als große 16:9-Bilder – ohne die App zu öffnen. „Abspielen“/„Mehr Infos“ springen direkt in die App
// (filmfrei24://play/<key> bzw. filmfrei24://title/<key>, verarbeitet in Router.deep).
final class ContentProvider: TVTopShelfContentProvider {
    private let base = "https://filmfrei24.com"

    override func loadTopShelfContent() async -> TVTopShelfContent? {
        guard let url = URL(string: base + "/beta/api.php?q=catalog&part=core"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var by: [String: [String: Any]] = [:]
        for (k, t) in [("films", "f"), ("series", "s")] {
            for x in (o[k] as? [[String: Any]]) ?? [] { if let id = x["id"] as? String { by[t + ":" + id] = x } }
        }
        var keys = (o["top10"] as? [String]) ?? []
        if keys.isEmpty {   // Rückfall: neueste Filme
            keys = ((o["films"] as? [[String: Any]]) ?? []).sorted { ($0["added"] as? String ?? "") > ($1["added"] as? String ?? "") }
                .prefix(10).compactMap { ($0["id"] as? String).map { "f:" + $0 } }
        }
        var items: [TVTopShelfCarouselItem] = []
        for key in keys.prefix(10) {
            guard let x = by[key], let title = x["title"] as? String else { continue }
            let it = TVTopShelfCarouselItem(identifier: key)
            it.title = title
            it.contextTitle = "Top 10 in Deutschland"
            if let img = tmdb(x["hero"] as? String ?? "", w: "original") ?? tmdb(x["card"] as? String ?? "", w: "w1280") {
                it.setImageURL(img, for: .screenScale1x)
                it.setImageURL(img, for: .screenScale2x)
            }
            var meta: [String] = []
            if let y = x["year"] as? String, !y.isEmpty { meta.append(y) }
            if let g = (x["genres"] as? [String])?.prefix(2), !g.isEmpty { meta.append(g.joined(separator: ", ")) }
            it.genre = meta.joined(separator: " · ")
            if let m = x["min"] as? Int, m > 0 { it.duration = TimeInterval(m * 60) }
            if (x["quality"] as? String ?? "").uppercased().contains("4K") { it.mediaOptions = [.videoResolution4K] }
            else { it.mediaOptions = [.videoResolutionHD] }
            let enc = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
            if let u = URL(string: "filmfrei24://title/" + enc) { it.displayAction = TVTopShelfAction(url: u) }
            if let u = URL(string: "filmfrei24://play/" + enc) { it.playAction = TVTopShelfAction(url: u) }
            items.append(it)
        }
        return items.isEmpty ? nil : TVTopShelfCarouselContent(style: .actions, items: items)
    }

    /// "~w1280/abc.jpg|780" -> https://image.tmdb.org/t/p/<w>/abc.jpg (große Bilder direkt von TMDB, 16:9)
    private func tmdb(_ v: String, w: String) -> URL? {
        guard v.hasPrefix("~"), let i = v.lastIndex(of: "|"), let s = v.firstIndex(of: "/") else { return v.isEmpty ? nil : URL(string: v) }
        return URL(string: "https://image.tmdb.org/t/p/" + w + String(v[s..<i]))
    }
}
