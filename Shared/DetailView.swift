import SwiftUI

/// pageDetail() – Handy-Ansicht der Website; auf dem Fernseher breiter.
struct DetailView: View {
    let key: String
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var seasons: [WebSeason]? = nil
    @State private var cur = 1
    @State private var tab = 0
    @State private var seasonPick = false
    @State private var report = false
    @State private var solid = false

    var body: some View {
        if let it = store.web.by[key] {
            #if os(tvOS)
            TVDetail(it: it)
            #else
            content(it)
            #endif
        }
        else { VStack { SubHead(title: ""); if store.web.isEmpty { Loading() } else { EmptyState(title: "", text: "Titel nicht gefunden.") }; Spacer() }.background(FF.bg.ignoresSafeArea()) }
    }

    @ViewBuilder func content(_ it: Item) -> some View {
        let trailer = it.isSeries ? nil : store.web.trailers[it.id]
        let sim = Array(store.web.all.filter { x in x != it && x.genres.contains { it.genres.contains($0) } }
            .sorted { a, b in
                let ca = a.genres.filter { it.genres.contains($0) }.count, cb = b.genres.filter { it.genres.contains($0) }.count
                return ca != cb ? ca > cb : score(a) > score(b)
            }.prefix(24))
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Bild mit Logo
                    ZStack(alignment: .bottomLeading) {
                        Img(url: it.hero.isEmpty ? it.card : it.hero, fallback: it.poster)
                        LinearGradient(stops: [.init(color: .clear, location: 0.45), .init(color: FF.bg.opacity(0.35), location: 0.7), .init(color: FF.bg, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                        LogoOrTitle(it: it, size: 28).frame(maxWidth: 300 * FF.scale, maxHeight: 76 * FF.scale, alignment: .bottomLeading)
                            .shadow(color: .black.opacity(0.7), radius: 10, y: 2).padding(.leading, FF.pad).padding(.bottom, 12)
                    }
                    .aspectRatio(FF.scale > 1 ? 16 / 7 : 16 / 10.5, contentMode: .fit).clipped()
                    .padding(.top, FF.scale > 1 ? 0 : 60)
                    .background(GeometryReader { g in Color.clear.preference(key: OffKey.self, value: g.frame(in: .named("d")).minY) })

                    VStack(alignment: .leading, spacing: 0) {
                        let b = store.web.badge(it), r = store.web.rank(it)
                        if (!b.isEmpty && b != "TOP 10") || r >= 0 {
                            HStack(spacing: 12) {
                                if !b.isEmpty && b != "TOP 10" { Pill(text: b, bg: .white, fg: FF.dark) }
                                if r >= 0 { Text("Nr. \(r + 1) in Deutschland").font(.inter(15, .bold)).foregroundColor(FF.green) }
                            }.padding(.bottom, 14)
                        }
                        if it.isSeries, let ss = seasons, !ss.isEmpty {
                            Button { seasonPick = true } label: {
                                HStack(spacing: 10) { Text("Staffel \(cur)").font(.inter(18, .semibold)); Image(systemName: "chevron.down") }
                                    .foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 11).background(RoundedRectangle(cornerRadius: 8).fill(FF.btn))
                            }.buttonStyle(FocusStyle()).padding(.bottom, 18)
                        }
                        Cta(label: store.playLabel(it)) { router.playItem(it) }.frame(maxWidth: FF.scale > 1 ? 600 : .infinity)
                        HStack(spacing: 0) {
                            iconAction(store.inList(it) ? "checkmark" : "plus", store.inList(it) ? "Gemerkt" : "Merkliste") {
                                if store.user == nil { router.go(.login(register: false)); return }
                                Task {
                                    let r = await store.toggleWatchlist(it)
                                    router.toast = r == nil ? "Merkliste konnte nicht gespeichert werden" : (r! ? "Zur Merkliste hinzugefügt" : "Von der Merkliste entfernt")
                                }
                            }
                            if let trailer { iconAction("play.rectangle", "Trailer") { router.trailer(it, trailer) } }
                            #if !os(tvOS)
                            ShareLink(item: URL(string: titleURL(it))!, subject: Text(it.title), message: Text("\(it.title) auf FilmFrei24")) {
                                iconLabel("square.and.arrow.up", "Teilen")
                            }.frame(maxWidth: 100).frame(maxWidth: .infinity)
                            #endif
                            iconAction("flag", "Melden") { report = true }
                        }.padding(.top, 22).padding(.bottom, 6).frame(maxWidth: FF.scale > 1 ? 600 : .infinity)
                        if !it.desc.isEmpty {
                            Text(it.desc).font(.inter(17)).foregroundColor(.white).lineSpacing(5).lineLimit(FF.scale > 1 ? 4 : 3)
                                .padding(.top, 20).padding(.bottom, 18).frame(maxWidth: 1200, alignment: .leading)
                        }
                        HStack(spacing: 10) {
                            ForEach(Array(it.genres.prefix(3).enumerated()), id: \.offset) { i, g in
                                if i > 0 { Text("•").foregroundColor(FF.meta.opacity(0.6)) }
                                Text(g).foregroundColor(FF.meta)
                            }
                        }.font(.inter(16, .medium))
                        HStack(spacing: 10) {
                            if it.rating > 0 { HStack(spacing: 4) { Image(systemName: "star.fill").foregroundColor(FF.yellow).font(.system(size: 13 * FF.scale)); Text(fmt1(it.rating)) } }
                            if !it.year.isEmpty { Text(it.year) }
                            let len = it.isSeries ? seasonsText(it.seasons) : mfmt(it.min)
                            if !len.isEmpty { Text(len) }
                            if !it.isSeries && !it.quality.isEmpty {
                                Text(it.quality.lowercased().contains("sd") ? "SD" : "HD").font(.inter(12, .bold)).padding(.horizontal, 4)
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(FF.meta.opacity(0.75)))
                            }
                        }.font(.inter(16, .medium)).foregroundColor(FF.meta).padding(.top, 10)
                    }.padding(.horizontal, FF.pad).padding(.top, 10)

                    // Reiter
                    let okCount = seasons?.first { $0.n == cur }?.episodes.filter(\.ok).count ?? 0
                    let labels = it.isSeries ? ["Folgen" + (seasons != nil ? " (\(okCount))" : ""), "Weitere Informationen"] : ["Weitere Informationen"]
                    Tabs(labels: labels, sel: $tab).padding(.top, 30)
                    if it.isSeries && tab == 0 { episodes(it) } else { info(it) }

                    PosterRow(title: "Das könnte dir auch gefallen", items: sim, open: router.open).padding(.top, 26)
                }.padding(.bottom, 120)
            }
            .coordinateSpace(name: "d")
            .onPreferenceChange(OffKey.self) { y in solid = y < -160 }

            #if !os(tvOS)
            HStack(spacing: 12) {
                BackButton()
                Text(it.title).font(.inter(18, .bold)).foregroundColor(solid ? .white : .clear).lineLimit(1).frame(maxWidth: .infinity)
                Color.clear.frame(width: 44, height: 44)
            }.padding(.horizontal, 16).padding(.vertical, 8).background(solid ? FF.bg.opacity(0.96) : .clear).animation(.easeOut(duration: 0.2), value: solid)
            #endif
        }
        .background(FF.bg.ignoresSafeArea())
        .task(id: it.key) {
            guard it.isSeries else { return }
            let ss = await store.seasons(it.id)
            seasons = ss
            let want = store.last(it)?.season ?? ss.first?.n ?? 1
            cur = ss.contains { $0.n == want } ? want : (ss.first?.n ?? 1)
        }
        .confirmationDialog(it.title, isPresented: $seasonPick, titleVisibility: .visible) {
            ForEach(seasons ?? []) { s in Button("Staffel \(s.n)") { cur = s.n; tab = 0 } }
        }
        .sheet(isPresented: $report) { ReportSheet(title: it.title, url: titleURL(it), pos: 0) }
    }

    @ViewBuilder func episodes(_ it: Item) -> some View {
        if let ss = seasons, let se = ss.first(where: { $0.n == cur }) ?? ss.first {
            VStack(spacing: 4) {
                ForEach(se.episodes) { e in
                    let pp = store.progress[episodeSlug(it.id, se.n, e.n)]
                    Button {
                        if e.ok { router.playEpisode(it.id, se.n, e.n, start: (pp != nil && pp!.pct < 95) ? pp!.pos : 0) }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "play.fill").font(.system(size: 15 * FF.scale)).foregroundColor(FF.dark).offset(x: 1)
                                .frame(width: 34 * FF.scale, height: 34 * FF.scale).background(Circle().fill(e.ok ? Color.white : Color.white.opacity(0.4)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Folge \(e.n)").font(.inter(18, .medium)).foregroundColor(e.ok ? .white : .white.opacity(0.4))
                                Text(e.title + (e.ok ? "" : " · Bald verfügbar")).font(.inter(15)).foregroundColor(FF.rowTitle.opacity(e.ok ? 1 : 0.4)).lineLimit(1)
                                if let pp { ProgressLine(pct: pp.pct, height: 3).clipShape(Capsule()).padding(.top, 6) }
                            }
                            Spacer()
                        }.padding(16).frame(maxWidth: .infinity).background(FF.box)
                    }.buttonStyle(FocusStyle()).disabled(!e.ok)
                }
            }
        } else {
            VStack(spacing: 4) { ForEach(0..<3, id: \.self) { _ in FF.skel.frame(height: 66) } }.padding(16)
        }
    }

    func info(_ it: Item) -> some View {
        var rows: [(String, String)] = [("Genres", it.genres.joined(separator: ", ")),
                                        (it.isSeries ? "Jahre" : "Jahr", it.year + (!it.endYear.isEmpty && it.endYear != it.year ? "–" + it.endYear : ""))]
        if it.isSeries { rows.append(("Umfang", "\(it.seasons) Staffeln · \(it.episodes) Folgen")) }
        else { rows.append(("Laufzeit", mfmt(it.min))); rows.append(("Qualität", it.quality.isEmpty ? "HD" : it.quality)) }
        if it.rating > 0 {
            let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "de_DE")
            rows.append(("Bewertung", "\(fmt1(it.rating)) / 10 (\(f.string(from: NSNumber(value: it.votes)) ?? "") Stimmen)"))
        }
        if !it.cast.isEmpty { rows.append(("Besetzung", it.cast.joined(separator: ", "))) }
        if !it.tagline.isEmpty { rows.append(("Slogan", it.tagline)) }
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(rows, id: \.0) { k, v in
                HStack(alignment: .top, spacing: 0) {
                    Text(k).font(.inter(16, .semibold)).foregroundColor(FF.text2).frame(width: 110 * FF.scale, alignment: .leading)
                    Text(v).font(.inter(16)).foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.padding(FF.pad)
    }

    func iconLabel(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 24 * FF.scale)).frame(height: 28 * FF.scale)
            Text(label).font(.inter(15))
        }.foregroundColor(.white)
    }
    func iconAction(_ icon: String, _ label: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { iconLabel(icon, label).frame(maxWidth: 100).padding(.vertical, 4) }.buttonStyle(FocusStyle()).frame(maxWidth: .infinity)
    }
}

private struct OffKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Problem melden (wie Website, auch aus dem Player)

let REPORT_TYPES = ["Kein Bild / schwarzer Screen", "Kein Ton", "Video stockt / lädt nicht", "Falsche Sprache", "Falscher Film",
                    "Update anfordern (z.B. Bildfehler, deutsche Forced Untertitel fehlen)", "Sonstiges"]

struct ReportSheet: View {
    let title: String
    let url: String
    let pos: Double
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var router: Router
    @State private var type = REPORT_TYPES[0]
    @State private var tc = ""
    @State private var msg = ""
    @State private var busy = false
    @State private var err: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Problem melden").font(.inter(22, .bold)).foregroundColor(.white)
                Text(title).font(.inter(15)).foregroundColor(FF.text2).padding(.top, 8).padding(.bottom, 14)
                Label2("Was ist los?")
                Menu { ForEach(REPORT_TYPES, id: \.self) { t in Button(t) { type = t } } } label: {
                    HStack { Text(type).lineLimit(1); Spacer(); Image(systemName: "chevron.down") }.font(.inter(16)).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 12).background(RoundedRectangle(cornerRadius: 8).fill(FF.field))
                }
                if type == REPORT_TYPES[2] { Label2("An welcher Stelle? (Minute:Sekunde)"); Field(placeholder: "z.B. 12:34", text: $tc) }
                Label2("Weitere Details (optional)")
                Field(placeholder: "", text: $msg, multiline: true)
                if let err { Text(err).foregroundColor(Color(hex: 0xFF8A8D)).padding(.top, 10) }
                GreyButton(label: busy ? "Wird gesendet …" : "Absenden", white: true, full: true) { send() }.padding(.top, 14)
            }.padding(20)
        }
        .background(FF.sheet.ignoresSafeArea())
        .onAppear { if pos > 0 { tc = String(format: "%d:%02d", Int(pos) / 60, Int(pos) % 60) } }
    }

    func send() {
        guard !busy else { return }
        if type == REPORT_TYPES[2] && tc.range(of: #"^\d{1,2}(:\d{1,2}){1,2}$"#, options: .regularExpression) == nil { err = "Bitte die Stelle angeben, z.B. 12:34"; return }
        busy = true
        Task {
            let d = await API.postObj("/api/report.php", ["film": title, "type": type, "msg": msg.trimmingCharacters(in: .whitespacesAndNewlines),
                                                         "url": url, "time_code": type == REPORT_TYPES[2] ? tc : ""])
            busy = false
            if d.b("ok") { router.toast = "Danke! Deine Meldung ist beim Support eingegangen."; dismiss() }
            else { err = d.s("error").isEmpty ? "Senden fehlgeschlagen" : d.s("error") }
        }
    }
}
