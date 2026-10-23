import SwiftUI

// MARK: - Farben/Schrift 1:1 wie filmfrei24.com

enum FF {
    static let soon = Color(hex: 0xF59E0B)   // Bald-Kennzeichnung wie Website
    static let bg = Color(hex: 0x00050D)
    static let surface = Color(hex: 0x191E25)
    static let box = Color(hex: 0x14191F)
    static let field = Color(hex: 0x232A33)
    static let btn = Color(hex: 0x33373D)
    static let btn2 = Color(hex: 0x4A4F56)
    static let sheet = Color(hex: 0x1B2027)
    static let skel = Color(hex: 0x141A21)
    static let line = Color.white.opacity(0.14)
    static let text2 = Color(hex: 0xAEB3B8)
    static let text3 = Color(hex: 0x8197A4)
    static let rowTitle = Color(hex: 0xC9CED3)
    static let meta = Color(hex: 0x8D939A)
    static let blue = Color(hex: 0x1A98FF)
    static let green = Color(hex: 0x4ADE80)
    static let red = Color(hex: 0xE5484D)
    static let yellow = Color(hex: 0xF2C94C)
    static let dark = Color(hex: 0x0F171E)
    static let rank = Color(hex: 0x2B333D)
    static let violet1 = Color(hex: 0xA855F7)
    static let violet2 = Color(hex: 0x7C3AED)

    #if os(tvOS)
    static let scale: CGFloat = 1.9
    static let pad: CGFloat = 80
    #else
    static let scale: CGFloat = 1
    static let pad: CGFloat = 16
    #endif
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

extension Font {
    static func inter(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        let name: String
        switch w {
        case .medium: name = "Inter-Medium"
        case .semibold: name = "Inter-SemiBold"
        case .bold: name = "Inter-Bold"
        case .heavy: name = "Inter-ExtraBold"
        case .black: name = "Inter-Black"
        default: name = "Inter-Regular"
        }
        return .custom(name, size: size * FF.scale)
    }
}

/// Karten-Breite wie --card am Handy: (Breite - 56) / 3.12; Fernseher: 6 Karten.
func cardWidth(_ w: CGFloat) -> CGFloat {
    #if os(tvOS)
    return (w - FF.pad * 2 - 40 * 5) / 6.3
    #else
    return w >= 600 ? (w - 32 - 36) / 4.16 : (w - 56) / 3.12
    #endif
}

// MARK: - Tippen/Fokus (iPhone: ohne Effekt, Apple TV: Fokus-Anhebung)

struct Tap<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    var body: some View {
        #if os(tvOS)
        Button(action: action) { content }.buttonStyle(.card)
        #else
        Button(action: action) { content.contentShape(Rectangle()) }.buttonStyle(PressStyle())
        #endif
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Knöpfe: auf dem Fernseher mit Fokus-Rahmen.
struct FocusStyle: ButtonStyle {
    #if os(tvOS)
    @Environment(\.isFocused) var focused
    #endif
    func makeBody(configuration: Configuration) -> some View {
        #if os(tvOS)
        configuration.label.scaleEffect(focused ? 1.06 : 1).shadow(color: .black.opacity(focused ? 0.6 : 0), radius: 14)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white, lineWidth: focused ? 3 : 0)).animation(.easeOut(duration: 0.15), value: focused)
        #else
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
        #endif
    }
}

// MARK: - Bilder: dunkle Fläche, weich einblenden, nie ein kaputtes Symbol

struct Img: View {
    let url: String
    var fallback: String = ""
    var mode: ContentMode = .fill
    var align: Alignment = .center
    var onFail: (() -> Void)? = nil
    @State private var useFallback = false

    var body: some View {
        let u = (useFallback || url.isEmpty) ? fallback : url
        AsyncImage(url: URL(string: u), transaction: Transaction(animation: .easeOut(duration: 0.3))) { phase in
            switch phase {
            case .success(let img):
                // nimmt nur den vorgegebenen Platz ein; bei .fill wird der Ueberstand abgeschnitten (2026-10-20)
                Color.clear.overlay(alignment: align) { img.resizable().aspectRatio(contentMode: mode) }.clipped().transition(.opacity)
            case .failure: Color.clear.onAppear { if !useFallback && !fallback.isEmpty { useFallback = true } else { onFail?() } }
            default: Color.clear
            }
        }
    }
}

/// Logo-Bild, sonst Titel als Text.
struct LogoOrTitle: View {
    let it: Item
    var size: CGFloat = 14
    var align: Alignment = .bottomLeading
    @State private var failed = false
    var body: some View {
        if it.logo.isEmpty || failed {
            Text(it.title).font(.inter(size, .heavy)).foregroundColor(.white).lineLimit(2).shadow(color: .black.opacity(0.9), radius: 6, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align)
        } else {
            AsyncImage(url: URL(string: it.logo)) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fit)
                case .failure: Color.clear.onAppear { failed = true }
                default: Color.clear
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align)
        }
    }
}

// MARK: - Karten

struct Badge: View {
    let text: String
    var body: some View {
        if !text.isEmpty {
            Text(text.uppercased()).font(.inter(10.5, .bold)).foregroundColor(FF.dark).lineLimit(1).fixedSize()
                .padding(.horizontal, 6 * FF.scale).padding(.vertical, 3 * FF.scale)
                .background(UnevenCorners(tr: 8, bl: 6).fill(isSoonBadge(text.uppercased()) ? FF.soon : Color.white))
        }
    }
}

struct UnevenCorners: Shape {
    var tr: CGFloat, bl: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + tr), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - bl), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct ProgressLine: View {
    let pct: Int
    var height: CGFloat = 5
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Color.white.opacity(0.28)
                FF.blue.frame(width: g.size.width * CGFloat(min(100, max(2, pct))) / 100)
            }
        }.frame(height: height)
    }
}

/// .card.p – Hochformat-Poster
struct PosterCard: View {
    let it: Item
    var badge = ""
    var pct: Int? = nil
    var body: some View {
        ZStack(alignment: .topTrailing) {
            FF.surface
            Img(url: it.poster, fallback: it.card)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: UnitPoint(x: 0.5, y: 0.6), endPoint: .bottom)
            Badge(text: badge)
            if let pct { VStack { Spacer(); ProgressLine(pct: pct) } }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// .card – Querformat mit Logo unten links
struct LandCard: View {
    let it: Item
    var badge = ""
    var pct: Int? = nil
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topTrailing) {
                FF.surface
                Img(url: it.card, fallback: it.poster).frame(width: g.size.width, height: g.size.height).clipped()
                LinearGradient(stops: [.init(color: .black.opacity(0.72), location: 0), .init(color: .black.opacity(0.2), location: 0.38), .init(color: .clear, location: 0.6)],
                               startPoint: .bottomLeading, endPoint: UnitPoint(x: 0.34, y: 0))
                LogoOrTitle(it: it)
                    .frame(width: g.size.width * 0.58, height: g.size.height * 0.40)
                    .position(x: g.size.width * 0.08 + g.size.width * 0.29, y: g.size.height * 0.91 - g.size.height * 0.20)
                Badge(text: badge)
                if let pct { VStack { Spacer(); ProgressLine(pct: pct) } }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Reihen

struct RowHead: View {
    let title: String
    var more: (() -> Void)? = nil
    var body: some View {
        Button { more?() } label: {
            HStack(spacing: 2) {
                Text(title).font(.inter(18, .semibold)).foregroundColor(FF.rowTitle)
                if more != nil { Image(systemName: "chevron.right").font(.system(size: 15 * FF.scale, weight: .semibold)).foregroundColor(FF.rowTitle) }
            }
        }
        .buttonStyle(PressStyle()).disabled(more == nil)
        .padding(.horizontal, FF.pad).padding(.bottom, 10)
    }
}

struct PosterRow: View {
    let title: String
    let items: [Item]
    var more: (() -> Void)? = nil
    let open: (Item) -> Void
    @EnvironmentObject var store: Store
    @Environment(\.screenWidth) var sw

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                RowHead(title: title, more: more)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12 * FF.scale) {
                        ForEach(items) { it in
                            Tap(action: { open(it) }) { PosterCard(it: it, badge: store.web.badge(it)).frame(width: cardWidth(sw)) }
                        }
                    }.padding(.horizontal, FF.pad).padding(.vertical, FF.scale > 1 ? 30 : 0)
                }
            }.padding(.bottom, 28)
        }
    }
}

struct TopRow: View {
    let items: [Item]
    let open: (Item) -> Void
    @Environment(\.screenWidth) var sw
    var body: some View {
        if !items.isEmpty {
            let c = cardWidth(sw)
            VStack(alignment: .leading, spacing: 0) {
                RowHead(title: "Die Top 10 in Deutschland")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12 * FF.scale) {
                        ForEach(Array(items.enumerated()), id: \.element.key) { i, it in
                            HStack(alignment: .bottom, spacing: 0) {
                                Text("\(i + 1)").font(.system(size: c * 0.9, weight: .black)).foregroundColor(FF.rank)
                                    .shadow(color: .white.opacity(0.25), radius: 1).lineLimit(1).fixedSize()
                                    .frame(width: c * 0.5, alignment: .trailing).offset(y: c * 0.12)
                                Tap(action: { open(it) }) { LandCard(it: it).frame(width: c * 2.05) }.offset(x: -c * 0.03)
                            }.frame(width: c * 2.55, alignment: .leading)
                        }
                    }.padding(.horizontal, FF.pad).padding(.vertical, FF.scale > 1 ? 30 : 0)
                }
            }.padding(.bottom, 28)
        }
    }
}

struct ContinueRow: View {
    let items: [(Item, WatchProgress)]
    let more: () -> Void
    let play: (Item) -> Void
    let menu: (Item) -> Void
    @Environment(\.screenWidth) var sw
    var body: some View {
        if !items.isEmpty {
            let w: CGFloat = FF.scale > 1 ? cardWidth(sw) * 1.6 : (sw - 44) / 2.15
            VStack(alignment: .leading, spacing: 0) {
                RowHead(title: "Weiterschauen", more: more)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12 * FF.scale) {
                        ForEach(items, id: \.0.key) { it, p in
                            VStack(alignment: .leading, spacing: 0) {
                                Tap(action: { play(it) }) { LandCard(it: it, pct: p.pct).frame(width: w) }
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(it.title).font(.inter(15, .semibold)).foregroundColor(.white).lineLimit(1)
                                        let sub = contSub(it, p)
                                        if !sub.isEmpty { Text(sub).font(.inter(13)).foregroundColor(FF.text2).lineLimit(1) }
                                    }.padding(.top, 8)
                                    Spacer(minLength: 0)
                                    #if !os(tvOS)
                                    Button { menu(it) } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)).foregroundColor(FF.text2).frame(width: 36, height: 40) }
                                    #endif
                                }.frame(width: w)
                            }
                        }
                    }.padding(.horizontal, FF.pad).padding(.vertical, FF.scale > 1 ? 30 : 0)
                }
            }.padding(.bottom, 28)
        }
    }
}

func contSub(_ it: Item, _ p: WatchProgress) -> String {
    let left = (p.pct > 0 && p.pct < 100 && p.pos > 0) ? max(1, Int((p.pos * Double(100 - p.pct) / Double(p.pct) / 60).rounded())) : 0
    return [it.isSeries && p.season != nil ? "S\(p.season!) F\(p.episode ?? 1)" : "", left > 0 ? "Noch " + mfmt(left) : ""].filter { !$0.isEmpty }.joined(separator: " · ")
}

/// .grid – 3 Spalten Handy, 6 Fernseher
struct PosterGrid: View {
    let items: [Item]
    var land = false
    var pctOf: ((Item) -> Int?)? = nil
    let open: (Item) -> Void
    @EnvironmentObject var store: Store
    @Environment(\.screenWidth) var sw
    var body: some View {
        let cols = FF.scale > 1 ? 6 : (sw >= 600 ? 5 : 3)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10 * FF.scale), count: cols), spacing: 18 * FF.scale) {
            ForEach(items) { it in
                Tap(action: { open(it) }) {
                    if land { LandCard(it: it, pct: pctOf?(it)) } else { PosterCard(it: it, badge: pctOf == nil ? store.web.badge(it) : "", pct: pctOf?(it)) }
                }
            }
        }.padding(.horizontal, FF.pad)
    }
}

/// .lrow – Treffer/Konto-Listen
struct ListRow: View {
    let it: Item
    var pct: Int? = nil
    var trailing: AnyView? = nil
    let open: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Tap(action: open) { LandCard(it: it, pct: pct).frame(width: (trailing != nil ? 132 : 150) * FF.scale) }
            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(it.title).font(.inter(17, .semibold)).foregroundColor(.white).multilineTextAlignment(.leading)
                    Text([it.year, it.isSeries ? seasonsText(it.seasons) : mfmt(it.min)].filter { !$0.isEmpty }.joined(separator: "  "))
                        .font(.inter(15)).foregroundColor(FF.text2)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(PressStyle())
            if let trailing { trailing }
        }.padding(.vertical, 8)
    }
}

// MARK: - Hero

struct Hero: View {
    let list: [Item]
    let open: (Item) -> Void
    let play: (Item) -> Void
    @EnvironmentObject var store: Store
    @State private var cur = 0
    private let timer = Timer.publish(every: 9, on: .main, in: .common).autoconnect()

    var body: some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                TabView(selection: $cur) {
                    ForEach(Array(list.enumerated()), id: \.element.key) { i, it in
                        Tap(action: { open(it) }) {
                            ZStack(alignment: .bottomLeading) {
                                Color.black
                                Img(url: it.hero.isEmpty ? it.card : it.hero, fallback: it.poster)
                                LinearGradient(colors: [.clear, FF.bg.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                                LogoOrTitle(it: it, size: 26).frame(maxWidth: .infinity, maxHeight: 64 * FF.scale, alignment: .bottomLeading)
                                    .frame(maxWidth: 260 * FF.scale, alignment: .leading).padding(.leading, 14 * FF.scale).padding(.bottom, 12 * FF.scale)
                                HStack {
                                    Spacer()
                                    Button { play(it) } label: {
                                        Image(systemName: "play.fill").font(.system(size: 22 * FF.scale)).foregroundColor(FF.dark).offset(x: 2)
                                            .frame(width: 48 * FF.scale, height: 48 * FF.scale).background(Circle().fill(Color.white)).shadow(color: .black.opacity(0.5), radius: 7, y: 4)
                                    }.buttonStyle(PressStyle()).padding(12 * FF.scale)
                                }
                            }.clipShape(RoundedRectangle(cornerRadius: 12))
                        }.tag(i).padding(.horizontal, FF.pad)
                    }
                }
                #if os(tvOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #else
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
                .aspectRatio(FF.scale > 1 ? 16 / 6 : 4 / 2.6, contentMode: .fit)

                let it = list[min(cur, list.count - 1)]
                HStack(spacing: 10) {
                    let parts = [it.isSeries ? seasonsText(it.seasons) : mfmt(it.min), it.year, it.genres.first ?? ""].filter { !$0.isEmpty }
                    ForEach(Array(parts.enumerated()), id: \.offset) { i, s in
                        if i > 0 { Text("·").foregroundColor(Color(hex: 0xD7DBDF).opacity(0.5)) }
                        Text(s).foregroundColor(Color(hex: 0xD7DBDF))
                    }
                    if store.web.isTop(it) {
                        Text("·").foregroundColor(Color(hex: 0xD7DBDF).opacity(0.5))
                        Text("Nr. \(store.web.rank(it) + 1) in Deutschland").foregroundColor(FF.green).fontWeight(.bold)
                    }
                }.font(.inter(15)).lineLimit(1).padding(.horizontal, FF.pad).padding(.top, 14)
                HStack(spacing: 7) {
                    ForEach(list.indices, id: \.self) { i in
                        Capsule().fill(i == cur ? Color.white : Color.white.opacity(0.4)).frame(width: i == cur ? 20 : 7, height: 7)
                    }
                }.frame(maxWidth: .infinity).padding(.top, 14).animation(.easeOut, value: cur)
            }
            .padding(.bottom, 30)
            .onReceive(timer) { _ in withAnimation { cur = (cur + 1) % list.count } }
        }
    }
}

// MARK: - Kopf, Knöpfe

struct BrandMark: View {
    var size: CGFloat = 27
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 3 / 28)
                .fill(LinearGradient(colors: [FF.violet1, FF.violet2], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 24 / 28, height: size * 18 / 28)
            VStack(spacing: size * 8.5 / 28) {
                Color.black.opacity(0.3).frame(height: size * 1.5 / 28)
                Color.black.opacity(0.3).frame(height: size * 1.5 / 28)
            }.frame(width: size * 24 / 28)
            Image(systemName: "play.fill").font(.system(size: size * 0.32)).foregroundColor(.white).offset(x: size * 0.02)
        }.frame(width: size, height: size)
    }
}

struct Brand: View {
    var body: some View {
        HStack(spacing: 8) {
            BrandMark(size: 27 * FF.scale)
            Text("FilmFrei24").font(.inter(20, .heavy)).foregroundColor(.white).kerning(-0.3)
        }
    }
}

struct ChipButton: View {
    let label: String
    let on: Bool
    var dark = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.inter(15, .semibold)).foregroundColor(on ? FF.dark : Color(hex: 0xE8EBEE)).lineLimit(1)
                .padding(.horizontal, 14 * FF.scale).padding(.vertical, 9 * FF.scale)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.white : (dark ? FF.field : FF.btn)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(on || !dark ? 0 : 0.08)))
        }.buttonStyle(FocusStyle())
    }
}

struct BlueButton: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.inter(15, .semibold)).foregroundColor(.white).padding(.horizontal, 14 * FF.scale).padding(.vertical, 7 * FF.scale)
                .background(RoundedRectangle(cornerRadius: 6).fill(FF.blue))
        }.buttonStyle(FocusStyle())
    }
}

/// .cta – weißer Hauptknopf
struct Cta: View {
    let label: String
    var icon: String? = "play.fill"
    var dark = false
    var height: CGFloat = 52
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon { Image(systemName: icon).font(.system(size: 20 * FF.scale)) }
                Text(label).font(.inter(18, .semibold)).lineLimit(1)
            }
            .foregroundColor(dark ? .white : FF.dark)
            .frame(maxWidth: .infinity, minHeight: height * FF.scale)
            .padding(.horizontal, 20)
            .background(RoundedRectangle(cornerRadius: 8).fill(dark ? FF.btn : Color.white))
        }.buttonStyle(FocusStyle())
    }
}

struct GreyButton: View {
    let label: String
    var white = false
    var full = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.inter(15, .bold)).foregroundColor(white ? FF.dark : .white).lineLimit(1)
                .frame(maxWidth: full ? .infinity : nil, minHeight: 44 * FF.scale).padding(.horizontal, 18)
                .background(RoundedRectangle(cornerRadius: 8).fill(white ? Color.white : FF.btn))
        }.buttonStyle(FocusStyle())
    }
}

struct BackButton: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        #if os(tvOS)
        EmptyView()   // Fernbedienung: Menü-Taste
        #else
        Button { dismiss() } label: {
            Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                .frame(width: 44, height: 44).background(Circle().fill(FF.btn.opacity(0.85)))
        }.buttonStyle(PressStyle())
        #endif
    }
}

/// subHead(): Zurück + großer Titel
struct SubHead: View {
    let title: String
    var back = true
    var body: some View {
        HStack(spacing: 14) {
            if back { BackButton() }
            Text(title).font(.inter(24, .bold)).foregroundColor(.white).lineLimit(1)
            Spacer()
        }.padding(.horizontal, FF.pad).padding(.top, 10).padding(.bottom, 8)
    }
}

struct Avatar: View {
    let user: User?
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: 0x425265))
            if let u = user {
                if !u.avatar.isEmpty { Img(url: u.avatar).clipShape(Circle()) }
                else { Text(String(u.name.prefix(1)).uppercased()).font(.system(size: size * 0.4, weight: .bold)).foregroundColor(.white) }
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.5)).foregroundColor(.white)
            }
        }.frame(width: size, height: size).clipShape(Circle())
    }
}

struct Pill: View {
    let text: String
    var bg: Color = FF.btn
    var fg: Color = Color(hex: 0xDFE3E7)
    var body: some View {
        Text(text.uppercased()).font(.inter(12, .bold)).foregroundColor(fg).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3).background(RoundedRectangle(cornerRadius: 5).fill(bg))
    }
}

struct EmptyState<A: View>: View {
    let title: String
    let text: String
    @ViewBuilder var action: A
    var body: some View {
        VStack(spacing: 8) {
            if !title.isEmpty { Text(title).font(.inter(22, .bold)).foregroundColor(.white).multilineTextAlignment(.center) }
            Text(text).font(.inter(17)).foregroundColor(FF.text2).multilineTextAlignment(.center)
            action.padding(.top, 12)
        }.frame(maxWidth: .infinity).padding(.horizontal, FF.pad).padding(.vertical, 70)
    }
}
extension EmptyState where A == EmptyView {
    init(title: String, text: String) { self.title = title; self.text = text; self.action = EmptyView() }
}

struct BoxCard<C: View>: View {
    var title: String? = nil
    @ViewBuilder var content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title { Text(title).font(.inter(20, .bold)).foregroundColor(.white).padding(.bottom, 12) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(RoundedRectangle(cornerRadius: 12).fill(FF.box))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06)))
        .padding(.bottom, 18)
    }
}

struct SetRow<T: View>: View {
    let title: String
    var sub: String? = nil
    var last = false
    @ViewBuilder var trailing: T
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.inter(16)).foregroundColor(.white)
                    if let sub { Text(sub).font(.inter(14)).foregroundColor(FF.text2) }
                }
                Spacer()
                trailing
            }.padding(.vertical, 14)
            if !last { FF.line.frame(height: 1) }
        }
    }
}

/// .tabs – weiß unterstrichene Reiter
struct Tabs: View {
    let labels: [String]
    @Binding var sel: Int
    var body: some View {
        HStack(spacing: 0) {
            ForEach(labels.indices, id: \.self) { i in
                Button { sel = i } label: {
                    VStack(spacing: 0) {
                        Text(labels[i]).font(.inter(18, .bold)).foregroundColor(i == sel ? .white : FF.text2).lineLimit(1)
                            .padding(.top, 14).padding(.bottom, 12).padding(.horizontal, 4)
                        (i == sel ? Color.white : Color.clear).frame(height: 3)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(FocusStyle())
            }
        }.overlay(alignment: .bottom) { Color(hex: 0x3A4048).frame(height: 1) }
    }
}

/// .inp – Eingabefeld
struct Field: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var multiline = false
    var body: some View {
        Group {
            if secure { SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(FF.text2)) }
            else if multiline {
                #if os(tvOS)
                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(FF.text2))
                #else
                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(FF.text2), axis: .vertical).lineLimit(3...8)
                #endif
            }
            else { TextField("", text: $text, prompt: Text(placeholder).foregroundColor(FF.text2)) }
        }
        .font(.inter(16)).foregroundColor(.white)
        #if !os(tvOS)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(FF.field))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12)))
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        #endif
    }
}

struct Label2: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).font(.inter(14, .semibold)).foregroundColor(FF.text2).padding(.top, 12).padding(.bottom, 6) }
}

struct Loading: View {
    var body: some View { ProgressView().tint(.white).scaleEffect(1.4).frame(maxWidth: .infinity).padding(80) }
}

// MARK: - Bildschirmbreite als Umgebung

private struct ScreenWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 393 }
extension EnvironmentValues {
    var screenWidth: CGFloat { get { self[ScreenWidthKey.self] } set { self[ScreenWidthKey.self] = newValue } }
}

struct Toast: ViewModifier {
    @Binding var text: String?
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let t = text {
                Text(t).font(.inter(15, .semibold)).foregroundColor(.white).multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 12).background(RoundedRectangle(cornerRadius: 8).fill(FF.btn))
                    .shadow(color: .black.opacity(0.6), radius: 15, y: 8).padding(.bottom, 100).padding(.horizontal, 20)
                    .transition(.opacity)
                    .task(id: t) { try? await Task.sleep(nanoseconds: 2_800_000_000); withAnimation { text = nil } }
            }
        }
    }
}
extension View { func toast(_ t: Binding<String?>) -> some View { modifier(Toast(text: t)) } }
