import SwiftUI
import UIKit
import WebKit
import Network
import GameKit

enum LegalDoc: String, Hashable, CaseIterable {
    case Terms, Privacy

    var title: String {
        switch self {
        case .Terms: "Terms & Conditions"
        case .Privacy: "Privacy Policy"
        }
    }

    var subtitle: String {
        switch self {
        case .Terms: "House rules for the table"
        case .Privacy: "What stays on your device"
        }
    }

    var liveUrl: String {
        switch self {
        case .Terms: "https://game-boardgames.web.app/terms_of_condition.html"
        case .Privacy: "https://game-boardgames.web.app/privacy_policy.html"
        }
    }

    /// Bundled offline copy (Android `assets/legal/…`).
    var asset: String {
        switch self {
        case .Terms: "legal/terms.html"
        case .Privacy: "legal/privacy.html"
        }
    }

    var assetURL: URL? {
        let name = self == .Terms ? "terms" : "privacy"
        return Bundle.main.url(forResource: name, withExtension: "html")
            ?? Bundle.main.url(forResource: name, withExtension: "html", subdirectory: "Legal")
            ?? Bundle.main.url(forResource: name, withExtension: "html", subdirectory: "Resources/Legal")
    }
}

/// Whether the device currently has a network path (Android `isNetworkConnected`). Started at launch.
final class LegalConnectivity: @unchecked Sendable {
    static let shared = LegalConnectivity()
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var status: NWPath.Status?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock(); self.status = path.status; self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "legal.connectivity"))
    }

    /// Unknown counts as connected: a failed live load falls back to the offline copy anyway.
    var isConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        return status.map { $0 == .satisfied } ?? true
    }
}

/// Displays legal documents by first attempting to load the live web URL.
/// If offline, unreachable, or on error/timeout, falls back seamlessly to the bundled offline HTML asset.
struct LegalScreen: View {
    let doc: LegalDoc
    let onBack: () -> Void
    @State private var currentDoc: LegalDoc
    @State private var loaded = false

    init(doc: LegalDoc, onBack: @escaping () -> Void) {
        self.doc = doc
        self.onBack = onBack
        _currentDoc = State(initialValue: doc)
    }

    init(_ doc: LegalDoc, _ onBack: @escaping () -> Void) {
        self.init(doc: doc, onBack: onBack)
    }

    var body: some View {
        RoyalBackground(sparkles: false) {
            VStack(spacing: 0) {
                RoyalTopBar(currentDoc.title, onBack, subtitle: currentDoc.subtitle)
                ZStack {
                    LegalWebPage(startDoc: doc, currentDoc: $currentDoc, loaded: $loaded)
                        .opacity(loaded ? 1 : 0)
                        .animation(.tween(300), value: loaded)
                    if !loaded {
                        ZStack {
                            Royal.Night
                            VStack(spacing: 0) {
                                LoadingSpinner()
                                    .frame(width: 46, height: 46)
                                Spacer().frame(height: 18)
                                Text("Loading \(currentDoc.title)...", style: bodyStyle(14, .Bold, Royal.Smoke))
                            }
                        }
                    }
                }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .circular))
                .padding(.horizontal, 12)
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

/// Material indeterminate spinner look: a gold arc sweeping around a faint track.
private struct LoadingSpinner: View {
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(start)
            let cycle = (t / 1.333).truncatingRemainder(dividingBy: 1)
            let grow = cycle < 0.5 ? Easing.FastOutSlowIn.transform(cycle * 2) : 1 - Easing.FastOutSlowIn.transform((cycle - 0.5) * 2)
            let sweep = 0.05 + 0.7 * grow
            ZStack {
                Circle().stroke(Royal.Gold.copy(alpha: 0.2), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: sweep)
                    .stroke(Royal.Gold, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(t * 300 + (cycle < 0.5 ? 0 : (cycle - 0.5) * 2 * 252)))
            }
            .padding(1.75)
        }
    }
}

/// WKWebView with the Android WebViewClient behaviour: live page first (6 s timeout), bundled copy on any
/// failure, terms/privacy links kept inside, everything else (mailto, tel, other sites) opened outside.
private struct LegalWebPage: UIViewRepresentable {
    let startDoc: LegalDoc
    @Binding var currentDoc: LegalDoc
    @Binding var loaded: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = UIColor(Royal.Night)
        v.scrollView.backgroundColor = UIColor(Royal.Night)
        v.navigationDelegate = context.coordinator
        context.coordinator.webView = v
        context.coordinator.begin(startDoc)
        return v
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.timeout?.cancel()
        uiView.stopLoading()
        uiView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LegalWebPage
        weak var webView: WKWebView?
        var timeout: DispatchWorkItem?
        private var hasFallenBack = false
        private var current: LegalDoc

        init(_ parent: LegalWebPage) {
            self.parent = parent
            self.current = parent.startDoc
        }

        func begin(_ doc: LegalDoc) {
            current = doc
            if LegalConnectivity.shared.isConnected, let url = URL(string: doc.liveUrl) {
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, !self.parent.loaded, !self.hasFallenBack else { return }
                        self.fallbackToAsset()
                    }
                }
                timeout = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
                webView?.load(URLRequest(url: url))
            } else {
                hasFallenBack = true
                loadAsset(doc)
            }
        }

        private func loadAsset(_ doc: LegalDoc) {
            guard let url = doc.assetURL else { return }
            webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        private func fallbackToAsset() {
            if hasFallenBack { return }
            hasFallenBack = true
            timeout?.cancel()
            let doc = current
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.loadAsset(doc) } }
        }

        private func setDoc(_ doc: LegalDoc) {
            current = doc
            if parent.currentDoc != doc { parent.currentDoc = doc }
            parent.loaded = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            timeout?.cancel()
            // While falling back, wait until the bundled page itself finishes loading.
            if hasFallenBack, let url = webView.url, !url.isFileURL { return }
            parent.loaded = true
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            timeout?.cancel()
            fallbackToAsset()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            timeout?.cancel()
            fallbackToAsset()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.isForMainFrame, let http = navigationResponse.response as? HTTPURLResponse, http.statusCode >= 400 {
                decisionHandler(.cancel)
                timeout?.cancel()
                fallbackToAsset()
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.allow); return }
            let scheme = url.scheme?.lowercased() ?? ""
            let userNavigation = action.navigationType == .linkActivated || action.navigationType == .formSubmitted
            // Our own loads (and sub-frames) go through untouched, like Android's loadUrl().
            if !userNavigation && (scheme == "https" || scheme == "http" || scheme == "file" || scheme == "about") {
                decisionHandler(.allow)
                return
            }
            let s = url.absoluteString.lowercased()
            let isTerms = s.contains("terms")
            let isPrivacy = s.contains("privacy")
            if isTerms && current != .Terms { setDoc(.Terms) } else if isPrivacy && current != .Privacy { setDoc(.Privacy) }

            // Local asset navigation
            if url.isFileURL {
                if isTerms { decisionHandler(.cancel); loadAsset(.Terms); return }
                if isPrivacy { decisionHandler(.cancel); loadAsset(.Privacy); return }
                decisionHandler(.allow)
                return
            }
            // Live site navigation
            if url.host == "game-boardgames.web.app" {
                if isTerms, let live = URL(string: LegalDoc.Terms.liveUrl) { decisionHandler(.cancel); webView.load(URLRequest(url: live)); return }
                if isPrivacy, let live = URL(string: LegalDoc.Privacy.liveUrl) { decisionHandler(.cancel); webView.load(URLRequest(url: live)); return }
                decisionHandler(.allow)
                return
            }
            // External links and mailto
            decisionHandler(.cancel)
            UIApplication.shared.open(url)
        }
    }
}
