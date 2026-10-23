import Foundation

/// 2026-10-23 User: „vieles ohne neue Version ändern können“. Einstellungen vom Server
/// (https://filmfrei24.com/app-config.json), zwischengespeichert, beim nächsten Start sofort aktiv.
/// Fehlt ein Wert oder ist der Server weg, gelten die eingebauten Werte.
enum RemoteCfg {
    private static let key = "ff24.remoteCfg"
    private static var o: [String: Any] = (UserDefaults.standard.data(forKey: key).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]

    static func refresh() {
        guard let u = URL(string: "https://filmfrei24.com/app-config.json?t=\(Int(Date().timeIntervalSince1970 / 600))") else { return }
        URLSession.shared.dataTask(with: u) { d, r, _ in
            guard let d, (r as? HTTPURLResponse)?.statusCode == 200, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
            DispatchQueue.main.async { o = j; UserDefaults.standard.set(d, forKey: key) }
        }.resume()
    }

    private static func val(_ path: String) -> Any? {
        var cur: Any? = o
        for p in path.split(separator: ".") { cur = (cur as? [String: Any])?[String(p)] }
        return cur
    }
    static func num(_ path: String, _ def: Double) -> Double { (val(path) as? NSNumber)?.doubleValue ?? def }
    static func bool(_ path: String, _ def: Bool) -> Bool { (val(path) as? Bool) ?? def }
}
