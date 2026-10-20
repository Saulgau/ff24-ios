import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

let BASE = "https://filmfrei24.com"

// MARK: - Tolerantes JSON (Typen schwanken wie auf der Website: Zahl/String, "" statt null)

typealias J = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func s(_ k: String) -> String {
        switch self[k] {
        case let v as String: return v
        case let v as NSNumber: return v.stringValue
        default: return ""
        }
    }
    func i(_ k: String) -> Int? {
        switch self[k] {
        case let v as NSNumber: return v.intValue
        case let v as String: return Int(v)
        default: return nil
        }
    }
    func d(_ k: String) -> Double? {
        switch self[k] {
        case let v as NSNumber: return v.doubleValue
        case let v as String: return Double(v)
        default: return nil
        }
    }
    func b(_ k: String) -> Bool {
        switch self[k] {
        case let v as NSNumber: return v.boolValue
        case let v as String: return v == "1" || v == "true"
        default: return false
        }
    }
    func o(_ k: String) -> J? { self[k] as? J }
    func a(_ k: String) -> [J] { (self[k] as? [Any])?.compactMap { $0 as? J } ?? [] }
    func strs(_ k: String) -> [String] { (self[k] as? [Any])?.compactMap { $0 as? String }.filter { !$0.isEmpty } ?? [] }
}

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Cookies dauerhaft (PHP-Session + ff24_remember), App = langer Browser-Besuch

enum CookieKeeper {
    private static let key = "ff24_cookies"

    static func restore() {
        guard let list = UserDefaults.standard.array(forKey: key) as? [[String: Any]] else { return }
        for raw in list {
            var props: [HTTPCookiePropertyKey: Any] = [:]
            for (k, v) in raw { props[HTTPCookiePropertyKey(k)] = v }
            if let c = HTTPCookie(properties: props), (c.expiresDate ?? .distantFuture) > Date() {
                HTTPCookieStorage.shared.setCookie(c)
            }
        }
    }

    static func save() {
        let cs = HTTPCookieStorage.shared.cookies?.filter { $0.domain.contains("filmfrei24.com") } ?? []
        let list: [[String: Any]] = cs.map { c in
            var p: [String: Any] = [:]
            for (k, v) in c.properties ?? [:] { p[k.rawValue] = v }
            // Session-Cookies (ohne Ablauf) trotzdem 30 Tage behalten
            if c.expiresDate == nil { p[HTTPCookiePropertyKey.expires.rawValue] = Date().addingTimeInterval(30 * 86400) }
            p.removeValue(forKey: HTTPCookiePropertyKey.discard.rawValue)
            return p
        }
        UserDefaults.standard.set(list, forKey: key)
    }

    static func clear() {
        HTTPCookieStorage.shared.cookies?.filter { $0.domain.contains("filmfrei24.com") }.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - HTTP

enum API {
    static let config: URLSessionConfiguration = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared
        c.httpShouldSetCookies = true
        c.httpCookieAcceptPolicy = .always
        c.timeoutIntervalForRequest = 30
        #if os(tvOS)
        let ua = "FilmFrei24-AppleTV/2.1"
        #else
        let ua = "FilmFrei24-iOS/2.1"
        #endif
        c.httpAdditionalHeaders = ["User-Agent": ua, "X-FF24-App": "1"]
        c.urlCache = URLCache(memoryCapacity: 50 << 20, diskCapacity: 300 << 20, diskPath: "ff24-api")
        return c
    }()
    static let http = URLSession(configuration: config)

    static func url(_ path: String) -> URL { URL(string: path.hasPrefix("http") ? path : BASE + path)! }

    private static func run(_ req: URLRequest) async throws -> Any? {
        let (data, resp) = try await http.data(for: req)
        CookieKeeper.save()
        let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            let msg = (parsed as? J)?.s("error")
            throw APIError(message: (msg?.isEmpty == false ? msg! : "Serverfehler (\(h.statusCode))"))
        }
        return parsed
    }

    static func get(_ path: String) async throws -> Any? {
        var r = URLRequest(url: url(path)); r.cachePolicy = .reloadIgnoringLocalCacheData
        return try await run(r)
    }
    static func getObj(_ path: String) async -> J { ((try? await get(path)) as? J) ?? [:] }

    static func post(_ path: String, _ body: J) async throws -> Any? {
        var r = URLRequest(url: url(path)); r.httpMethod = "POST"
        r.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await run(r)
    }
    /** Wie Website: Fehler als {ok:false,error} statt Ausnahme. */
    static func postObj(_ path: String, _ body: J) async -> J {
        do { return (try await post(path, body) as? J) ?? [:] } catch { return ["ok": false, "error": error.localizedDescription] }
    }

    static func postForm(_ path: String, _ fields: [String: String]) async throws -> Any? {
        var r = URLRequest(url: url(path)); r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var cs = CharacterSet.alphanumerics; cs.insert(charactersIn: "-._~")
        r.httpBody = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: cs) ?? "")" }.joined(separator: "&").data(using: .utf8)
        return try await run(r)
    }

    static func upload(_ path: String, field: String, filename: String, mime: String, data: Data) async throws -> J {
        let boundary = "ff24-" + UUID().uuidString
        var r = URLRequest(url: url(path)); r.httpMethod = "POST"
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        r.httpBody = body
        return (try await run(r) as? J) ?? [:]
    }

    static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }
}

// MARK: - Bilder wie Website (image.php)

func b64u(_ s: String) -> String {
    Data(s.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

/** "~w1280/datei.jpg|780" → image.php-URL */
func unpackImg(_ v: String) -> String {
    guard v.hasPrefix("~"), let i = v.lastIndex(of: "|") else { return v }
    let path = String(v[v.index(after: v.startIndex)..<i]), w = String(v[v.index(after: i)...])
    return "\(BASE)/api/image.php?u=" + b64u("https://image.tmdb.org/t/p/" + path) + "&w=" + w
}

func imgProxy(_ url: String, _ w: Int) -> String { url.isEmpty ? "" : "\(BASE)/api/image.php?u=" + b64u(url) + "&w=\(w)" }
