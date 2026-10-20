import SwiftUI

/// Startseite: Kopf mit Chips, Hero, Reihen in Website-Reihenfolge.
struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var heroes: [Item] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                #if !os(tvOS)
                MobileHead()
                #endif
                if store.web.isEmpty {
                    if let e = store.error { EmptyState(title: "Keine Verbindung", text: e) { GreyButton(label: "Erneut versuchen", white: true) { Task { await store.refresh() } } } }
                    else { Loading() }
                } else {
                    Hero(list: heroes, open: router.open, play: router.playItem)
                    let cont = store.contItems
                    if !cont.isEmpty {
                        ContinueRow(items: Array(cont.prefix(20)), more: { router.go(.cont) }, play: router.playItem, menu: { router.menuFor = $0 })
                    }
                    PosterRow(title: "Meine Merkliste", items: Array(store.wlItems.prefix(30)), more: { router.switchTab("konto") }, open: router.open)
                    TopRow(items: store.web.top, open: router.open)
                    PosterRow(title: "Neu bei FilmFrei24", items: Array(store.web.films.sorted(by: byAdded).prefix(30)), more: { router.list("filme", s: "neu") }, open: router.open)
                    PosterRow(title: "Neue Folgen", items: Array(store.web.series.sorted(by: byAdded).prefix(30)), more: { router.list("serien", s: "neu") }, open: router.open)
                    PosterRow(title: "Am besten bewertet", items: Array(store.web.films.filter { $0.votes > 800 }.sorted { $0.rating > $1.rating }.prefix(30)),
                              more: { router.list("filme", s: "bewertung") }, open: router.open)
                    ForEach(genreRows(store.web.films, max: 8), id: \.0) { g, l in
                        PosterRow(title: g, items: l, more: { router.list("filme", g: g) }, open: router.open)
                    }
                    PosterRow(title: "Serien", items: store.web.series.sorted(by: byScore), more: { router.route("serien") }, open: router.open)
                }
            }.padding(.bottom, 110)
        }
        .background(FF.bg.ignoresSafeArea())
        .refreshable { await store.refresh() }
        .onAppear { if heroes.isEmpty { heroes = heroPick(store.web.all, 6) } }
        .onChange(of: store.web.all.count) { _ in if heroes.isEmpty || heroes.allSatisfy({ store.web.by[$0.key] == nil }) { heroes = heroPick(store.web.all, 6) } }
    }
}

/// mhead(): Logo + Anmelden, darunter Chips.
struct MobileHead: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Brand()
                Spacer()
                if store.user == nil { BlueButton(label: "Anmelden") { router.go(.login(register: false)) } }
            }.frame(height: 44).padding(.horizontal, FF.pad).padding(.top, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ChipButton(label: "Filme", on: false) { router.route("filme") }
                    ChipButton(label: "Serien", on: false) { router.route("serien") }
                    if store.user != nil && !store.contItems.isEmpty { ChipButton(label: "Weiterschauen", on: false) { router.route("weiterschauen") } }
                    ChipButton(label: "Wünsche", on: false) { router.route("wuensche") }
                    ChipButton(label: "Support", on: false) { router.route("support") }
                }.padding(.horizontal, FF.pad).padding(.top, 10).padding(.bottom, 14)
            }
        }
    }
}

/// ⋮ bei Weiterschauen
struct ContinueMenu: View {
    let it: Item
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) var dismiss
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(it.title).font(.inter(22, .bold)).foregroundColor(.white).padding(.bottom, 16)
            opt("play.fill", store.playLabel(it)) { dismiss(); router.playItem(it) }
            opt("info.circle", "Details ansehen") { dismiss(); router.open(it) }
            opt("xmark", "Aus Weiterschauen entfernen") { if it.isSeries { confirm = true } else { store.removeCont(it); dismiss() } }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 22).frame(maxWidth: .infinity, alignment: .leading)
        .background(FF.sheet.ignoresSafeArea())
        .alert("Aus Weiterschauen entfernen?", isPresented: $confirm) {
            Button("Entfernen", role: .destructive) { store.removeCont(it); dismiss() }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Der Fortschritt aller Folgen von „\(it.title)“ wird gelöscht.") }
    }
    func opt(_ icon: String, _ label: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            HStack(spacing: 14) { Image(systemName: icon).frame(width: 22); Text(label).font(.inter(18)) }.foregroundColor(.white).padding(.vertical, 13)
        }.buttonStyle(PressStyle())
    }
}

private let SORTS = [("bewertung", "Beliebt"), ("neu", "Neu hinzugefügt"), ("jahr", "Erscheinungsjahr"), ("az", "A–Z")]

/// Filme/Serien: ohne g/s Übersicht (Hero + Reihen), sonst Raster mit Sortierung + Genre-Chips.
struct ListView: View {
    let kind: String
    let g: String
    let s: String
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var heroes: [Item] = []
    @State private var genre: String = ""
    @State private var sort: String = ""

    var list: [Item] { kind == "filme" ? store.web.films : store.web.series }
    var label: String { kind == "filme" ? "Filme" : "Serien" }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if genre.isEmpty && sort.isEmpty { overview } else { grid }
            }.padding(.bottom, 110)
        }
        .background(FF.bg.ignoresSafeArea())
        .onAppear { if genre.isEmpty && sort.isEmpty { genre = g; sort = s }; if heroes.isEmpty { heroes = heroPick(list, 5) } }
    }

    @ViewBuilder var overview: some View {
        #if !os(tvOS)
        SubHead(title: label)
        #endif
        Menu {
            ForEach(genresOf(list), id: \.self) { x in Button(x) { genre = x; sort = "bewertung" } }
        } label: { selLabel("Alle Kategorien") }
            .padding(.horizontal, FF.pad).padding(.top, 4).padding(.bottom, 14)
        if list.isEmpty { Loading() }
        Hero(list: heroes, open: router.open, play: router.playItem)
        PosterRow(title: kind == "filme" ? "Neue Filme" : "Neue Folgen", items: Array(list.sorted(by: byAdded).prefix(30)), more: { sort = "neu" }, open: router.open)
        PosterRow(title: "Beliebt", items: Array(list.sorted(by: byScore).prefix(30)), more: { sort = "bewertung" }, open: router.open)
        ForEach(genreRows(list, max: 14), id: \.0) { gg, l in PosterRow(title: gg, items: l, more: { genre = gg; sort = "bewertung" }, open: router.open) }
    }

    @ViewBuilder var grid: some View {
        let srt = sort.isEmpty ? "bewertung" : sort
        let base = genre.isEmpty ? list : list.filter { $0.genres.contains(genre) }
        let items: [Item] = {
            switch srt {
            case "neu": return base.sorted(by: byAdded)
            case "az": return base.sorted { $0.title.compare($1.title, locale: Locale(identifier: "de")) == .orderedAscending }
            case "jahr": return base.sorted { $0.year > $1.year }
            default: return base.sorted(by: byScore)
            }
        }()
        HStack {
            #if !os(tvOS)
            BackButton()
            #endif
            Text(label + (genre.isEmpty ? "" : " · \(genre)")).font(.inter(24, .bold)).foregroundColor(.white).lineLimit(1)
            Spacer()
            Menu { ForEach(SORTS, id: \.0) { v, l in Button(l) { sort = v } } } label: { selLabel(SORTS.first { $0.0 == srt }?.1 ?? "Beliebt") }
        }.padding(.horizontal, FF.pad).padding(.top, 10).padding(.bottom, 16)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChipButton(label: "Alle", on: genre.isEmpty, dark: false) { genre = ""; if sort.isEmpty { sort = "bewertung" } }
                ForEach(genresOf(list), id: \.self) { x in ChipButton(label: x, on: x == genre, dark: false) { genre = x } }
            }.padding(.horizontal, FF.pad).padding(.bottom, 16).padding(.vertical, FF.scale > 1 ? 20 : 0)
        }
        if items.isEmpty { EmptyState(title: "", text: "Keine Titel gefunden.") }
        PosterGrid(items: items, open: router.open)
    }

    func selLabel(_ t: String) -> some View {
        HStack(spacing: 10) { Text(t).font(.inter(16, .bold)); Image(systemName: "chevron.down").font(.system(size: 14 * FF.scale, weight: .bold)) }
            .foregroundColor(.white).padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 8).fill(FF.btn))
    }
}

struct ContinueView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    var body: some View {
        let cont = store.contItems
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SubHead(title: "Weiterschauen")
                if cont.isEmpty { EmptyState(title: "", text: store.user != nil ? "Du hast noch nichts angefangen." : "Melde dich an, um weiterzuschauen.") }
                PosterGrid(items: cont.map(\.0), land: true, pctOf: { it in cont.first { $0.0 == it }?.1.pct ?? 0 }, open: router.playItem)
            }.padding(.bottom, 110)
        }.background(FF.bg.ignoresSafeArea())
    }
}
