import SwiftUI
import UIKit
#if os(iOS)
import PhotosUI
#endif
#if os(tvOS)
import CoreImage.CIFilterBuiltins
#endif

/// .seg – Umschalter
struct Seg: View {
    let options: [(String, String)]
    @Binding var value: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { v, l in
                Button { value = v } label: {
                    Text(l).font(.inter(15, .semibold)).foregroundColor(v == value ? FF.dark : Color(hex: 0xCFD3D8)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 14).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 6).fill(v == value ? Color.white : .clear))
                }.buttonStyle(FocusStyle())
            }
        }.padding(4).background(RoundedRectangle(cornerRadius: 8).fill(FF.field))
    }
}

// MARK: - Wünsche (TMDB-Suche, Gratis-Kontingent, Warenkorb + Stripe)

struct WishesView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.scenePhase) var phase
    @AppStorage("wish_cart") private var cartRaw = "[]"
    @AppStorage("wish_guest") private var guestId = ""
    @State private var ctx: J? = nil
    @State private var list: [J] = []
    @State private var failed = false
    @State private var type = "movie"
    @State private var q = ""
    @State private var results: [J]? = nil
    @State private var filter = "pending"
    @State private var busyId: Int? = nil
    @State private var cartOpen = false
    @State private var altInfo = ""
    @State private var payErr = ""
    @State private var paying = false
    @State private var payURL: String? = nil       // Apple TV: QR-Code zum Bezahlen am Handy

    var cart: [J] { ((try? JSONSerialization.jsonObject(with: Data(cartRaw.utf8))) as? [J]) ?? [] }
    func saveCart(_ c: [J]) { cartRaw = String(data: (try? JSONSerialization.data(withJSONObject: c)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]" }
    var guest: String {
        if guestId.isEmpty { guestId = "g" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + UUID().uuidString.prefix(6).lowercased() }
        return guestId
    }

    func quotaLeft(_ t: String) -> Int {
        guard let c = ctx else { return 0 }
        if t == "tv" && !c.b("seriesFree") { return 0 }
        if c.b("freeWisher") { return Int.max }
        if !c.b("loggedIn") { return 0 }
        let qq = c.o("quota"), used = qq?.o("used")
        return max(0, (qq?.i("limit") ?? 0) - ((used?.i("movie") ?? 0) + (used?.i("tv") ?? 0)))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SubHead(title: "Wünsche", back: false)
                    VStack(alignment: .leading, spacing: 0) { content }.padding(.horizontal, FF.pad)
                }.padding(.bottom, cart.isEmpty ? 110 : 180)
            }
            if !cart.isEmpty {
                HStack(spacing: 14) {
                    Text("\(cart.count) Titel · " + eur(cart.reduce(0) { $0 + ($1.d("price") ?? 1) })).font(.inter(15, .bold)).foregroundColor(FF.dark)
                    Button { cartOpen = true } label: {
                        Text("Warenkorb").font(.inter(15, .bold)).foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 9).background(RoundedRectangle(cornerRadius: 8).fill(FF.dark))
                    }.buttonStyle(FocusStyle())
                }.padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 10).background(Capsule().fill(Color.white)).shadow(color: .black.opacity(0.5), radius: 15, y: 10)
                    .padding(.bottom, FF.scale > 1 ? 40 : 84)
            }
        }
        .background(FF.bg.ignoresSafeArea())
        .task(id: store.user?.id) { await load() }
        .onChange(of: phase) { p in if p == .active { Task { await load() } } }   // zurück von Stripe
        .task(id: q + type) {
            let qq = q.trimmingCharacters(in: .whitespaces)
            guard qq.count >= 2 else { results = nil; return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            results = await API.getObj("/api/tmdb.php?q=" + API.enc(qq) + "&type=" + type).a("results").filter { ["de", "en", ""].contains($0.s("original_language")) }
        }
        .sheet(isPresented: $cartOpen) { cartSheet }
        .alert("Danke! Wir prüfen deine Zahlung", isPresented: Binding(get: { !altInfo.isEmpty }, set: { if !$0 { altInfo = "" } })) {
            Button("OK") { altInfo = "" }
        } message: { Text(altInfo) }
        #if os(tvOS)
        .fullScreenCover(item: Binding(get: { payURL.map { QRPay(url: $0) } }, set: { payURL = $0?.url })) { QRPayView(url: $0.url) }
        #endif
    }

    func load() async {
        let c = await API.getObj("/beta/api.php?q=wishctx")
        guard c.b("ok") else { failed = true; return }
        ctx = c; failed = false
        list = await API.getObj("/api/wishlist.php?action=list").a("items")
    }

    @ViewBuilder var content: some View {
        if let c = ctx {
            if !c.s("closed").isEmpty {
                Text(c.s("closed")).font(.inter(16, .bold)).foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xE5484D, alpha: 0.12))).padding(.bottom, 18)
            }
            BoxCard(title: "Film oder Serie wünschen") {
                let left = quotaLeft("movie")
                Text("Was dir fehlt, holen wir ins Programm. " + (c.b("freeWisher") ? "Als Unterstützer wünschst du Filme kostenlos."
                    : (c.b("loggedIn") && left > 0) ? "Du hast noch \(left) kostenlose Wünsche diesen Monat."
                    : "Ein Film kostet \(eur(c.d("price") ?? 1)), eine Serie je nach Umfang ab 2 €."))
                    .font(.inter(15)).foregroundColor(Color(hex: 0xCFD3D8)).padding(.bottom, 14)
                Seg(options: [("movie", "Film"), ("tv", "Serie")], value: $type)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundColor(Color(hex: 0xCFD3D8))
                    TextField("", text: $q, prompt: Text("Titel suchen …").foregroundColor(FF.text2)).font(.inter(16)).foregroundColor(.white)
                        #if !os(tvOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                }.padding(.horizontal, 14).frame(height: 52 * FF.scale).background(RoundedRectangle(cornerRadius: 8).fill(FF.field)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white)).padding(.top, 12)
                if let res = results {
                    if res.isEmpty { Text("Keine Ergebnisse gefunden.").foregroundColor(FF.text2).padding(.top, 16) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: FF.scale > 1 ? 6 : 3), spacing: 14) {
                        ForEach(res.prefix(18).indices, id: \.self) { i in result(res[i], c) }
                    }.padding(.top, 16)
                } else if q.count >= 2 { Text("Suche …").foregroundColor(FF.text2).padding(.top, 16) }
            }
            BoxCard(title: "Wunschliste") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([("pending", "Ausstehend"), ("in_progress", "In Bearbeitung"), ("fulfilled", "Erfüllt"), ("unavailable", "Nicht erfüllbar"), ("mine", "Meine")], id: \.0) { f, l in
                            ChipButton(label: l, on: f == filter, dark: false) { filter = f }
                        }
                    }.padding(.bottom, 14).padding(.vertical, FF.scale > 1 ? 16 : 0)
                }
                let me = c.b("loggedIn") ? c.s("userId") : "guest_" + guest
                let items = filter == "mine" ? list.filter { $0.s("user_id") == me } : list.filter { ($0.s("status").isEmpty ? "pending" : $0.s("status")) == filter }
                if items.isEmpty { Text("Keine Wünsche in dieser Liste.").foregroundColor(FF.text2) }
                VStack(spacing: 10) {
                    ForEach(items.prefix(120).indices, id: \.self) { i in
                        let w = items[i], st = wishStatus(w.s("status"))
                        WishRow(poster: w.s("poster"), title: w.s("title"), sub: [w.s("year"), w.s("type") == "tv" ? "Serie" : "Film", w.s("user_name")].filter { !$0.isEmpty }.joined(separator: " · "), note: w.s("note")) {
                            Pill(text: st.0, bg: st.1, fg: st.2)
                        }
                    }
                }
            }
        } else if failed {
            EmptyState(title: "", text: "Wünsche konnten nicht geladen werden.") { GreyButton(label: "Erneut versuchen") { Task { await load() } } }
        } else { FF.skel.frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 12)) }
    }

    @ViewBuilder func result(_ r: J, _ c: J) -> some View {
        let id = r.i("id") ?? 0, t = r.s("type")
        let slug = t == "movie" ? (c.o("filmsInCatalog")?.s("\(id)") ?? "") : ""
        let inSer = t == "tv" ? (c.o("seriesInCatalog")?.s("\(id)") ?? "") : ""
        let ex = list.first { $0.i("tmdb_id") == id && $0.s("type") == t && $0.s("status") != "fulfilled" }
        let inCart = cart.contains { $0.i("tmdb_id") == id && $0.s("type") == t }
        let price = r.d("price")
        let left = quotaLeft(t)
        let item: J = ["tmdb_id": id, "type": t, "title": r.s("title"), "year": r.s("year"), "poster": r.s("poster"), "original_language": r.s("original_language"),
                       "price": price ?? c.d("price") ?? 1, "price_tier": r.s("price_tier").isEmpty ? "normal" : r.s("price_tier"), "size_label": r.s("size_label")]
        let (label, kind, act): (String, Int, () -> Void) = {
            if !slug.isEmpty { return ("Ansehen", 1, { if let it = store.web.by["f:\(slug)"] { router.open(it) } }) }
            if !inSer.isEmpty { return ("Schon da", 1, { if let it = store.web.by["s:\(inSer)"] { router.open(it) } }) }
            if let ex { return (wishStatus(ex.s("status")).0, 0, {}) }
            if inCart { return ("✓ Im Warenkorb", 0, {}) }
            if !c.s("closed").isEmpty { return ("Geschlossen", 0, {}) }
            if left == Int.max { return ("Wünschen", 1, { wishFree(item, id) }) }
            if left > 0 { return ("Kostenlos wünschen", 1, { wishFree(item, id) }) }
            if price == nil && t == "tv" { return ("Preis nicht verfügbar", 0, {}) }
            return ((r.s("price_tier") == "lottery" ? "Glücksfund " : "") + "In Warenkorb · " + eur(price ?? c.d("price") ?? 1), 2, {
                saveCart(cart + [item]); router.toast = "In den Warenkorb gelegt · " + eur(price ?? 1)
            })
        }()
        VStack(alignment: .leading, spacing: 2) {
            ZStack { FF.surface; if !r.s("poster").isEmpty { Img(url: imgProxy(r.s("poster"), 342)) } }.aspectRatio(2 / 3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8))
            Text(r.s("title")).font(.inter(14, .bold)).foregroundColor(.white).lineLimit(2).padding(.top, 8)
            Text([r.s("year"), r.s("size_label")].filter { !$0.isEmpty }.joined(separator: " · ")).font(.inter(12)).foregroundColor(FF.text2).lineLimit(2)
            Button(action: act) {
                Text(busyId == id ? "…" : label).font(.inter(13, .bold)).multilineTextAlignment(.center).lineLimit(2)
                    .foregroundColor(kind == 1 ? FF.dark : .white).frame(maxWidth: .infinity, minHeight: 38 * FF.scale).padding(.horizontal, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(kind == 1 ? Color.white : kind == 2 ? FF.blue : FF.btn))
            }.buttonStyle(FocusStyle()).disabled(kind == 0 || busyId == id).padding(.top, 8)
        }
    }

    func wishFree(_ item: J, _ id: Int) {
        busyId = id
        Task {
            let d = await API.postObj("/api/wishlist_checkout.php", ["action": "create", "mode": "free", "items": [item]])
            busyId = nil
            guard d.b("ok") else { router.toast = d.s("error").isEmpty ? "Fehler beim Wünschen" : d.s("error"); return }
            list = d.a("items") + list
            if let ql = d.o("quota_left"), let total = ql.i("total"), var c = ctx, var qq = c.o("quota") {
                qq["used"] = ["movie": (qq.i("limit") ?? 0) - total, "tv": 0]; c["quota"] = qq; ctx = c
            }
            router.toast = "Wunsch aufgenommen!"
        }
    }

    var cartSheet: some View {
        let total = cart.reduce(0) { $0 + ($1.d("price") ?? 1) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Warenkorb").font(.inter(22, .bold)).foregroundColor(.white).padding(.bottom, 8)
                ForEach(cart.indices, id: \.self) { i in
                    let x = cart[i]
                    WishRow(poster: x.s("poster"), title: x.s("title"), sub: [x.s("year"), x.s("type") == "tv" ? "Serie" : "Film", x.s("size_label")].filter { !$0.isEmpty }.joined(separator: " · ")) {
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(eur(x.d("price") ?? 1)).font(.inter(15, .bold)).foregroundColor(.white)
                            GreyButton(label: "Entfernen") { var c = cart; c.remove(at: i); saveCart(c); if c.isEmpty { cartOpen = false } }
                        }
                    }
                }
                HStack { Text("Summe"); Spacer(); Text(eur(total)) }.font(.inter(18, .bold)).foregroundColor(.white).padding(.vertical, 18)
                Text("Bezahlung sicher über Stripe (Karte, Klarna, Apple Pay).").font(.inter(14)).foregroundColor(FF.text2).padding(.bottom, 14)
                Cta(label: paying ? "Bitte warten …" : "Jetzt bezahlen · " + eur(total), icon: nil) { if !paying { pay() } }
                if !payErr.isEmpty { Text(payErr).font(.inter(14, .bold)).foregroundColor(Color(hex: 0xF87171)).padding(.top, 6) }
                #if !os(tvOS)
                AltPayView(total: total, items: cart, loggedIn: ctx?.b("loggedIn") == true) { msg, pending in
                    saveCart([]); cartOpen = false
                    if pending { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { altInfo = msg } } else { router.toast = msg }
                    Task { await load() }
                }
                #endif
            }.padding(20)
        }.background(FF.sheet.ignoresSafeArea())
    }

    func pay() {
        paying = true; payErr = ""
        Task {
            var payload: J = ["action": "create", "mode": "paid", "items": cart]
            if ctx?.b("loggedIn") != true { payload["guest_id"] = guest }
            let d = await API.postObj("/api/wishlist_checkout.php", payload)
            paying = false
            let url = d.s("checkout_url")
            // Fehler im Warenkorb anzeigen (ein Toast lag hinter dem offenen Sheet, 2026-10-28)
            guard d.b("ok"), !url.isEmpty else { payErr = d.s("error").isEmpty ? "Bestellung konnte nicht erstellt werden – bitte nochmal versuchen." : d.s("error"); return }
            saveCart([]); cartOpen = false
            #if os(tvOS)
            payURL = url
            #else
            // Stripe erst öffnen, wenn das Sheet ganz zu ist – sonst verschluckt iOS die zweite Präsentation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { router.browser(url) }
            #endif
        }
    }
}

#if os(tvOS)
struct QRPay: Identifiable { let url: String; var id: String { url } }

/// Apple TV hat keinen Browser: Bezahlen per QR-Code am Handy.
struct QRPayView: View {
    let url: String
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 40) {
            Text("Mit dem Handy bezahlen").font(.inter(28, .bold)).foregroundColor(.white)
            if let img = qr(url) { Image(uiImage: img).interpolation(.none).resizable().frame(width: 520, height: 520).padding(30).background(Color.white) }
            Text("Code mit der Handy-Kamera scannen und die Bezahlung abschließen. Danach erscheint dein Wunsch in der Liste.").font(.inter(16)).foregroundColor(FF.text2).multilineTextAlignment(.center).frame(maxWidth: 1100)
            GreyButton(label: "Fertig") { dismiss() }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(FF.bg.ignoresSafeArea())
    }
    func qr(_ s: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator(); f.message = Data(s.utf8); f.correctionLevel = "M"
        guard let o = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)), let cg = CIContext().createCGImage(o, from: o.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
#endif

// MARK: - Support

private let TK_CAT: [(String, String)] = [("bug", "Fehler"), ("improvement", "Verbesserung"), ("general", "Frage")]
private func tkCat(_ k: String) -> String { TK_CAT.first { $0.0 == k }?.1 ?? "Frage" }
private let TK_ST: [String: (String, Color, Color)] = [
    "open": ("Offen", Color(hex: 0x1A98FF, alpha: 0.16), Color(hex: 0x7CC0FF)), "in_progress": ("In Bearbeitung", Color(hex: 0xF2C94C, alpha: 0.16), FF.yellow),
    "resolved": ("Gelöst", Color(hex: 0x1FB36B, alpha: 0.18), FF.green), "done": ("Erledigt", Color(hex: 0x1FB36B, alpha: 0.18), FF.green),
    "wontfix": ("Wird nicht umgesetzt", FF.btn, Color(hex: 0xDFE3E7)), "closed": ("Geschlossen", FF.btn, Color(hex: 0xDFE3E7)),
]
private func tkSt(_ s: String) -> (String, Color, Color) { TK_ST[s] ?? TK_ST["open"]! }
private func isOpenTk(_ t: J) -> Bool { !["closed", "resolved", "done", "wontfix"].contains(t.s("status")) }

// MARK: - Support & Forum (2026-10-21)
// Wie die Website: öffentliche Themen kann jeder lesen und mitschreiben – auch Gäste ohne Anmeldung (eigener
// Geräteschlüssel gk, damit man seine Themen wiederfindet). Bilder anhängen (iPhone/iPad), max. 4 je Beitrag.

/// Geräteschlüssel für Gäste (bleibt in der App gespeichert)
func forumGk() -> String {
    let k = "ff24_forum_gk"
    if let g = UserDefaults.standard.string(forKey: k) { return g }
    let g = "a" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(24)
    UserDefaults.standard.set(g, forKey: k)
    return g
}
@MainActor func forumQ() -> String { Store.shared.user == nil ? "&gk=" + forumGk() : "" }
var forumName: String {
    get { UserDefaults.standard.string(forKey: "ff24_forum_name") ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: "ff24_forum_name") }
}
func forumImgURL(_ u: String) -> URL? { URL(string: u.hasPrefix("http") ? u : BASE + u) }

/// Thumbnails eines Beitrags, antippen = groß
struct ForumImages: View {
    let urls: [String]
    var remove: ((String) -> Void)? = nil
    @State private var big: String?
    var body: some View {
        if !urls.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(urls, id: \.self) { u in
                        Button { if let remove { remove(u) } else { big = u } } label: {
                            AsyncImage(url: forumImgURL(u)) { ph in
                                if let i = ph.image { i.resizable().scaledToFill() } else { FF.skel }
                            }.frame(width: 120 * FF.scale, height: 90 * FF.scale).clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                if remove != nil { Image(systemName: "xmark.circle.fill").foregroundColor(.white).padding(4) }
                            }
                        }.buttonStyle(FocusStyle())
                    }
                }
            }.padding(.top, 10)
            #if os(iOS)
            .fullScreenCover(item: Binding(get: { big.map { BigImg(url: $0) } }, set: { big = $0?.url })) { b in
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    AsyncImage(url: forumImgURL(b.url)) { ph in if let i = ph.image { i.resizable().scaledToFit() } else { ProgressView().tint(.white) } }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Button { big = nil } label: { Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundColor(.white).frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.2))) }.padding(16)
                }
            }
            #endif
        }
    }
    struct BigImg: Identifiable { let url: String; var id: String { url } }
}

#if os(iOS)
/// Bilder auswählen + sofort hochladen (verkleinert auf max. 2000 px)
struct ForumImagePicker: View {
    @Binding var urls: [String]
    @EnvironmentObject var router: Router
    @State private var picks: [PhotosPickerItem] = []
    @State private var busy = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PhotosPicker(selection: $picks, maxSelectionCount: max(1, 4 - urls.count), matching: .images) {
                HStack(spacing: 8) { Image(systemName: "photo.on.rectangle"); Text(busy > 0 ? "Lädt hoch …" : "Bilder anhängen") }
                    .font(.inter(15, .semibold)).foregroundColor(.white).padding(.horizontal, 16).frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(FF.btn))
            }.disabled(urls.count >= 4 || busy > 0)
            ForumImages(urls: urls) { u in urls.removeAll { $0 == u } }
        }.padding(.top, 12)
        .onChange(of: picks) { items in
            guard !items.isEmpty else { return }
            picks = []
            for it in items {
                busy += 1
                Task {
                    defer { busy -= 1 }
                    guard let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) else { router.toast = "Bild konnte nicht gelesen werden"; return }
                    let s = min(1, 2000 / max(img.size.width, img.size.height))
                    let sz = CGSize(width: img.size.width * s, height: img.size.height * s)
                    let out = UIGraphicsImageRenderer(size: sz).image { _ in img.draw(in: CGRect(origin: .zero, size: sz)) }
                    guard let jpg = out.jpegData(compressionQuality: 0.85) else { return }
                    let r = (try? await API.upload("/api/support.php?action=upload" + forumQ(), field: "file", filename: "bild.jpg", mime: "image/jpeg", data: jpg)) ?? [:]
                    if r.b("ok"), urls.count < 4 { urls.append(r.s("url")) } else if !r.b("ok") { router.toast = r.s("error").isEmpty ? "Upload fehlgeschlagen" : r.s("error") }
                }
            }
        }
    }
}
#endif

private let FB_TOPICS: [String: [String]] = [
    "bug": ["Film/Folge startet nicht", "Bild ruckelt oder lädt lange", "Kein Ton / Ton versetzt", "Untertitel falsch oder fehlen",
            "App stürzt ab", "Anmeldung geht nicht", "Anderer Fehler"],
    "improvement": ["Bedienung einfacher machen", "Neue Funktion", "Design", "Andere Idee"],
    "general": ["Konto / Anmeldung", "Unterstützer / Bezahlung", "Wünsche", "Andere Frage"],
]

/// Neues Thema: Fehler / Verbesserung / Frage, Punkt antippen, Text, Bilder, öffentlich oder privat.
/// Geht auch mit der Fernbedienung (Text freiwillig). Gerät + App-Version gehen automatisch mit (nur fürs Team).
struct SupportForm: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    var onSent: (String) -> Void = { _ in }
    @State private var cat = "improvement"
    @State private var topic = ""
    @State private var title = ""
    @State private var text = ""
    @State private var name = forumName
    @State private var pub = true
    @State private var imgs: [String] = []
    @State private var busy = false

    var body: some View {
        BoxCard(title: "Neues Thema") {
            HStack(spacing: 10) {
                ForEach(TK_CAT, id: \.0) { k, l in ChipButton(label: l, on: cat == k) { cat = k; topic = ""; pub = k == "improvement" } }
            }.padding(.bottom, 6)
            Label2(cat == "bug" ? "Was ist passiert?" : cat == "improvement" ? "Worum geht es?" : "Thema")
            FlowChips(items: FB_TOPICS[cat] ?? [], sel: $topic)
            if store.user == nil { Label2("Dein Name (freiwillig)"); Field(placeholder: "Gast", text: $name) }
            Label2("Betreff (freiwillig)"); Field(placeholder: topic.isEmpty ? "Worum geht es?" : topic, text: $title)
            Label2("Nachricht"); Field(placeholder: cat == "bug" ? "Welcher Film, was genau …" : "Schreib uns …", text: $text, multiline: true)
            #if os(iOS)
            ForumImagePicker(urls: $imgs)
            #endif
            HStack(spacing: 10) {
                ChipButton(label: "Öffentlich – alle reden mit", on: pub) { pub = true }
                ChipButton(label: "Privat – nur Team", on: !pub) { pub = false }
            }.padding(.top, 14)
            GreyButton(label: busy ? "Wird gesendet …" : "Absenden", white: true, full: true) { send() }.padding(.top, 14)
            Text("Jeder kann mitmachen, auch ohne Anmeldung. Gerät und App-Version sieht nur das Team.").font(.inter(13)).foregroundColor(FF.text2).padding(.top, 10)
        }
    }

    func send() {
        guard !busy else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines), ti = title.trimmingCharacters(in: .whitespaces)
        let head = !ti.isEmpty ? ti : (!topic.isEmpty ? topic : String(t.prefix(80)))
        guard !head.isEmpty else { router.toast = "Bitte ein Thema antippen oder etwas schreiben."; return }
        busy = true
        if store.user == nil { forumName = name.trimmingCharacters(in: .whitespaces) }
        Task {
            var body: J = ["action": "create", "category": cat, "title": String(head.prefix(110)), "text": t.isEmpty ? head : t,
                           "visibility": pub ? "public" : "private", "guest_name": name.isEmpty ? "Gast" : name, "device": deviceInfo(), "images": imgs]
            if store.user == nil { body["gk"] = forumGk() }
            let r = await API.postObj("/api/support.php?action=create", body)
            busy = false
            if r.b("ok"), let tk = r.o("ticket") { topic = ""; title = ""; text = ""; imgs = []; router.toast = "Thema erstellt"; onSent(tk.s("id")) }
            else { router.toast = r.s("error").isEmpty ? "Fehler beim Senden" : r.s("error") }
        }
    }
}

struct TicketRow: View {
    let t: J
    let open: () -> Void
    var body: some View {
        let st = tkSt(t.s("status")), msgs = t.a("messages"), n = max(0, msgs.count - 1)
        let people = Set(msgs.map { $0.b("from_admin") ? "admin" : ($0.s("user_id").isEmpty ? $0.s("user_name") : $0.s("user_id")) }).count
        let imgs = msgs.contains { !$0.strs("images").isEmpty }
        let line = (t.s("user_name").isEmpty ? "Gast" : t.s("user_name")) + " · \(n) Antwort" + (n == 1 ? "" : "en")
            + (people > 1 ? " · \(people) Beteiligte" : "") + (t.d("updated_at").map { " · " + dfmt($0) } ?? "")
        Button(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Pill(text: st.0, bg: st.1, fg: st.2); Pill(text: tkCat(t.s("category")))
                    if t.s("visibility") == "private" { Image(systemName: "lock.fill").font(.system(size: 12 * FF.scale)).foregroundColor(FF.text2) }
                    if imgs { Image(systemName: "photo").font(.system(size: 12 * FF.scale)).foregroundColor(FF.text2) }
                }.padding(.bottom, 2)
                Text(t.s("title")).font(.inter(16, .bold)).foregroundColor(.white).multilineTextAlignment(.leading)
                Text(line).font(.inter(13)).foregroundColor(FF.text2)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(RoundedRectangle(cornerRadius: 10).fill(FF.box))
        }.buttonStyle(FocusStyle()).padding(.bottom, 8)
    }
}

struct SupportView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var tks: [J]? = nil
    @State private var f = "open"
    @State private var c = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SubHead(title: "Support & Forum")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Fehler melden, Ideen vorschlagen, Fragen stellen – jeder kann mitmachen, auch ohne Anmeldung.")
                        .font(.inter(15)).foregroundColor(FF.text2).padding(.bottom, 16)
                    SupportForm { id in Task { await reload() }; router.go(.ticket(id)) }
                    if let l = tks {
                        let mine = l.filter { $0.b("is_own") }
                        if !mine.isEmpty {
                            Text("Meine Themen").font(.inter(22, .bold)).foregroundColor(.white).padding(.top, 22).padding(.bottom, 10)
                            ForEach(Array(mine.prefix(20).enumerated()), id: \.offset) { _, t in TicketRow(t: t) { router.go(.ticket(t.s("id"))) } }
                        }
                        Text("Forum").font(.inter(22, .bold)).foregroundColor(.white).padding(.top, 22).padding(.bottom, 10)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach([("", "Alle"), ("improvement", "Vorschläge"), ("bug", "Fehler"), ("general", "Fragen")], id: \.0) { k, lb in
                                    ChipButton(label: lb, on: c == k, dark: false) { c = k }
                                }
                                ChipButton(label: f == "open" ? "Offen" : "Erledigt", on: true, dark: false) { f = f == "open" ? "closed" : "open" }
                            }
                        }.padding(.bottom, 14)
                        let shown = Array(l.filter { (f == "open" ? isOpenTk($0) : !isOpenTk($0)) && (c.isEmpty || $0.s("category") == c) }.prefix(100))
                        if shown.isEmpty { Text("Keine Themen.").foregroundColor(FF.text2) }
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, t in TicketRow(t: t) { router.go(.ticket(t.s("id"))) } }
                    } else { FF.skel.frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 12)) }
                }.padding(.horizontal, FF.pad)
            }.padding(.bottom, 110)
        }
        .background(FF.bg.ignoresSafeArea())
        .task(id: store.user?.id) { await reload() }
    }
    func reload() async { tks = await API.getObj("/api/support.php?action=list" + forumQ()).a("tickets") }
}

struct TicketView: View {
    let id: String
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) var dismiss
    @State private var t: J? = nil
    @State private var loaded = false
    @State private var reply = ""
    @State private var name = forumName
    @State private var imgs: [String] = []
    @State private var busy = false
    @State private var confirmDel = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SubHead(title: "Thema")
                VStack(alignment: .leading, spacing: 0) {
                    if let tk = t {
                        let st = tkSt(tk.s("status")), priv = tk.s("visibility") == "private"
                        Text(tk.s("title")).font(.inter(22, .bold)).foregroundColor(.white).padding(.bottom, 10)
                        HStack(spacing: 8) {
                            Pill(text: st.0, bg: st.1, fg: st.2); Pill(text: tkCat(tk.s("category")))
                            Pill(text: priv ? "Privat" : "Öffentlich")
                        }.padding(.bottom, 8)
                        if !tk.s("device").isEmpty { Text(tk.s("device")).font(.inter(12)).foregroundColor(FF.text2).padding(.bottom, 8) }
                        ForEach(Array(tk.a("messages").enumerated()), id: \.offset) { _, m in post(m) }
                        if tk.s("status") == "closed" { Text("Dieses Thema ist geschlossen.").foregroundColor(FF.text2).padding(.vertical, 12) }
                        else if tk.b("can_reply") {
                            BoxCard {
                                if store.user == nil { Label2("Dein Name (freiwillig)"); Field(placeholder: "Gast", text: $name) }
                                Field(placeholder: priv || tk.b("is_own") ? "Antwort schreiben …" : "Mitreden – deine Meinung oder Ergänzung …", text: $reply, multiline: true)
                                #if os(iOS)
                                ForumImagePicker(urls: $imgs)
                                #endif
                                GreyButton(label: busy ? "…" : "Senden", white: true) { sendReply(tk) }.padding(.top, 12)
                            }.padding(.top, 8)
                        }
                        if store.user?.role == "admin" { adminBox(tk) }
                        GreyButton(label: "Alle Themen") { dismiss() }.padding(.top, 8)
                    } else if loaded {
                        EmptyState(title: "", text: "Thema nicht gefunden oder privat.")
                    } else { FF.skel.frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 12)) }
                }.padding(.horizontal, FF.pad)
            }.padding(.bottom, 110)
        }
        .background(FF.bg.ignoresSafeArea())
        .task { await load() }
        .alert("Thema endgültig löschen?", isPresented: $confirmDel) {
            Button("Löschen", role: .destructive) {
                Task {
                    let r = await API.postObj("/api/support.php?action=delete", ["action": "delete", "id": id])
                    if r.b("ok") { router.toast = "Thema gelöscht"; dismiss() } else { router.toast = r.s("error").isEmpty ? "Löschen fehlgeschlagen" : r.s("error") }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    func post(_ m: J) -> some View {
        let admin = m.b("from_admin")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(admin ? "FilmFrei24 Support" : (m.b("from_bot") ? "Support-KI" : (m.s("user_name").isEmpty ? "Gast" : m.s("user_name")))).font(.inter(15, .bold)).foregroundColor(.white)
                if admin { Pill(text: "Team", bg: Color(hex: 0x1FB36B, alpha: 0.18), fg: FF.green) }
                Text(m.d("time").map { dfmt($0) } ?? "").font(.inter(12)).foregroundColor(FF.text2)
            }
            Text(m.s("text")).font(.inter(15)).foregroundColor(.white).fixedSize(horizontal: false, vertical: true)
            ForumImages(urls: m.strs("images"))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(FF.box))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(admin ? FF.green.opacity(0.45) : Color.white.opacity(0.06)))
        .padding(.bottom, 10)
    }

    func load() async { t = await API.getObj("/api/support.php?action=get&id=" + API.enc(id) + forumQ()).o("ticket"); loaded = true }

    func sendReply(_ tk: J) {
        let txt = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!txt.isEmpty || !imgs.isEmpty), !busy else { return }
        busy = true
        if store.user == nil { forumName = name.trimmingCharacters(in: .whitespaces) }
        Task {
            var body: J = ["action": "reply", "id": tk.s("id"), "ticket_id": tk.s("id"), "text": txt.isEmpty ? "(Bild)" : txt, "images": imgs, "guest_name": name]
            if store.user == nil { body["gk"] = forumGk() }
            let r = await API.postObj("/api/support.php?action=reply", body)
            busy = false
            if r.b("ok") { reply = ""; imgs = []; await load() } else { router.toast = r.s("error").isEmpty ? "Fehler" : r.s("error") }
        }
    }

    func adminBox(_ tk: J) -> some View {
        let opts: [(String, String)] = isOpenTk(tk)
            ? [("closed", "Schließen")] + (tk.s("status") != "in_progress" ? [("in_progress", "In Bearbeitung")] : []) + [("done", "Erledigt"), ("wontfix", "Wird nicht umgesetzt")]
            : [("open", "Wieder öffnen")]
        return BoxCard(title: "Admin") {
            VStack(spacing: 8) {
                ForEach(opts, id: \.0) { v, l in
                    GreyButton(label: l, full: true) {
                        Task {
                            let r = await API.postObj("/api/support.php?action=status", ["action": "status", "id": tk.s("id"), "status": v])
                            if r.b("ok") { router.toast = "Status: " + tkSt(v).0; await load() } else { router.toast = r.s("error").isEmpty ? "Fehler" : r.s("error") }
                        }
                    }
                }
                Button { confirmDel = true } label: {
                    Text("Löschen").font(.inter(15, .bold)).foregroundColor(Color(hex: 0xFF8A8D)).frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0xE5484D, alpha: 0.16)))
                }.buttonStyle(FocusStyle())
            }
        }.padding(.top, 16)
    }
}

// MARK: - IPTV

struct IptvView: View {
    @EnvironmentObject var router: Router
    @State private var n = ("…", "…", "…")
    private let m3u = "https://filmfrei24.com/playlist.m3u"
    private let xt = "https://tv.filmfrei24.com/xtream/get.php?username=public&password=ff24stream&type=m3u_plus&output=ts"

    var body: some View {
        let (fi, se, ep) = n
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SubHead(title: "IPTV")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Für TiviMate, IPTV Smarters, Perfect Player, VLC, Kodi und Co.: alle \(fi) Filme + \(se) Serien mit \(ep) Folgen sofort verfügbar. Kostenlos, unbegrenzt, ohne Ablauf.")
                        .font(.inter(16)).foregroundColor(FF.text2).lineSpacing(6).padding(.top, 8).padding(.bottom, 22)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) { Pill(text: "HTTPS · Port 443", bg: Color(hex: 0x1FB36B, alpha: 0.18), fg: FF.green); Text("Empfohlen · Xtream Codes").font(.inter(13)).foregroundColor(FF.text2) }
                            .padding(.horizontal, 20).padding(.vertical, 14)
                        field("Server URL", "https://tv.filmfrei24.com", false)
                        HStack(spacing: 0) { field("Benutzer", "public", true); field("Passwort", "ff24stream", true) }
                        Text("✓ \(fi) Filme   ✓ \(se) Serien · \(ep) Folgen   ✓ Unbegrenzt   ✓ Kein Ablauf").font(.inter(13, .semibold)).foregroundColor(FF.green).padding(.horizontal, 20).padding(.vertical, 14)
                    }.background(RoundedRectangle(cornerRadius: 12).fill(FF.box)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06)))
                    h2("Kein Xtream-Account einrichten wollen?")
                    p("Diese Alternativen enthalten bereits alle Filme + alle Serien in einer einzigen URL — kein Login, keine separaten Felder.")
                    urlBox(m3u)
                    h2("Xtream-URL mit eingebetteten Zugangsdaten")
                    p("Manche Apps akzeptieren eine einzige komplette URL statt Server/Benutzer/Passwort getrennt einzugeben:")
                    urlBox(xt)
                    h2("So verwendest du FilmFrei24 in deiner App")
                    step("1", "App öffnen → „Playlist hinzufügen“", "Für die beste Erfahrung (Film- und Serien-Kategorien) den Typ Xtream Codes wählen — für einfache Player reicht die M3U-URL.")
                    step("2", "Zugangsdaten oder URL eingeben", "Server, Benutzer (public) und Passwort (ff24stream) aus der Karte oben eintragen — oder eine der URLs darüber direkt einfügen.")
                    h2("Kompatible Apps")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: FF.scale > 1 ? 3 : 2), spacing: 12) {
                        ForEach([("TiviMate", "Android TV · Fire TV"), ("IPTV Smarters", "iOS · Android · Smart TV"), ("Perfect Player", "Android TV"), ("GSE Smart IPTV", "iOS · Android"),
                                 ("Duplex Play", "Smart TV · Android"), ("Sparkle TV", "Apple TV · iOS"), ("Infuse", "Apple TV · iPhone · Mac"), ("VLC", "Alle Plattformen"), ("Kodi", "Alle Plattformen")], id: \.0) { a, pl in
                            VStack(spacing: 4) { Text(a).font(.inter(16, .bold)).foregroundColor(.white); Text(pl).font(.inter(12)).foregroundColor(FF.text2).multilineTextAlignment(.center) }
                                .frame(maxWidth: .infinity).padding(16).background(RoundedRectangle(cornerRadius: 12).fill(FF.box))
                        }
                    }
                    Text("Alle URLs werden automatisch aktualisiert, sobald neue Filme oder Serienfolgen hinzukommen — einmal einbinden, immer aktuell, kein manuelles Update nötig.")
                        .font(.inter(15)).foregroundColor(FF.yellow).lineSpacing(5).padding(20).background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xF2C94C, alpha: 0.08))).padding(.top, 24)
                }.padding(.horizontal, FF.pad)
            }.padding(.bottom, 110)
        }
        .background(FF.bg.ignoresSafeArea())
        .task {
            let d = await API.getObj("/beta/api.php?q=iptv")
            guard d.b("ok") else { return }
            let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "de_DE")
            func x(_ k: String) -> String { f.string(from: NSNumber(value: d.i(k) ?? 0)) ?? "" }
            n = (x("films"), x("series"), x("episodes"))
        }
    }

    func copy(_ v: String) {
        #if os(iOS)
        UIPasteboard.general.string = v; router.toast = "Kopiert!"
        #endif
    }
    func field(_ l: String, _ v: String, _ big: Bool) -> some View {
        Button { copy(v) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(l.uppercased()).font(.inter(11, .bold)).foregroundColor(FF.text2).kerning(1)
                Text(v).font(.system(size: (big ? 17 : 15) * FF.scale, weight: big ? .heavy : .regular, design: .monospaced)).foregroundColor(.white)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 12).overlay(Rectangle().stroke(FF.line, lineWidth: 0.5))
        }.buttonStyle(FocusStyle())
    }
    func h2(_ t: String) -> some View { Text(t).font(.inter(18, .bold)).foregroundColor(.white).padding(.top, 30).padding(.bottom, 10) }
    func p(_ t: String) -> some View { Text(t).font(.inter(15)).foregroundColor(FF.text2).lineSpacing(5).padding(.bottom, 14) }
    func urlBox(_ v: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(v).font(.inter(14)).foregroundColor(Color(hex: 0xDFE3E7)).padding(4)
            #if os(iOS)
            GreyButton(label: "Kopieren", full: true) { copy(v) }
            #endif
        }.padding(12).background(RoundedRectangle(cornerRadius: 12).fill(FF.box)).padding(.bottom, 6)
    }
    func step(_ n: String, _ t: String, _ p: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(n).font(.inter(15, .heavy)).foregroundColor(.white).frame(width: 30, height: 30).background(Circle().fill(FF.btn))
            VStack(alignment: .leading, spacing: 4) { Text(t).font(.inter(16, .bold)).foregroundColor(.white); Text(p).font(.inter(15)).foregroundColor(FF.text2).lineSpacing(5) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(RoundedRectangle(cornerRadius: 12).fill(FF.box)).padding(.bottom, 18)
    }
}

// MARK: - Fehler melden / Idee (2026-10-21): schnell, auch mit der Fernbedienung, Gerät geht automatisch mit

/// „Apple TV (AppleTV14,1) · tvOS 18.1 · App 2.4.0 (7)“ – landet nur beim Team im Ticket.
func deviceInfo() -> String {
    var u = utsname(); uname(&u)
    let model = withUnsafePointer(to: &u.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
    let d = UIDevice.current
    let kind: String
    #if os(tvOS)
    kind = "Apple TV"
    #else
    kind = d.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    #endif
    let info = Bundle.main.infoDictionary
    let v = (info?["CFBundleShortVersionString"] as? String ?? "?") + " (" + (info?["CFBundleVersion"] as? String ?? "?") + ")"
    return "\(kind) (\(model)) · \(d.systemName) \(d.systemVersion) · App \(v)"
}

/// Auswahl-Knöpfe, die umbrechen (Handy) bzw. in Reihen stehen (Fernseher)
struct FlowChips: View {
    let items: [String]
    @Binding var sel: String
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220 * FF.scale), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { s in
                ChipButton(label: s, on: sel == s) { sel = sel == s ? "" : s }
            }
        }
    }
}


#if !os(tvOS)
/// 2026-10-28: Guthaben, Paysafecard, Überweisung (SumUp) wie auf der Website – nur mit Konto,
/// Paysafe/Überweisung werden von Hand geprüft (api/credit.php, wishlist_checkout mode=credit).
struct AltPayView: View {
    let total: Double
    let items: [J]
    let loggedIn: Bool
    let onDone: (String, Bool) -> Void
    @EnvironmentObject var router: Router
    @State private var c: J? = nil
    @State private var kind = ""
    @State private var busy = false
    @State private var pins: [(String, String)] = [("", "")]
    @State private var err = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !loggedIn {
                Text("Lieber mit Paysafecard oder Überweisung zahlen? Das geht, wenn du angemeldet bist (Konto).").font(.inter(14)).foregroundColor(FF.text2)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 14)
            } else if let cc = c {
                let tc = Int((total * 100).rounded()), bal = cc.i("balance") ?? 0, need = max(0, tc - bal)
                HStack { Rectangle().fill(FF.btn).frame(height: 1); Text("oder").font(.inter(13)).foregroundColor(FF.text2); Rectangle().fill(FF.btn).frame(height: 1) }.padding(.top, 18)
                if bal > 0 { Text("Dein Guthaben: " + eur(Double(bal) / 100)).font(.inter(15, .bold)).foregroundColor(.white) }
                if bal >= tc {
                    Cta(label: busy ? "Bitte warten …" : "Mit Guthaben bezahlen · " + eur(total), icon: nil, dark: true) { if !busy { submit(nil) } }
                }
                HStack(spacing: 10) {
                    if cc.b("paysafe") { opt("paysafe", "🎫 Paysafecard") }
                    if !cc.s("iban").isEmpty { opt("transfer", "🏦 Überweisung") }
                }
                if kind == "paysafe" { paysafe(need, bal) }
                if kind == "transfer" { transfer(cc, tc) }
                if !err.isEmpty { Text(err).font(.inter(14, .bold)).foregroundColor(Color(hex: 0xF87171)) }
            }
        }
        .task { if loggedIn && c == nil { let d = await API.getObj("/api/credit.php?action=me"); if d.b("ok") { c = d; let t = Int((total * 100).rounded()), n = max(0, t - (d.i("balance") ?? 0)); pins = [("", String(format: "%.2f", Double(n > 0 ? n : t) / 100).replacingOccurrences(of: ".", with: ","))] } } }
    }

    func opt(_ k: String, _ l: String) -> some View {
        Button { kind = k } label: {
            VStack(spacing: 2) {
                Text(l).font(.inter(15, .bold))
                Text("manuelle Prüfung").font(.inter(12))
            }.foregroundColor(kind == k ? FF.dark : .white).frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 8).fill(kind == k ? Color.white : FF.btn))
        }.buttonStyle(.plain)
    }

    func paysafe(_ need: Int, _ bal: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gib den 16-stelligen Code deiner Paysafecard und ihren Wert ein (jeder Betrag). Die Karte wird von uns manuell geprüft (meist innerhalb eines Tages), erst danach werden deine Wünsche angelegt. Was übrig bleibt, bekommst du als Guthaben.").font(.inter(14)).foregroundColor(.white)
            Text("Preis deiner Wünsche: " + eur(total) + (bal > 0 ? " · dein Guthaben wird mit verrechnet" : "")).font(.inter(13)).foregroundColor(FF.text2)
            ForEach(pins.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    TextField("16-stelliger Code", text: Binding(get: { pins[i].0 }, set: { pins[i].0 = String($0.filter(\.isNumber).prefix(16)) }))
                        .keyboardType(.numberPad).font(.system(size: 16, design: .monospaced)).foregroundColor(.white)
                        .padding(12).background(RoundedRectangle(cornerRadius: 8).fill(FF.field))
                    HStack(spacing: 4) {
                        TextField("Wert", text: Binding(get: { pins[i].1 }, set: { pins[i].1 = String($0.filter { $0.isNumber || $0 == "," || $0 == "." }.prefix(7)) }))
                            .keyboardType(.decimalPad).font(.inter(16)).foregroundColor(.white)
                        Text("€").foregroundColor(FF.text2)
                    }.frame(width: 100).padding(12).background(RoundedRectangle(cornerRadius: 8).fill(FF.field))
                }
            }
            if pins.count < 5 { GreyButton(label: "+ weitere Karte") { pins.append(("", "")) } }
            Cta(label: busy ? "Bitte warten …" : "Code einreichen", icon: nil) {
                let ok = pins.filter { !$0.0.isEmpty }
                let num = { (v: String) -> Double in Double(v.replacingOccurrences(of: ",", with: ".")) ?? 0 }
                if ok.isEmpty || ok.contains(where: { $0.0.count != 16 }) { err = "Ein Paysafecard-Code hat 16 Ziffern."; return }
                if ok.contains(where: { num($0.1) < 1 }) { err = "Bitte zu jedem Code den Wert der Karte eintragen."; return }
                if !busy { submit(["method": "paysafe", "pins": ok.map { ["pin": $0.0, "value": num($0.1)] }]) }
            }.padding(.top, 4)
        }.padding(.top, 8)
    }

    func transfer(_ cc: J, _ price: Int) -> some View {
        let amt = price // genau der Kaufpreis, kein Guthaben (Rest-Guthaben nur bei Paysafecard)
        let rows: [(String, String)] = [
            ("Empfänger", cc.s("holder")), ("IBAN", cc.s("iban")), ("BIC", cc.s("bic")), ("Bank", cc.s("bank")),
            ("Verwendungszweck", cc.s("ref")), ("Betrag", eur(Double(amt) / 100)),
        ].filter { !$0.1.isEmpty }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Überweise genau den Kaufpreis auf unser Konto. Wichtig: Verwendungszweck genau so angeben. Die Überweisung wird von uns manuell geprüft, sobald das Geld da ist (meist 1–2 Werktage), danach werden deine Wünsche angelegt. Tippen zum Kopieren.").font(.inter(14)).foregroundColor(.white)
            ForEach(rows, id: \.0) { r in
                Button { UIPasteboard.general.string = r.0 == "Betrag" ? String(format: "%.2f", Double(amt) / 100).replacingOccurrences(of: ".", with: ",") : r.1; router.toast = "Kopiert!" } label: {
                    HStack(alignment: .top) {
                        Text(r.0).font(.inter(14)).foregroundColor(FF.text2).frame(width: 130, alignment: .leading)
                        Text(r.1).font(.inter(14, .bold)).foregroundColor(r.0 == "Verwendungszweck" ? Color(hex: 0x93C5FD) : .white).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }.buttonStyle(.plain)
            }
            Cta(label: busy ? "Bitte warten …" : "Ich habe überwiesen", icon: nil) {
                if !busy { submit(["method": "transfer", "amount": String(format: "%.2f", Double(amt) / 100)]) }
            }.padding(.top, 6)
        }.padding(.top, 8)
    }

    func submit(_ topup: J?) {
        busy = true
        Task {
            var p: J = ["action": "create", "mode": "credit", "items": items]
            if let topup { p["topup"] = topup }
            let d = await API.postObj("/api/wishlist_checkout.php", p)
            busy = false
            guard d.b("ok") else { err = d.s("error").isEmpty ? "Fehler – bitte nochmal versuchen." : d.s("error"); return }
            err = ""
            if d.b("pending") {
                onDone(kind == "paysafe"
                       ? "Deine Paysafecard wird von Hand geprüft. Danach werden deine Wünsche angelegt und du bekommst eine Nachricht ins Postfach. Was von der Karte übrig bleibt, wird dein Guthaben."
                       : "Sobald deine Überweisung mit dem Verwendungszweck \(d.s("ref")) bei uns ankommt, prüfen wir sie von Hand. Danach werden deine Wünsche angelegt und du bekommst eine Nachricht ins Postfach.", true)
            } else {
                onDone("Danke! Wünsche angelegt · Restguthaben " + eur(Double(d.i("balance") ?? 0) / 100), false)
            }
        }
    }
}
#endif
