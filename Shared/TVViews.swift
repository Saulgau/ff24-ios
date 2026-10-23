#if os(tvOS)
import SwiftUI
import AVKit

// Apple-TV-Oberfläche (2026-10-20), Aufbau wie die aktuelle Prime-Video-App, aber im FilmFrei24-Design:
// Navigation oben, Hintergrundbild + Infos des fokussierten Titels, Reihen mit Querformat-Karten,
// Karte zoomt beim Fokussieren kurz heran und zurück, bleibt man stehen, läuft der Trailer (stumm).
// Größen hier in echten Fernseh-Punkten (1920 × 1080) -- .inter() multipliziert auf tvOS mit FF.scale.

extension Font {
    static func tv(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font { .inter(size / FF.scale, w) }
}

enum TVL {
    static let side: CGFloat = 96          // Rand links/rechts
    static let cardW: CGFloat = 372
    static let cardH: CGFloat = 209        // 16:9
    static let infoH: CGFloat = 470        // Info-Bereich oben (unter der Navigation)
}

// MARK: - Hintergrund: Bild, nach kurzer Zeit Trailer

struct TVBackdrop: View {
    let item: Item?
    var trailer: String? = nil
    var delay: Double = 2.5
    @State private var player: AVPlayer?
    @State private var showVideo = false

    var body: some View {
        ZStack {
            FF.bg
            if let it = item {
                Img(url: it.hero.isEmpty ? it.card : it.hero, fallback: it.poster)
                    .id(it.key).transition(.opacity)
            }
            if showVideo, let p = player { TVVideoLayer(player: p).transition(.opacity) }
            LinearGradient(stops: [.init(color: FF.bg, location: 0), .init(color: FF.bg.opacity(0.92), location: 0.28),
                                   .init(color: FF.bg.opacity(0.35), location: 0.55), .init(color: .clear, location: 0.75)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: FF.bg.opacity(0.75), location: 0.62), .init(color: FF.bg, location: 0.85)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: item?.key)
        .task(id: (item?.key ?? "") + (trailer ?? "")) {
            stop()
            guard let t = trailer, let u = URL(string: t) else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            let p = AVPlayer(url: u)
            p.isMuted = true
            player = p
            p.play()
            // erst einblenden, wenn wirklich Bilder laufen (Laden kann dauern), sonst Standbild lassen
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                if p.currentTime().seconds > 0.3 { withAnimation(.easeIn(duration: 0.6)) { showVideo = true }; break }
            }
        }
        .onDisappear { stop() }
    }

    private func stop() { player?.pause(); player = nil; showVideo = false }
}

struct TVVideoLayer: UIViewRepresentable {
    let player: AVPlayer
    final class V: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var pl: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    func makeUIView(context: Context) -> V { let v = V(); v.pl.player = player; v.pl.videoGravity = .resizeAspectFill; return v }
    func updateUIView(_ v: V, context: Context) { v.pl.player = player }
}

// MARK: - Infos zum Titel (oben links)

struct TVInfo: View {
    let it: Item
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LogoOrTitle(it: it, size: 40 / FF.scale)
                .frame(maxWidth: 560, maxHeight: 150, alignment: .bottomLeading)
                .shadow(color: .black.opacity(0.6), radius: 12)
            let b = store.web.badge(it)
            if !b.isEmpty && b != "TOP 10" {
                Text(tvBadgeText(b)).font(.tv(26, .semibold)).foregroundColor(isSoonBadge(b) ? FF.soon : FF.green)
            } else if store.web.isTop(it) {
                Text("Nr. \(store.web.rank(it) + 1) in Deutschland").font(.tv(26, .semibold)).foregroundColor(FF.green)
            }
            TVMeta(it: it)
            if !it.desc.isEmpty {
                Text(it.desc).font(.tv(25)).foregroundColor(Color(hex: 0xD7DBDF)).lineLimit(3).lineSpacing(4)
                    .frame(maxWidth: 900, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: it.key)
    }
}

struct TVMeta: View {
    let it: Item
    var body: some View {
        HStack(spacing: 18) {
            if it.rating > 0 {
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { i in
                        let v = it.rating / 2 - Double(i)
                        Image(systemName: v >= 0.75 ? "star.fill" : v >= 0.25 ? "star.leadinghalf.filled" : "star")
                            .font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
                    }
                    Text(fmt1(it.rating)).font(.tv(24, .semibold)).foregroundColor(.white).padding(.leading, 6)
                }
            }
            if !it.year.isEmpty { Text(it.year).font(.tv(24)).foregroundColor(FF.text2) }
            Text(it.isSeries ? seasonsText(it.seasons) : mfmt(it.min)).font(.tv(24)).foregroundColor(FF.text2)
            if !it.genres.isEmpty { Text(it.genres.prefix(2).joined(separator: " • ")).font(.tv(24, .medium)).foregroundColor(.white) }
            if !it.isSeries && !it.quality.isEmpty {
                Text(it.quality.lowercased().contains("sd") ? "SD" : "HD").font(.tv(18, .bold)).foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2).overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.6), lineWidth: 1.5))
            }
        }.lineLimit(1)
    }
}

/// Abzeichen ("NEUE FOLGEN") als normaler Text ("Neue Folgen").
func tvBadgeText(_ b: String) -> String {
    switch b.uppercased() {
    case "NEUE FOLGEN": return "Neue Folgen"
    case "NEUE FOLGE": return "Neue Folge"
    case "NEUE STAFFEL": return "Neue Staffel"
    case "NEUE SERIE": return "Neue Serie"
    case "NEU HINZUGEFÜGT": return "Neu hinzugefügt"
    case "NUR SD": return "Nur SD"
    default: let l = b.lowercased(); return l.prefix(1).uppercased() + l.dropFirst()
    }
}

// MARK: - Karte mit Fokus-Effekt

/// Fokus: weißer Rahmen, Bild zoomt kurz heran und wieder zurück (User-Wunsch), danach ruhig.
struct TVFocusStyle: ButtonStyle {
    var radius: CGFloat = 10
    var pulse: CGFloat = 1.1
    func makeBody(configuration: Configuration) -> some View { FocusBody(configuration: configuration, radius: radius, pulse: pulse) }
    struct FocusBody: View {
        let configuration: Configuration
        let radius: CGFloat
        let pulse: CGFloat
        @Environment(\.isFocused) private var focused
        @State private var big = false
        var body: some View {
            configuration.label
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius + 3).stroke(Color.white, lineWidth: focused ? 5 : 0).padding(-4))
                .scaleEffect(configuration.isPressed ? 0.97 : (big ? pulse : 1))
                .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: 18, y: 10)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
                // 2026-10-23 User: kein Hüpfen beim Auswählen mehr → Fokus nur weißer Rahmen + Schatten (Puls entfernt)
        }
    }
}

struct TVCard: View {
    let it: Item
    var progress: Double? = nil
    var badge = ""
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(hex: 0x141A21)
            Img(url: it.card.isEmpty ? it.poster : it.card, fallback: it.poster)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            LogoOrTitle(it: it, size: 22 / FF.scale).frame(maxWidth: TVL.cardW * 0.62, maxHeight: TVL.cardH * 0.36, alignment: .bottomLeading)
                .padding(14).shadow(color: .black.opacity(0.7), radius: 6)
            if progress == nil, !badge.isEmpty, badge != "TOP 10" {
                Text(tvBadgeText(badge)).font(.tv(17, .bold)).foregroundColor(FF.dark).lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(UnevenCorners(tr: 8, bl: 8).fill(isSoonBadge(badge) ? FF.soon : Color.white))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            if let p = progress {
                VStack { Spacer(); GeometryReader { g in
                    ZStack(alignment: .leading) { Color.white.opacity(0.25); FF.blue.frame(width: g.size.width * max(0.02, min(1, p / 100))) }
                }.frame(height: 6) }
            }
        }
        .frame(width: TVL.cardW, height: TVL.cardH)
    }
}

struct TVRow: View {
    let title: String
    let items: [Item]
    var top10 = false
    var progress = false
    var focus: FocusState<String?>.Binding
    var rowId: String
    let open: (Item) -> Void
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.tv(30, .bold)).foregroundColor(.white).padding(.leading, TVL.side)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: top10 ? 8 : 26) {
                    ForEach(Array(items.enumerated()), id: \.element.key) { i, it in
                        HStack(alignment: .bottom, spacing: -14) {
                            if top10 {
                                Text("\(i + 1)").font(.system(size: 190, weight: .black, design: .rounded))
                                    .foregroundColor(Color(hex: 0x2B333D)).overlay(Text("\(i + 1)").font(.system(size: 190, weight: .black, design: .rounded)).foregroundColor(.clear))
                                    .frame(height: TVL.cardH).offset(y: 18)
                            }
                            Button { open(it) } label: { TVCard(it: it, progress: progress ? store.last(it).map { Double($0.pct) } : nil, badge: store.web.badge(it)) }
                                .buttonStyle(TVFocusStyle())
                                .focused(focus, equals: rowId + "|" + it.key)
                        }
                    }
                }
                .padding(.horizontal, TVL.side).padding(.vertical, 24)
            }
        }
        .focusSection()
        .id(rowId)
    }
}

// MARK: - Navigation oben (Pillen)

struct TVNav: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var store: Store
    static let tabs: [(String, String, String?)] = [("home", "Start", nil), ("filme", "Filme", nil), ("serien", "Serien", nil),
        ("merkliste", "Merkliste", nil), ("support", "Support", nil), ("suche", "", "magnifyingglass"), ("konto", "", "person.crop.circle")]

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) { BrandMark(size: 34); Text("FilmFrei24").font(.tv(28, .heavy)).foregroundColor(.white); BetaTag(size: 15 / FF.scale) }.padding(.trailing, 26)
            ForEach(TVNav.tabs, id: \.0) { t in
                Button { router.switchTab(t.0) } label: {
                    Group {
                        if let ic = t.2 { Image(systemName: ic).font(.system(size: 26, weight: .semibold)) }
                        else { Text(t.1).font(.tv(26, .semibold)) }
                    }
                    .padding(.horizontal, 20).frame(height: 54)
                }
                .buttonStyle(TVPillStyle(selected: router.tab == t.0))
            }
            Spacer()
        }
        .padding(.horizontal, TVL.side).padding(.top, 34)
        .focusSection()
    }
}

struct TVPillStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View { B(configuration: configuration, selected: selected) }
    struct B: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .foregroundColor(focused ? FF.dark : .white)
                .background(Capsule().fill(focused ? Color.white : selected ? Color.white.opacity(0.18) : Color.clear))
                .scaleEffect(focused ? 1.06 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// Große Knöpfe (Abspielen, Merkliste ...): fokussiert weiß, sonst grau-transparent.
struct TVActionStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View { B(configuration: configuration, primary: primary) }
    struct B: View {
        let configuration: Configuration
        let primary: Bool
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .font(.tv(26, .semibold))
                .foregroundColor(focused ? FF.dark : .white)
                .padding(.horizontal, 30).frame(height: 66)
                .background(RoundedRectangle(cornerRadius: 10).fill(focused ? Color.white : primary ? FF.blue : Color.white.opacity(0.16)))
                .scaleEffect(focused ? 1.06 : (configuration.isPressed ? 0.97 : 1))
                .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 14, y: 8)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

// MARK: - Startseite / Filme / Serien

struct TVHome: View {
    var kind = "home"     // home | filme | serien | merkliste
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @FocusState private var focus: String?
    @State private var heroes: [Item] = []
    @State private var heroIdx = 0
    @State private var shown: Item?
    @State private var focusTask: Task<Void, Never>?

    private var list: [Item] { kind == "filme" ? store.web.films : kind == "serien" ? store.web.series : store.web.all }

    var body: some View {
        let hero = heroes.isEmpty ? nil : heroes[min(heroIdx, heroes.count - 1)]
        let cur = shown ?? hero
        ZStack(alignment: .topLeading) {
            TVBackdrop(item: cur, trailer: cur.flatMap { $0.isSeries ? nil : store.web.trailers[$0.id] })
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 120)
                // Info-Bereich des fokussierten Titels
                VStack(alignment: .leading, spacing: 22) {
                    if let c = cur { TVInfo(it: c) }
                    if let h = hero, shown == nil || shown == h {
                        HStack(spacing: 20) {
                            Button { router.playItem(h) } label: { Label(store.playLabel(h), systemImage: "play.fill") }
                                .buttonStyle(TVActionStyle(primary: true)).focused($focus, equals: "hero.play")
                            Button { router.open(h) } label: { Label("Details", systemImage: "info.circle") }
                                .buttonStyle(TVActionStyle()).focused($focus, equals: "hero.info")
                            if heroes.count > 1 {
                                HStack(spacing: 10) {
                                    ForEach(heroes.indices, id: \.self) { i in
                                        Capsule().fill(i == heroIdx ? Color.white : Color.white.opacity(0.35)).frame(width: i == heroIdx ? 30 : 12, height: 12)
                                    }
                                }.padding(.leading, 30)
                            }
                        }
                        .focusSection()
                        .onMoveCommand { d in
                            guard heroes.count > 1 else { return }
                            if d == .right { heroIdx = (heroIdx + 1) % heroes.count; shown = nil }
                            if d == .left { heroIdx = (heroIdx + heroes.count - 1) % heroes.count; shown = nil }
                        }
                    }
                }
                .padding(.horizontal, TVL.side)
                .frame(height: TVL.infoH, alignment: .bottomLeading)

                ScrollViewReader { sp in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 34) {
                            ForEach(rows(), id: \.0) { r in
                                TVRow(title: r.1, items: r.2, top10: r.3, progress: r.0 == "cont", focus: $focus, rowId: r.0, open: r.0 == "cont" ? router.playItem : router.open)  // 2026-10-23: Weiterschauen direkt in den Player
                            }
                            Color.clear.frame(height: 200)
                        }.padding(.top, 10)
                    }
                    .onChange(of: focus) { f in
                        guard let f, let row = f.split(separator: "|").first, f.contains("|") else { return }
                        withAnimation(.easeInOut(duration: 0.3)) { sp.scrollTo(String(row), anchor: .top) }
                    }
                }
            }
            TVNav()
        }
        .background(FF.bg.ignoresSafeArea())
        .onAppear { if heroes.isEmpty { heroes = heroPick(list, 6) } }
        .onChange(of: store.web.all.count) { _ in if heroes.isEmpty { heroes = heroPick(list, 6) } }
        .onChange(of: focus) { f in
            focusTask?.cancel()
            guard let f else { return }
            if f.hasPrefix("hero.") { shown = nil; return }
            let key = f.split(separator: "|").last.map(String.init) ?? ""
            // kurz warten, damit schnelles Durchscrollen nicht flackert
            focusTask = Task { try? await Task.sleep(nanoseconds: 180_000_000); if !Task.isCancelled, let it = store.web.by[key] { shown = it } }
        }
        .task {
            // nur für automatische Bildschirmfotos (Launch-Argument -ff24focus): erste Karte fokussieren
            if ProcessInfo.processInfo.arguments.contains("-ff24focus") {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if let r = rows().first, let it = r.2.first { focus = r.0 + "|" + it.key }
            }
        }
    }

    /// (id, Titel, Titel, Top-10-Stil)
    private func rows() -> [(String, String, [Item], Bool)] {
        let byAdded: (Item, Item) -> Bool = { $0.added > $1.added }
        let score: (Item) -> Double = { $0.rating * log10(10 + Double($0.votes)) }
        var r: [(String, String, [Item], Bool)] = []
        if kind == "merkliste" {
            let wl = store.wlItems
            return wl.isEmpty ? [] : [("wl", "Meine Merkliste", wl, false)]
        }
        let cont = store.contItems
        if kind == "home" && !cont.isEmpty { r.append(("cont", "Weiterschauen", Array(cont.prefix(20).map { $0.0 }), false)) }
        if kind == "home" && !store.web.top.isEmpty { r.append(("top", "Die Top 10 in Deutschland", store.web.top, true)) }
        let soonL = list.filter { $0.soon == 1 }.sorted(by: byAdded)
        if kind != "merkliste" && !soonL.isEmpty { r.append(("bald", "Bald verfügbar", Array(soonL.prefix(30)), false)) }
        if kind != "serien" { r.append(("neu-f", "Neu bei FilmFrei24", Array(store.web.films.sorted(by: byAdded).prefix(30)), false)) }
        if kind != "filme" { r.append(("neu-s", "Neue Folgen", Array(store.web.series.sorted(by: byAdded).prefix(30)), false)) }
        if kind != "serien" { r.append(("best", "Am besten bewertet", Array(store.web.films.filter { $0.votes > 800 }.sorted { $0.rating > $1.rating }.prefix(30)), false)) }
        var count: [String: Int] = [:]
        for it in list { for g in it.genres { count[g, default: 0] += 1 } }
        for (g, _) in count.filter({ $0.value >= 8 }).sorted(by: { $0.value > $1.value }).prefix(kind == "home" ? 8 : 14) {
            r.append(("g-" + g, g, Array(list.filter { $0.genres.contains(g) }.sorted { score($0) > score($1) }.prefix(30)), false))
        }
        if kind == "home" { r.append(("serien", "Serien", Array(store.web.series.sorted { score($0) > score($1) }.prefix(40)), false)) }
        return r.filter { !$0.2.isEmpty }
    }
}

// MARK: - Detailseite

struct TVDetail: View {
    let it: Item
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @FocusState private var focus: String?
    @State private var seasons: [WebSeason] = []
    @State private var cur = 1
    @State private var report = false

    var body: some View {
        let trailer = it.isSeries ? nil : store.web.trailers[it.id]
        let sim = Array(store.web.all.filter { x in x != it && x.genres.contains { it.genres.contains($0) } }
            .sorted { a, b in a.genres.filter { it.genres.contains($0) }.count > b.genres.filter { it.genres.contains($0) }.count }.prefix(24))
        ZStack(alignment: .topLeading) {
            TVBackdrop(item: it, trailer: trailer, delay: 3)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 22) {
                        TVInfo(it: it)
                        if !it.cast.isEmpty {
                            Text("Mit " + it.cast.prefix(4).joined(separator: ", ")).font(.tv(22)).foregroundColor(FF.text2).lineLimit(1).frame(maxWidth: 900, alignment: .leading)
                        }
                        HStack(spacing: 20) {
                            Button { router.playItem(it) } label: { Label(store.playLabel(it), systemImage: it.soon > 0 ? "clock" : "play.fill") }
                                .buttonStyle(TVActionStyle(primary: it.soon == 0)).focused($focus, equals: "play")
                            // 2026-10-23 User: „Von vorne“ auf allen Fernsehern, Filme und Serien (nur wenn angefangen)
                            if it.soon == 0, let p = (it.isSeries ? store.last(it) : store.progress[it.id]), p.pct > 0, p.pct < 95, p.pos > 10 {
                                Button { router.playFromStart(it) } label: { Label("Von vorne", systemImage: "arrow.counterclockwise") }.buttonStyle(TVActionStyle())
                            }
                            if let t = trailer {
                                Button { router.trailer(it, t) } label: { Label("Trailer", systemImage: "film") }.buttonStyle(TVActionStyle())
                            }
                            Button { Task { _ = await store.toggleWatchlist(it) } } label: {
                                Label(store.inList(it) ? "Gemerkt" : "Merkliste", systemImage: store.inList(it) ? "checkmark" : "plus")
                            }.buttonStyle(TVActionStyle())
                            Button { report = true } label: { Label("Melden", systemImage: "flag") }.buttonStyle(TVActionStyle())
                        }
                        .padding(.top, 8)
                        .focusSection()
                    }
                    .padding(.horizontal, TVL.side).padding(.top, 150)
                    .frame(minHeight: 700, alignment: .bottomLeading)

                    if it.isSeries && !seasons.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Staffeln und Folgen").font(.tv(30, .bold)).foregroundColor(.white).padding(.leading, TVL.side)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(seasons) { s in
                                        Button { cur = s.n } label: { Text("Staffel \(s.n)").font(.tv(24, .semibold)).padding(.horizontal, 22).frame(height: 52) }
                                            .buttonStyle(TVPillStyle(selected: cur == s.n))
                                    }
                                }.padding(.horizontal, TVL.side).padding(.vertical, 10)
                            }.focusSection()
                            let se = seasons.first { $0.n == cur } ?? seasons[0]
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 26) {
                                    ForEach(se.episodes.filter(\.ok)) { e in
                                        VStack(alignment: .leading, spacing: 10) {
                                            Button { router.playEpisode(it.id, se.n, e.n, start: -1) } label: {
                                                ZStack(alignment: .bottomLeading) {
                                                    Color(hex: 0x141A21)
                                                    Img(url: e.thumb, fallback: it.card)
                                                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                                                    Image(systemName: "play.fill").font(.system(size: 26)).foregroundColor(.white).padding(14)
                                                }.frame(width: TVL.cardW, height: TVL.cardH)
                                            }.buttonStyle(TVFocusStyle())
                                            Text("\(e.n). " + (e.title.isEmpty ? "Folge \(e.n)" : e.title)).font(.tv(23, .semibold)).foregroundColor(.white).lineLimit(1)
                                            Text([e.min > 0 ? "\(e.min) Min." : "", e.desc].filter { !$0.isEmpty }.joined(separator: " · "))
                                                .font(.tv(19)).foregroundColor(FF.text2).lineLimit(2)
                                        }.frame(width: TVL.cardW)
                                    }
                                }.padding(.horizontal, TVL.side).padding(.vertical, 24)
                            }.focusSection()
                        }.padding(.top, 30)
                    }
                    if !sim.isEmpty {
                        TVRow(title: "Das könnte dir auch gefallen", items: sim, focus: $focus, rowId: "sim", open: router.open).padding(.top, 34)
                    }
                    // 2026-10-22: „Weitere Informationen“ wie Prime (fokussierbar, damit die Fernbedienung bis hierher scrollt)
                    Button {} label: { tvInfo }.buttonStyle(TVInfoStyle()).focused($focus, equals: "info")
                        .padding(.horizontal, TVL.side - 16).padding(.top, 40)
                    Color.clear.frame(height: 160)
                }
            }
        }
        .background(FF.bg.ignoresSafeArea())
        .task(id: it.key) {
            if it.isSeries {
                seasons = await store.seasons(it.id)
                if let p = store.last(it), let s = p.season, seasons.contains(where: { $0.n == s }) { cur = s } else { cur = seasons.first?.n ?? 1 }
            }
            focus = "play"
        }
        .sheet(isPresented: $report) { ReportSheet(title: it.title, url: titleURL(it), pos: 0) }
    }

    private var tvInfo: some View {
        var rows: [(String, String)] = []
        if !it.genres.isEmpty { rows.append(("Genre", it.genres.joined(separator: ", "))) }
        if !it.cast.isEmpty { rows.append(("Besetzung", it.cast.prefix(8).joined(separator: ", "))) }
        rows.append((it.isSeries ? "Jahre" : "Jahr", it.year + (!it.endYear.isEmpty && it.endYear != it.year ? "–" + it.endYear : "")))
        if it.isSeries { rows.append(("Umfang", "\(it.seasons) Staffeln · \(it.episodes) Folgen")) } else if it.min > 0 { rows.append(("Laufzeit", mfmt(it.min))) }
        if it.rating > 0 { rows.append(("Bewertung", fmt1(it.rating) + " / 10")) }
        if !it.tagline.isEmpty { rows.append(("Slogan", it.tagline)) }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Weitere Informationen").font(.tv(31, .bold)).foregroundColor(.white).padding(.bottom, 6)
            ForEach(rows.filter { !$0.1.isEmpty }, id: \.0) { k, v in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k).font(.tv(23, .bold)).foregroundColor(.white)
                    Text(v).font(.tv(23)).foregroundColor(FF.text2).lineLimit(3)
                }
            }
        }.frame(maxWidth: 1400, alignment: .leading).padding(16)
    }
}

/// Info-Block: beim Fokus nur leicht hinterlegt (kein Zoom).
struct TVInfoStyle: ButtonStyle {
    @Environment(\.isFocused) var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(focused ? 0.08 : 0)))
    }
}
#endif
