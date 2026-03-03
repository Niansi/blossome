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
    var onVideoGenerated: (String) -> Void
    
    func makeUIView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs
        config.allowsInlineMediaPlayback = true

        // Add message handlers
        config.userContentController.add(context.coordinator, name: "action")
        config.userContentController.add(context.coordinator, name: "videoCallback")
        config.userContentController.add(context.coordinator, name: "p5Ready")
        
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
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: P5WebView

        init(_ parent: P5WebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "p5Ready" {
                // P5.js setup() has completed — now safe to call startArt
                let safeText = parent.text
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")

                let jsString = "startArt(\"\(safeText)\", \"\(parent.fontName)\");"
                parent.webViewManager.webView?.evaluateJavaScript(jsString, completionHandler: nil)
            } else if message.name == "action" {
                if let msg = message.body as? String, msg == "showActionSheet" {
                    parent.onActionRequested()
                }
            } else if message.name == "videoCallback" {
                if let base64Data = message.body as? String {
                    parent.onVideoGenerated(base64Data)
                }
            }
        }
    }
}
