import SwiftUI
#if os(iOS)
import AuthenticationServices
#endif

enum Route: Hashable {
    case title(String)                       // Item.key
    case list(kind: String, g: String, s: String)
    case cont, settings, support, ticket(String), iptv, forgot, login(register: Bool)
}

struct PlayRequest: Identifiable {
    let id = UUID()
    var type = "f", itemId = "", season = 1, ep = 1
    var start: Double = -1
    var trailer: (url: String, title: String)? = nil
}

/// Navigation + Abspielen, wie Nav in der Android-App.
@MainActor
final class Router: ObservableObject {
    @Published var tab = "home"
    @Published var path = NavigationPath()
    @Published var play: PlayRequest?
    @Published var toast: String?
    @Published var menuFor: Item?

    func open(_ it: Item) { path.append(Route.title(it.key)) }
    func list(_ kind: String, g: String = "", s: String = "") { path.append(Route.list(kind: kind, g: g, s: s)) }
    func go(_ r: Route) { path.append(r) }
    func switchTab(_ t: String) { tab = t; path = NavigationPath() }

    func route(_ r: String) {
        switch r {
        case "filme", "serien":
            #if os(tvOS)
            switchTab(r)
            #else
            list(r)
            #endif
        case "weiterschauen": go(.cont)
        case "support": go(.support)
        case "iptv": go(.iptv)
        case "wuensche", "konto", "nachrichten", "suche", "home": switchTab(r)
        default: switchTab("home")
        }
    }

    func playItem(_ it: Item) {
        Task {
            let s = Store.shared
            guard let t = await s.playTarget(it) else { toast = "Noch keine Folgen verfügbar."; return }
            play = it.isSeries ? PlayRequest(type: "s", itemId: it.id, season: t.season, ep: t.ep, start: t.start)
                               : PlayRequest(type: "f", itemId: it.id, start: t.start)
        }
    }
    func playEpisode(_ id: String, _ s: Int, _ e: Int, start: Double) { play = PlayRequest(type: "s", itemId: id, season: s, ep: e, start: start) }
    func trailer(_ it: Item, _ url: String) { play = PlayRequest(trailer: (url, it.title)) }

    /// Nur Google-Login und Stripe-Bezahlseite gehen in den Browser.
    func browser(_ url: String) {
        #if os(iOS)
        if let u = URL(string: url) { UIApplication.shared.open(u) }
        #endif
    }

    #if os(iOS)
    private var authSession: ASWebAuthenticationSession?
    private let ctxProvider = AuthContext()
    func googleLogin() {
        let s = ASWebAuthenticationSession(url: URL(string: "\(BASE)/api/app.php?action=google_start")!, callbackURLScheme: "filmfrei24") { url, _ in
            guard let url, let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
                Task { @MainActor in self.toast = "Google-Anmeldung abgebrochen." }; return
            }
            Task { @MainActor in
                do { try await Store.shared.redeem(code: code); self.toast = "Angemeldet als \(Store.shared.user?.name ?? "")"; if !self.path.isEmpty { self.path.removeLast() } }
                catch { self.toast = error.localizedDescription }
            }
        }
        s.presentationContextProvider = ctxProvider
        s.prefersEphemeralWebBrowserSession = false
        authSession = s
        s.start()
    }
    #endif
}

#if os(iOS)
final class AuthContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }
}
#endif

@main
struct FF24App: App {
    @StateObject private var store = Store.shared
    @StateObject private var router = Router()
    @Environment(\.scenePhase) private var phase

    init() {
        URLCache.shared = URLCache(memoryCapacity: 80 << 20, diskCapacity: 400 << 20, diskPath: "ff24-images")   // Bilder
    }

    var body: some Scene {
        WindowGroup {
            GeometryReader { g in
                Root()
                    .environment(\.screenWidth, g.size.width)
            }
            .environmentObject(store)
            .environmentObject(router)
            .preferredColorScheme(.dark)
            .onChange(of: phase) { p in if p == .active { Task { await store.refreshMe() } } }
            .modifier(UpdateCheck())
        }
    }
}

/// 2026-10-20: bei jedem Start prüfen, ob auf tv.filmfrei24.com eine neuere Version liegt
/// (app-version.json) -> "Weiter nutzen" oder "Update" (lädt direkt die neue IPA).
struct UpdateCheck: ViewModifier {
    @State private var newer: (name: String, url: String)?
    @State private var show = false
    func body(content: Content) -> some View {
        content
            .task {
                guard let u = URL(string: "https://tv.filmfrei24.com/app-version.json"),
                      let (d, _) = try? await URLSession.shared.data(from: u),
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let k = o["ios"] as? [String: Any],
                      let build = (k["build"] as? NSNumber)?.intValue else { return }
                let mine = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
                if build > mine {
                    newer = ((k["name"] as? String) ?? "", (k["url"] as? String) ?? "https://tv.filmfrei24.com/ipa")
                    show = true
                }
            }
            .alert("Neue Version verfügbar", isPresented: $show) {
                #if os(tvOS)
                Button("OK", role: .cancel) {}
                #else
                Button("Weiter nutzen", role: .cancel) {}
                Button("Update") { if let n = newer, let u = URL(string: n.url) { UIApplication.shared.open(u) } }
                #endif
            } message: {
                #if os(tvOS)
                Text("FilmFrei24 \(newer?.name ?? "") ist da. Lade die neue Apple-TV-Version auf filmfrei24.com unter „App“ herunter und installiere sie wie beim ersten Mal.")
                #else
                Text("FilmFrei24 \(newer?.name ?? "") ist da. Lade die neue Version herunter und installiere sie wie gewohnt mit Sideloadly.")
                #endif
            }
    }
}

struct Root: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router

    var body: some View {
        #if os(tvOS)
        // Fernseher: Reiter oben (tvOS-Standard), Detailseiten legen sich darüber
        stack {
            TabView(selection: $router.tab) {
                HomeView().tabItem { Text("Start") }.tag("home")
                ListView(kind: "filme", g: "", s: "").tabItem { Text("Filme") }.tag("filme")
                ListView(kind: "serien", g: "", s: "").tabItem { Text("Serien") }.tag("serien")
                SearchView().tabItem { Image(systemName: "magnifyingglass") }.tag("suche")
                WishesView().tabItem { Text("Wünsche") }.tag("wuensche")
                MessagesView().tabItem { Image(systemName: "bell") }.tag("nachrichten")
                AccountView().tabItem { Text("Konto") }.tag("konto")
            }
        }
        .background(FF.bg.ignoresSafeArea())
        .fullScreenCover(item: $router.play) { PlayerView(req: $0) }
        .toast($router.toast)
        #else
        ZStack(alignment: .bottom) {
            stack {
                switch router.tab {
                case "wuensche": WishesView()
                case "konto": AccountView()
                case "nachrichten": MessagesView()
                case "suche": SearchView()
                default: HomeView()
                }
            }
            if !isLoginRoute { TabBar() }
        }
        .background(FF.bg.ignoresSafeArea())
        .fullScreenCover(item: $router.play) { PlayerView(req: $0) }
        .sheet(item: $router.menuFor) { ContinueMenu(it: $0).presentationDetents([.height(260)]) }
        .toast($router.toast)
        .onOpenURL { _ in }   // filmfrei24://login läuft über ASWebAuthenticationSession
        #endif
    }

    private var isLoginRoute: Bool { false }

    @ViewBuilder
    private func stack<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        NavigationStack(path: $router.path) {
            c()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { r in
                    Group {
                        switch r {
                        case .title(let k): DetailView(key: k)
                        case .list(let kind, let g, let s): ListView(kind: kind, g: g, s: s)
                        case .cont: ContinueView()
                        case .settings: SettingsView()
                        case .support: SupportView()
                        case .ticket(let id): TicketView(id: id)
                        case .iptv: IptvView()
                        case .forgot: ForgotView()
                        case .login(let reg): LoginView(register: reg)
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
        }
        .background(FF.bg.ignoresSafeArea())
    }
}

#if os(iOS)
/// Schwebende Pille unten: Start, Wünsche, Konto, Nachrichten, Suche (wie Website-Handy).
struct TabBar: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    var body: some View {
        HStack(spacing: 0) {
            ForEach(["home", "wuensche", "konto", "nachrichten", "suche"], id: \.self) { t in
                let on = router.tab == t && router.path.isEmpty
                Button { router.switchTab(t) } label: {
                    ZStack(alignment: .topTrailing) {
                        Group {
                            switch t {
                            case "home": Image(systemName: "house")
                            case "wuensche": Image(systemName: "star")
                            case "konto": Avatar(user: store.user, size: 30)
                            case "nachrichten": Image(systemName: "bell")
                            default: Image(systemName: "magnifyingglass")
                            }
                        }
                        .font(.system(size: 22, weight: .medium)).foregroundColor(on ? FF.blue : Color(hex: 0xE8EBEE))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Capsule().fill(on ? Color(hex: 0x0B0F15) : .clear))
                        if t == "nachrichten" && store.unread > 0 {
                            Text(store.unread > 99 ? "99+" : "\(store.unread)").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                                .padding(.horizontal, 4).frame(minWidth: 17, minHeight: 17).background(Capsule().fill(FF.red)).offset(x: -16, y: 4)
                        }
                    }
                }.buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 6).frame(height: 62)
        .background(Capsule().fill(Color(hex: 0x1E242C, alpha: 0.92)).background(.ultraThinMaterial, in: Capsule()))
        .overlay(Capsule().stroke(Color.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.55), radius: 15, y: 8)
        .padding(.horizontal, 16).padding(.bottom, 10)
    }
}
#endif
