//
//  P5WebView.swift
//  blossome
//

import SwiftUI
import WebKit

struct P5WebView: UIViewRepresentable {
    let text: String
    let fontName: String
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
        
        let webView = WKWebView(frame: .zero, configuration: config)
        
        // Bind manager
        webViewManager.webView = webView
        
        // Set navigation delegate BEFORE loading
        webView.navigationDelegate = context.coordinator
        
        // Load local file
        if let fileURL = Bundle.main.url(forResource: "sketch", withExtension: "html") {
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        } else {
            print("sketch.html not found in bundle!")
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Always sync the latest parent reference so Coordinator has fresh data
        context.coordinator.parent = self
        
        // Only call JS if the page has finished loading
        guard context.coordinator.pageLoaded else { return }
        
        let safeText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        
        let jsString = "startArt(\"\(safeText)\", \"\(fontName)\");"
        uiView.evaluateJavaScript(jsString) { res, error in
            if let error = error {
                print("JS evaluation error on update: \(error.localizedDescription)")
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: P5WebView
        var pageLoaded = false
        
        init(_ parent: P5WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            
            // Use the latest parent reference (updated in updateUIView)
            let safeText = parent.text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            
            let jsString = "startArt(\"\(safeText)\", \"\(parent.fontName)\");"
            webView.evaluateJavaScript(jsString, completionHandler: nil)
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "action" {
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
