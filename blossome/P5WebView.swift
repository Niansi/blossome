//
//  P5WebView.swift
//  blossome
//

import SwiftUI
import WebKit

struct P5WebView: UIViewRepresentable {
    let text: String
    let fontName: String
    let htmlFileName: String
    @ObservedObject var webViewManager: WebViewManager

    // Callbacks to parent
    var onActionRequested: () -> Void
    var onTextRendered: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs
        config.allowsInlineMediaPlayback = true

        // Add message handlers
        config.userContentController.add(context.coordinator, name: "action")
        config.userContentController.add(context.coordinator, name: "p5Ready")
        config.userContentController.add(context.coordinator, name: "textRendered")

        let webView = WKWebView(frame: .zero, configuration: config)

        // Bind manager
        webViewManager.webView = webView

        // Set navigation delegate BEFORE loading
        webView.navigationDelegate = context.coordinator

        // Load local file
        if let fileURL = Bundle.main.url(forResource: htmlFileName, withExtension: "html") {
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        } else {
            print("\(htmlFileName).html not found in bundle!")
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Always sync the latest parent reference so Coordinator has fresh data
        context.coordinator.parent = self

        // When the WebView first appears, `p5Ready` can arrive before SwiftUI has
        // finished committing the latest TextEditor changes (especially with IME
        // composing text). If we sync immediately, JS may receive the default
        // placeholder snapshot. Force an additional sync on the next runloop.
        context.coordinator.scheduleDeferredSync()

        // Sync text to JavaScript if p5 is ready and text has changed
        if context.coordinator.isP5Ready {
            context.coordinator.syncTextIfNeeded()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: P5WebView
        var isP5Ready = false
        private var lastSyncedText: String?
        private var deferredSyncWorkItem: DispatchWorkItem?

        init(_ parent: P5WebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "p5Ready" {
                isP5Ready = true
                // Don't push text here. We must wait until the WebView finished
                // navigation; otherwise `startArt` may run before the JS globals
                // are actually ready (and we also risk using stale SwiftUI text).
                scheduleDeferredSync()
            } else if message.name == "action" {
                if let msg = message.body as? String, msg == "showActionSheet" {
                    parent.onActionRequested()
                }
            } else if message.name == "textRendered" {
                parent.onTextRendered()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Navigation finished is the closest “JS is actually loaded” signal we have
            // on Swift side. Combine it with p5Ready and then sync.
            scheduleDeferredSync()
        }

        func syncTextIfNeeded() {
            let currentText = parent.text
            if currentText != lastSyncedText {
                syncTextToJavaScript()
            }
        }

        func syncTextToJavaScript() {
            let currentText = parent.text
            lastSyncedText = currentText

            #if DEBUG
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = trimmed.prefix(60)
            print("[P5WebView] syncTextToJavaScript: len=\(currentText.count) preview=\(preview)")
            #endif

            let safeText = currentText
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")

            let jsString = "startArt(\"\(safeText)\", \"\(parent.fontName)\");"
            parent.webViewManager.webView?.evaluateJavaScript(jsString, completionHandler: nil)
        }

        func scheduleDeferredSync() {
            deferredSyncWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.isP5Ready else { return }
                self.syncTextIfNeeded()
            }
            deferredSyncWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }
    }
}
