import SwiftUI
#if os(tvOS)
import CoreImage.CIFilterBuiltins
#endif
#if os(iOS)
import PhotosUI
#endif

// MARK: - Suche

struct SearchView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var q = ""
    @State private var shown = ""
    @State private var allGenres = false

    var body: some View {
        let res = searchItems(store.web.all, shown)
        let genres = genresOf(store.web.all)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if shown.isEmpty { Text("Suchen").font(.inter(28, .bold)).foregroundColor(.white).padding(.bottom, 16) }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundColor(Color(hex: 0x6B7280))
                    TextField("", text: $q, prompt: Text("Schauspieler, Titel oder Genre").foregroundColor(Color(hex: 0x6B7280)))
                        .font(.inter(16)).foregroundColor(FF.dark).submitLabel(.search).onSubmit { shown = q.trimmingCharacters(in: .whitespaces) }
                        #if !os(tvOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                    if !q.isEmpty { Button("Löschen") { q = ""; shown = "" }.font(.inter(15, .semibold)).foregroundColor(Color(hex: 0x374151)) }
                }
                .padding(.horizontal, 18).frame(height: 52 * FF.scale).background(Capsule().fill(Color.white))

                if !shown.isEmpty {
                    Text("Ergebnisse").font(.inter(24, .bold)).foregroundColor(.white).padding(.top, 22).padding(.bottom, 8)
                    if res.isEmpty { Text("Keine Treffer für „\(shown)“.").font(.inter(17)).foregroundColor(FF.text2).frame(maxWidth: .infinity).padding(.vertical, 40) }
                    #if os(tvOS)
                    PosterGrid(items: Array(res.prefix(80)), open: router.open).padding(.horizontal, -FF.pad)
                    #else
                    ForEach(res.prefix(80)) { it in ListRow(it: it) { router.open(it) } }
                    #endif
                } else {
                    Text("Genres").font(.inter(22, .bold)).foregroundColor(.white).padding(.top, 22)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: FF.scale > 1 ? 4 : 2), spacing: 14) {
                        ForEach(allGenres ? genres : Array(genres.prefix(6)), id: \.self) { g in
                            Button { router.list("filme", g: g) } label: {
                                Text(g).font(.inter(16)).foregroundColor(.white).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 58 * FF.scale)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(FF.btn))
                            }.buttonStyle(FocusStyle())
                        }
                    }.padding(.vertical, 16)
                    if !allGenres {
                        Button { allGenres = true } label: {
                            HStack(spacing: 8) { Text("Mehr anzeigen").font(.inter(15, .bold)); Image(systemName: "chevron.down") }.foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
                        }.buttonStyle(FocusStyle())
                    }
                    Text("Empfohlene Sammlungen").font(.inter(22, .bold)).foregroundColor(.white).padding(.top, 22).padding(.bottom, 4)
                    coll("Neue Filme") { router.list("filme", s: "neu") }
                    coll("Neue Folgen") { router.list("serien", s: "neu") }
                    coll("Am besten bewertet") { router.list("filme", s: "bewertung") }
                    coll("Alle Serien") { router.list("serien", s: "bewertung") }
                    coll("Film wünschen") { router.switchTab("wuensche") }
                }
            }.padding(.horizontal, FF.pad).padding(.top, 10).padding(.bottom, 110)
        }
        .background(FF.bg.ignoresSafeArea())
        .task(id: q) { try? await Task.sleep(nanoseconds: 200_000_000); shown = q.trimmingCharacters(in: .whitespaces) }
    }

    func coll(_ l: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            VStack(spacing: 0) {
                HStack { Text(l).font(.inter(17)); Spacer(); Image(systemName: "chevron.right") }.foregroundColor(.white).padding(.vertical, 16)
                Color(hex: 0x2B3139).frame(height: 1)
            }
        }.buttonStyle(FocusStyle())
    }
}

// MARK: - Konto

private let W_ST: [String: (String, Color, Color)] = [
    "pending": ("Ausstehend", Color(hex: 0x1A98FF, alpha: 0.16), Color(hex: 0x7CC0FF)),
    "in_progress": ("In Bearbeitung", Color(hex: 0xF2C94C, alpha: 0.16), FF.yellow),
    "fulfilled": ("Erfüllt", Color(hex: 0x1FB36B, alpha: 0.18), FF.green),
    "unavailable": ("Nicht erfüllbar", Color(hex: 0xE5484D, alpha: 0.16), Color(hex: 0xFF8A8D)),
]
func wishStatus(_ s: String) -> (String, Color, Color) { W_ST[s] ?? W_ST["pending"]! }

struct AccountView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var tab = 0
    @State private var wishes: [J]? = nil

    var body: some View {
        ScrollView {
            if let u = store.user { profile(u) } else { guest }
        }
        .background(FF.bg.ignoresSafeArea())
        .task(id: tab) {
            if tab == 2, wishes == nil, let u = store.user {
                wishes = await API.getObj("/api/wishlist.php?action=list").a("items").filter { $0.s("user_id") == u.id }
            }
        }
    }

    var guest: some View {
        EmptyState(title: "Willkommen bei FilmFrei24", text: "Melde dich an, um weiterzuschauen, Filme zu wünschen und Nachrichten zu erhalten.") {
            VStack(spacing: 12) {
                Cta(label: "Anmelden", icon: nil, height: 48) { router.go(.login(register: false)) }.frame(maxWidth: 320)
                GreyButton(label: "Neues Konto erstellen") { router.go(.login(register: true)) }
                GreyButton(label: "IPTV-Playlist") { router.go(.iptv) }
            }
        }.padding(.top, 90)
    }

    func profile(_ u: User) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { router.go(.settings) } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 20 * FF.scale)).foregroundColor(.white).frame(width: 44 * FF.scale, height: 44 * FF.scale).background(Circle().fill(FF.btn))
                }.buttonStyle(FocusStyle())
            }.padding(.top, 12)
            VStack(spacing: 0) {
                Avatar(user: u, size: 84 * FF.scale)
                Text(u.name).font(.inter(24, .bold)).foregroundColor(.white).padding(.top, 12)
                if let ic = ["admin": "👑", "team": "🛠️", "member": "⭐"][u.tier] {
                    Pill(text: "\(ic) \(u.label)" + (u.tier == "member" && !u.until.isEmpty ? " · bis \(u.until)" : ""), bg: .white, fg: FF.dark).padding(.top, 10)
                    if u.tier == "member" { Text("Danke für deine Unterstützung! · bevorzugter Support").font(.inter(14)).foregroundColor(FF.text2).padding(.top, 8) }
                } else {
                    GreyButton(label: "⭐ FilmFrei24 unterstützen · 10 € im Monat") { memberCheckout() }.padding(.top, 14)
                }
            }.padding(.top, 10).padding(.bottom, 20)
            Tabs(labels: ["Weiterschauen", "Merkliste", "Meine Wünsche"], sel: $tab)
            VStack(alignment: .leading, spacing: 0) {
                switch tab {
                case 0:
                    let c = store.contItems
                    if c.isEmpty { EmptyState(title: "Jetzt entdecken, später weiterschauen", text: "Was du anfängst, findest du hier auf allen Geräten wieder.") { Cta(label: "Stöbern", icon: nil, height: 48) { router.switchTab("home") }.frame(maxWidth: 260) } }
                    ForEach(c.prefix(100), id: \.0.key) { it, p in
                        ListRow(it: it, pct: p.pct, trailing: AnyView(Button { store.removeCont(it) } label: { Image(systemName: "xmark").foregroundColor(FF.text2).frame(width: 36, height: 40) }.buttonStyle(FocusStyle()))) { router.open(it) }
                    }
                case 1:
                    let l = store.wlItems
                    if l.isEmpty { EmptyState(title: "Deine Merkliste ist leer", text: "Tippe bei einem Film oder einer Serie auf „Merkliste“, um ihn für später zu speichern.") { Cta(label: "Stöbern", icon: nil, height: 48) { router.switchTab("home") }.frame(maxWidth: 260) } }
                    ForEach(l) { it in ListRow(it: it) { router.open(it) } }
                default:
                    if let w = wishes {
                        if w.isEmpty { EmptyState(title: "Noch keine Wünsche", text: "Fehlt dir ein Film oder eine Serie? Wünsch sie dir.") { Cta(label: "Wünschen", icon: nil, height: 48) { router.switchTab("wuensche") }.frame(maxWidth: 260) } }
                        ForEach(w.indices, id: \.self) { i in
                            let x = w[i], st = wishStatus(x.s("status"))
                            WishRow(poster: x.s("poster"), title: x.s("title"), sub: [x.s("year"), x.s("type") == "tv" ? "Serie" : "Film"].filter { !$0.isEmpty }.joined(separator: " · ")) {
                                Pill(text: st.0, bg: st.1, fg: st.2)
                            }.padding(.bottom, 10)
                        }
                    } else { Loading() }
                }
            }.padding(.top, 12)
        }.padding(.horizontal, FF.pad).padding(.bottom, 110)
    }

    func memberCheckout() {
        Task {
            let d = await API.postObj("/api/membership.php", ["action": "checkout"])
            let url = d.s("checkout_url")
            if url.isEmpty { router.toast = d.s("error").isEmpty ? "Abo konnte nicht gestartet werden" : d.s("error") } else { router.browser(url) }
        }
    }
}

struct WishRow<T: View>: View {
    let poster: String
    let title: String
    let sub: String
    var note = ""
    @ViewBuilder var trailing: T
    var body: some View {
        HStack(spacing: 12) {
            ZStack { FF.surface; if !poster.isEmpty { Img(url: imgProxy(poster, 185)) } }
                .frame(width: 54 * FF.scale, height: 81 * FF.scale).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.inter(15, .bold)).foregroundColor(.white)
                if !sub.isEmpty { Text(sub).font(.inter(13)).foregroundColor(FF.text2) }
                if !note.isEmpty { Text(note).font(.inter(13)).foregroundColor(Color(hex: 0xCFD3D8)) }
            }
            Spacer(minLength: 0)
            trailing
        }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(FF.box))
    }
}

// MARK: - Einstellungen

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) var dismiss
    @State private var mail: Bool? = nil
    @State private var pw0 = ""
    @State private var pw1 = ""
    @State private var pw2 = ""
    @State private var confirm: (String, String)? = nil
    #if os(iOS)
    @State private var photo: PhotosPickerItem?
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SubHead(title: "Einstellungen")
                if let u = store.user {
                    VStack(spacing: 0) {
                        #if os(iOS)
                        BoxCard(title: "Profilbild") {
                            HStack(spacing: 16) {
                                Avatar(user: u, size: 64)
                                PhotosPicker(selection: $photo, matching: .images) {
                                    Text("Bild wählen").font(.inter(15, .bold)).foregroundColor(.white).padding(.horizontal, 18).frame(minHeight: 44).background(RoundedRectangle(cornerRadius: 8).fill(FF.btn))
                                }
                            }
                        }
                        #endif
                        BoxCard(title: "E-Mails") {
                            SetRow(title: "Neue Filme per E-Mail", sub: "Wir schreiben dir, wenn neue Filme da sind.", last: true) {
                                Toggle("", isOn: Binding(get: { mail ?? false }, set: { v in
                                    mail = v
                                    Task { if !(await API.postObj("/api/email_prefs.php", ["new_films": v])).b("ok") { mail = !v; router.toast = "Konnte nicht gespeichert werden" } }
                                })).labelsHidden().tint(FF.blue)
                            }
                        }
                        BoxCard(title: u.hasPassword ? "Passwort ändern" : "Passwort festlegen") {
                            if u.hasPassword { Label2("Aktuelles Passwort"); Field(placeholder: "", text: $pw0, secure: true) }
                            else { Text("Du meldest dich mit Google an. Mit einem Passwort kannst du dich auch per E-Mail anmelden.").font(.inter(15)).foregroundColor(FF.text2) }
                            Label2("Neues Passwort"); Field(placeholder: "", text: $pw1, secure: true)
                            Label2("Neues Passwort wiederholen"); Field(placeholder: "", text: $pw2, secure: true)
                            GreyButton(label: "Speichern", white: true) {
                                Task {
                                    let d = await API.postObj("/api/change_password.php", ["current_password": pw0, "new_password": pw1, "new_password2": pw2])
                                    if d.b("ok") { router.toast = "Passwort geändert"; pw0 = ""; pw1 = ""; pw2 = "" } else { router.toast = d.s("error").isEmpty ? "Fehler" : d.s("error") }
                                }
                            }.padding(.top, 14)
                        }
                        BoxCard(title: "Verlauf") {
                            SetRow(title: "Weiterschauen leeren", sub: "Entfernt alle angefangenen Filme und Folgen.") { GreyButton(label: "Leeren") { confirm = ("clear", "Weiterschauen leeren") } }
                            SetRow(title: "Angeschaut-Liste leeren", sub: "Entfernt alle fertig geschauten Titel.", last: true) { GreyButton(label: "Leeren") { confirm = ("clear_watched", "Angeschaut-Liste leeren") } }
                        }
                        BoxCard(title: "Wiedergabe") {
                            SetRow(title: "Forced-Untertitel automatisch", sub: "Deutsche Untertitel bei fremdsprachigen Stellen.", last: true) {
                                Toggle("", isOn: $store.subtitlesDefault).labelsHidden().tint(FF.blue)
                            }
                        }
                        BoxCard(title: "Mehr") {
                            if u.tier == "user" { SetRow(title: "Unterstützer werden", sub: "10 € im Monat · Filme gratis wünschen, 10 % auf Serien") { GreyButton(label: "Unterstützen", white: true) { member() } } }
                            SetRow(title: "IPTV-Playlist", sub: "Alle Filme & Serien in TiviMate, VLC, Kodi & Co.") { GreyButton(label: "Öffnen") { router.go(.iptv) } }
                            SetRow(title: "Discord", sub: "Community & Neuigkeiten", last: true) { GreyButton(label: "Öffnen") { router.browser("https://discord.gg/Jzj4nYj85U") } }
                        }
                        BoxCard {
                            SetRow(title: "Fehler melden / Idee", sub: "Schnell melden, Gerät geht automatisch mit") { GreyButton(label: "Melden") { router.go(.feedback) } }
                            SetRow(title: "Hilfe & Support", sub: "Fragen, Fehler oder Vorschläge") { GreyButton(label: "Öffnen") { router.go(.support) } }
                            SetRow(title: "Angemeldet als", sub: u.email.isEmpty ? u.name : u.email) { GreyButton(label: "Abmelden") { Task { await store.logout(); router.switchTab("home") } } }
                            SetRow(title: "App-Version", sub: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "", last: true) { EmptyView() }
                        }
                    }.padding(.horizontal, FF.pad).padding(.top, 8)
                }
            }.padding(.bottom, 110)
        }
        .background(FF.bg.ignoresSafeArea())
        .task { mail = await API.getObj("/api/email_prefs.php").b("new_films") }
        .onChange(of: store.user == nil) { gone in if gone { dismiss() } }
        #if os(iOS)
        .onChange(of: photo) { p in
            guard let p else { return }
            Task {
                guard let data = try? await p.loadTransferable(type: Data.self), let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.88) else { router.toast = "Bild konnte nicht gelesen werden"; return }
                let d = (try? await API.upload("/api/avatar_upload.php", field: "file", filename: "avatar.jpg", mime: "image/jpeg", data: jpg)) ?? [:]
                if d.b("ok") { await store.refreshMe(); router.toast = "Profilbild gespeichert" } else { router.toast = d.s("error").isEmpty ? "Upload fehlgeschlagen" : d.s("error") }
            }
        }
        #endif
        .alert(confirm.map { "\($0.1)?" } ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("Leeren", role: .destructive) { guard let c = confirm else { return }; Task { router.toast = await store.clearProgress(c.0) ? "\(c.1): erledigt" : "Konnte nicht geleert werden" } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    func member() {
        Task {
            let d = await API.postObj("/api/membership.php", ["action": "checkout"])
            if d.s("checkout_url").isEmpty { router.toast = "Abo konnte nicht gestartet werden" } else { router.browser(d.s("checkout_url")) }
        }
    }
}

// MARK: - Anmelden / Registrieren / Passwort vergessen

struct LoginView: View {
    @State var register: Bool
    init(register: Bool) { _register = State(initialValue: register) }
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var pass = ""
    @State private var pass2 = ""
    @State private var busy = false
    @State private var err: String?
    @State private var emailForm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack { BackButton(); Spacer() }.padding(.vertical, 16)
                HStack(spacing: 10) { BrandMark(size: 36 * FF.scale); Text("FilmFrei24").font(.inter(26, .heavy)).foregroundColor(.white) }.padding(.bottom, 24)
                #if os(tvOS)
                if !register && !emailForm {
                    TVQRLogin().padding(.vertical, 30)
                    Button { emailForm = true } label: { Text("Stattdessen mit E-Mail anmelden") }
                        .buttonStyle(TVActionStyle()).padding(.top, 10)
                } else { form }
                #else
                form
                #endif
            }.padding(.horizontal, FF.pad).frame(maxWidth: loginWidth)
        }
        .frame(maxWidth: .infinity)
        .background(FF.bg.ignoresSafeArea())
        .onChange(of: store.user?.id) { id in if id != nil { dismiss() } }
    }

    @ViewBuilder private var form: some View {
                BoxCard {
                    Text(register ? "Konto erstellen" : "Anmelden").font(.inter(24, .bold)).foregroundColor(.white)
                    Text(register ? "Kostenlos – Fortschritt, Merkliste & Wünsche auf allen Geräten." : "Willkommen zurück!").font(.inter(15)).foregroundColor(FF.text2).padding(.top, 4).padding(.bottom, 8)
                    if let err { Text(err).foregroundColor(Color(hex: 0xFF8A8D)).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0xE5484D, alpha: 0.16))).padding(.top, 8) }
                    if register { Label2("Name"); Field(placeholder: "", text: $name) }
                    Label2("E-Mail"); Field(placeholder: "", text: $email)
                    Label2("Passwort"); Field(placeholder: "", text: $pass, secure: true)
                    if register { Label2("Passwort bestätigen"); Field(placeholder: "", text: $pass2, secure: true) }
                    Cta(label: busy ? "Bitte warten …" : register ? "Konto erstellen" : "Anmelden", icon: nil, height: 48) { submit() }.padding(.top, 18)
                    #if os(iOS)
                    HStack { FF.line.frame(height: 1); Text("oder").foregroundColor(FF.text2); FF.line.frame(height: 1) }.padding(.vertical, 16)
                    Button { router.googleLogin() } label: {
                        HStack(spacing: 6) { Text("G").font(.inter(16, .heavy)).foregroundColor(Color(hex: 0x4285F4)); Text("Mit Google " + (register ? "registrieren" : "anmelden")).font(.inter(16, .semibold)).foregroundColor(.white) }
                            .frame(maxWidth: .infinity, minHeight: 48).background(RoundedRectangle(cornerRadius: 8).fill(FF.btn))
                    }.buttonStyle(PressStyle())
                    #endif
                    if !register {
                        Button("Passwort vergessen?") { router.go(.forgot) }.font(.inter(15)).foregroundColor(FF.text2).frame(maxWidth: .infinity).padding(.top, 16)
                    }
                }
                Button { register.toggle(); err = nil } label: {
                    (Text(register ? "Schon ein Konto? " : "Neu bei FilmFrei24? ").foregroundColor(.white) + Text(register ? "Anmelden" : "Konto erstellen").foregroundColor(FF.blue).fontWeight(.semibold)).font(.inter(15))
                }.buttonStyle(FocusStyle()).padding(12)
    }

    #if os(tvOS)
    private var loginWidth: CGFloat { emailForm || register ? 760 : 1400 }
    #else
    private var loginWidth: CGFloat { 560 }
    #endif

    func submit() {
        guard !busy else { return }
        if register && name.trimmingCharacters(in: .whitespaces).count < 2 { err = "Name zu kurz."; return }
        if !email.contains("@") { err = "Bitte gültige E-Mail eingeben."; return }
        if register && pass.count < 6 { err = "Passwort mindestens 6 Zeichen."; return }
        if register && pass != pass2 { err = "Passwörter stimmen nicht überein."; return }
        if pass.isEmpty { err = "Bitte Passwort eingeben."; return }
        busy = true
        Task {
            do {
                if register { try await store.register(name: name.trimmingCharacters(in: .whitespaces), email: email.trimmingCharacters(in: .whitespaces), password: pass) }
                else { try await store.login(email: email.trimmingCharacters(in: .whitespaces), password: pass) }
                if store.user == nil { err = "Anmeldung fehlgeschlagen." }
            } catch { err = error.localizedDescription }
            busy = false
        }
    }
}

struct ForgotView: View {
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var p1 = ""
    @State private var p2 = ""
    @State private var stage = 0
    @State private var busy = false
    @State private var msg: (Bool, String)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SubHead(title: "Passwort vergessen")
                BoxCard {
                    Text(stage == 0 ? "Gib deine E-Mail ein. Wir schicken dir einen Code." : "Gib den Code aus der E-Mail und dein neues Passwort ein.").font(.inter(15)).foregroundColor(FF.text2)
                    if let mm = msg {
                        let ok = mm.0, t = mm.1
                        Text(t).foregroundColor(ok ? FF.green : Color(hex: 0xFF8A8D)).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(ok ? Color(hex: 0x1FB36B, alpha: 0.18) : Color(hex: 0xE5484D, alpha: 0.16))).padding(.top, 12)
                    }
                    Label2("E-Mail"); Field(placeholder: "", text: $email)
                    if stage == 1 {
                        Label2("Code"); Field(placeholder: "", text: $code)
                        Label2("Neues Passwort"); Field(placeholder: "", text: $p1, secure: true)
                        Label2("Neues Passwort wiederholen"); Field(placeholder: "", text: $p2, secure: true)
                    }
                    Cta(label: busy ? "Bitte warten …" : stage == 0 ? "Code senden" : "Passwort speichern", icon: nil, height: 48) { go() }.padding(.top, 18)
                }.padding(.horizontal, FF.pad)
            }
        }.background(FF.bg.ignoresSafeArea())
    }

    func go() {
        guard !busy else { return }
        if stage == 1 && p1 != p2 { msg = (false, "Die Passwörter stimmen nicht überein."); return }
        busy = true
        Task {
            let r = stage == 0
                ? await API.postObj("/api/app.php?action=reset_request", ["email": email.trimmingCharacters(in: .whitespaces)])
                : await API.postObj("/api/app.php?action=reset_confirm", ["email": email.trimmingCharacters(in: .whitespaces), "code": code.trimmingCharacters(in: .whitespaces), "password": p1])
            busy = false
            if !r.b("ok") { msg = (false, r.s("error").isEmpty ? "Fehler" : r.s("error")); return }
            if stage == 0 { stage = 1; msg = (true, r.s("message")) } else { router.toast = "Passwort geändert – bitte anmelden."; dismiss() }
        }
    }
}

// MARK: - Nachrichten

struct MessagesView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var list: [J]? = nil
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SubHead(title: "Nachrichten", back: false)
                if store.user == nil {
                    EmptyState(title: "Melde dich an", text: "Deine Nachrichten (neue Filme, Antworten vom Support …) siehst du nach dem Anmelden.") {
                        Cta(label: "Anmelden", icon: nil, height: 48) { router.go(.login(register: false)) }.frame(maxWidth: 260)
                    }
                } else if let l = list {
                    if l.isEmpty { EmptyState(title: "Keine Nachrichten", text: "Hier erscheinen neue Filme, Folgen und Antworten auf deine Anfragen.") }
                    else {
                        HStack(spacing: 10) {
                            GreyButton(label: "Alle als gelesen markieren") {
                                Task { _ = await API.postObj("/api/inbox.php", ["action": "mark_all_read"]); await load(); await store.refreshUnread() }
                            }
                            GreyButton(label: "Alle löschen") { confirmClear = true }
                        }.padding(.horizontal, FF.pad).padding(.bottom, 14)
                        ForEach(l.prefix(300).indices, id: \.self) { i in row(l[i]) }
                    }
                } else { FF.skel.frame(height: 80).clipShape(RoundedRectangle(cornerRadius: 10)).padding(FF.pad) }
            }.padding(.bottom, 110)
        }
        .background(FF.bg.ignoresSafeArea())
        .task(id: store.user?.id) { await load() }
        .alert("Alle Nachrichten löschen?", isPresented: $confirmClear) {
            Button("Löschen", role: .destructive) { Task { _ = await API.postObj("/api/inbox.php", ["action": "clear_all"]); await load(); await store.refreshUnread() } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    func load() async { if store.user != nil { list = await API.getObj("/api/inbox.php").a("messages") } }

    func row(_ m: J) -> some View {
        let target = msgTarget(m.s("url"))
        let text = m.s("text").isEmpty ? ((m["extras"] as? [String]) ?? []).joined(separator: "\n") : m.s("text")
        return Button {
            if !m.b("read") && !m.s("id").hasPrefix("film_update_") {
                Task { _ = await API.postObj("/api/inbox.php", ["action": "mark_read", "message_id": m.s("id")]); await load(); await store.refreshUnread() }
            }
            switch target {
            case .item(let it): router.open(it)
            case .ticket(let id): router.go(.ticket(id))
            case .route(let r): router.route(r)
            case .none: break
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(m.b("read") ? Color.clear : FF.blue).frame(width: 9, height: 9).padding(.top, 7)
                ZStack { FF.surface; if let it = target.item { Img(url: it.card, fallback: it.poster) } }
                    .frame(width: 84 * FF.scale, height: 47 * FF.scale).clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 4) {
                    (Text(m.s("from").isEmpty ? "FilmFrei24" : m.s("from")).fontWeight(.bold) + Text(m.d("time").map { "  " + dfmt($0) } ?? "").foregroundColor(FF.text3).font(.inter(12)))
                        .font(.inter(15)).foregroundColor(.white)
                    Text(md(text)).font(.inter(15)).foregroundColor(Color(hex: 0xD6DADE)).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }.padding(16).background(RoundedRectangle(cornerRadius: 10).fill(FF.box))
        }.buttonStyle(FocusStyle()).padding(.horizontal, FF.pad).padding(.bottom, 8)
    }

    enum Target {
        case item(Item), ticket(String), route(String), none
        var item: Item? { if case .item(let i) = self { return i }; return nil }
    }

    func msgTarget(_ u: String) -> Target {
        guard !u.isEmpty else { return .none }
        if let r = u.range(of: "player/?") {
            let q = URLComponents(string: "x://y/?" + u[r.upperBound...])?.queryItems ?? []
            if let s = q.first(where: { $0.name == "s" })?.value {
                let series = q.first(where: { $0.name == "type" })?.value == "series"
                if let it = store.web.by[(series ? "s:" : "f:") + s] { return .item(it) }
            }
        }
        if let r = u.range(of: #"/serien/\?id=([^&]+)"#, options: .regularExpression) {
            let id = String(u[r]).replacingOccurrences(of: "/serien/?id=", with: "").removingPercentEncoding ?? ""
            if let it = store.web.by["s:" + id] { return .item(it) }
        }
        if let r = u.range(of: #"/support/\?id=([^&]+)"#, options: .regularExpression) {
            return .ticket(String(u[r]).replacingOccurrences(of: "/support/?id=", with: "").removingPercentEncoding ?? "")
        }
        if u.contains("/support/") { return .route("support") }
        if u.contains("/wishlist") { return .route("wuensche") }
        return .none
    }
}

func dfmt(_ ts: Double) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "d. MMM yyyy, HH:mm"
    return f.string(from: Date(timeIntervalSince1970: ts))
}

/// **fett** wie mdText()
func md(_ t: String) -> AttributedString {
    (try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(t)
}


#if os(tvOS)

/// 2026-10-20: Fernseher-Login per QR-Code -- Handy scannt, meldet sich auf filmfrei24.com an und
/// bestätigt; der Fernseher fragt alle 2 s nach (api/app.php tv_start / tv_poll). Code gilt 10 Min.
struct TVQRLogin: View {
    @EnvironmentObject var store: Store
    @State private var code = ""
    @State private var url = ""
    @State private var err: String?

    var body: some View {
        HStack(alignment: .center, spacing: 56) {
            Group {
                if let img = qrImage(url) {
                    Image(uiImage: img).interpolation(.none).resizable().frame(width: 380, height: 380)
                } else {
                    ProgressView().frame(width: 380, height: 380)
                }
            }
            .padding(18).background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            VStack(alignment: .leading, spacing: 18) {
                Text("Mit dem Handy anmelden").font(.tv(46, .bold)).foregroundColor(.white)
                Text("1.  QR-Code mit der Handy-Kamera scannen\n2.  Auf filmfrei24.com anmelden (falls nötig)\n3.  „Ja, anmelden“ tippen – fertig")
                    .font(.tv(30)).foregroundColor(FF.text2).lineSpacing(10)
                if !code.isEmpty {
                    Text("Code: \(code)").font(.tv(34, .heavy)).foregroundColor(.white).padding(.top, 6)
                }
                if let err { Text(err).font(.tv(26)).foregroundColor(Color(hex: 0xFF8A8D)) }
            }
            Spacer(minLength: 0)
        }
        .task { await loop() }
    }

    private func loop() async {
        while !Task.isCancelled && store.user == nil {
            let s = await API.postObj("/api/app.php?action=tv_start", [:])
            guard s.b("ok"), !s.s("poll").isEmpty else {
                err = "Keine Verbindung – neuer Versuch …"
                try? await Task.sleep(nanoseconds: 5_000_000_000); continue
            }
            code = s.s("code"); url = s.s("url"); err = nil
            let poll = s.s("poll"), until = Date().addingTimeInterval(570)
            while Date() < until && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let r = await API.postObj("/api/app.php?action=tv_poll", ["poll": poll])
                if r.b("ok") { store.apply(me: r); return }
                if r["expired"] != nil { break }
            }
        }
    }

    private func qrImage(_ s: String) -> UIImage? {
        guard !s.isEmpty else { return nil }
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(s.utf8); f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
#endif
