// FF24 Dateien – interne Verwaltungs-App (2026-11-20). Zeigt die Datei-Verwaltung von tv.filmfrei24.com/ff24-dateien
// im Vollbild. Der Zugangsschlüssel ist fest eingebaut (keine Anmeldung, Wunsch des Betreibers) – App nicht weitergeben.
import SwiftUI
import WebKit

let FF24_KEY = "fWUkhh09IDDPhuiNTDEQKANd8uSzuy_E897APP4f-EU"
let FF24_URL = URL(string: "https://tv.filmfrei24.com/ff24-dateien/?k=" + FF24_KEY)!

@main
struct FF24DateienApp: App {
    var body: some Scene {
        WindowGroup { WebView().ignoresSafeArea().background(Color(red: 0.04, green: 0.06, blue: 0.09)) }
    }
}

struct WebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0.04, green: 0.06, blue: 0.09, alpha: 1)
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        let rc = UIRefreshControl()
        rc.addTarget(context.coordinator, action: #selector(Coordinator.reload(_:)), for: .valueChanged)
        wv.scrollView.refreshControl = rc
        context.coordinator.web = wv
        var req = URLRequest(url: FF24_URL)
        req.setValue(FF24_KEY, forHTTPHeaderField: "X-FF24-Dateien")
        wv.load(req)
        return wv
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        weak var web: WKWebView?
        var ziel: URL?
        @objc func reload(_ rc: UIRefreshControl) { web?.reload(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { rc.endRefreshing() } }

        // Herunterladen: Dateien landen in der Dateien-App unter „Auf meinem iPhone › FF24 Dateien“, danach Teilen-Menü
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let r = navigationResponse.response as? HTTPURLResponse,
               (r.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased().contains("attachment") {
                decisionHandler(.download); return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            var url = docs.appendingPathComponent(suggestedFilename)
            var n = 1
            while FileManager.default.fileExists(atPath: url.path) {
                let base = (suggestedFilename as NSString).deletingPathExtension, ext = (suggestedFilename as NSString).pathExtension
                url = docs.appendingPathComponent("\(base) (\(n))" + (ext.isEmpty ? "" : ".\(ext)")); n += 1
            }
            ziel = url; completionHandler(url)
        }
        func downloadDidFinish(_ download: WKDownload) {
            guard let url = ziel, let wv = web else { return }
            let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = wv
            vc.popoverPresentationController?.sourceRect = CGRect(x: wv.bounds.midX, y: wv.bounds.midY, width: 1, height: 1)
            wv.window?.rootViewController?.present(vc, animated: true)
        }
        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) { alert("Herunterladen fehlgeschlagen: \(error.localizedDescription)") }

        // prompt()/confirm()/alert() der Seite (Umbenennen, Löschen bestätigen)
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            present(a) ?? completionHandler()
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Abbrechen", style: .cancel) { _ in completionHandler(false) })
            a.addAction(UIAlertAction(title: "Ja", style: .destructive) { _ in completionHandler(true) })
            present(a) ?? completionHandler(false)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            a.addTextField { $0.text = defaultText; $0.clearButtonMode = .whileEditing }
            a.addAction(UIAlertAction(title: "Abbrechen", style: .cancel) { _ in completionHandler(nil) })
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
            present(a) ?? completionHandler(nil)
        }
        private func present(_ vc: UIViewController) -> Void? {
            guard let root = web?.window?.rootViewController else { return nil }
            var top = root; while let p = top.presentedViewController { top = p }
            top.present(vc, animated: true); return ()
        }
        private func alert(_ text: String) { _ = present(UIAlertController(title: nil, message: text, preferredStyle: .alert).withOK()) }
    }
}

extension UIAlertController { func withOK() -> UIAlertController { addAction(UIAlertAction(title: "OK", style: .default)); return self } }
