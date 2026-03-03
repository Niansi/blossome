//
//  ContentView.swift
//  blossome
//
//  Created by 武翔宇 on 2026/3/2.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @State private var notepadText: String = "输入一些文字...\n来看看音符如何诞生。"
    @State private var selectedFont: String = "System"
    @State private var isShowingArtPreview: Bool = false
    
    @StateObject private var webViewManager = WebViewManager()
    @State private var showingActionSheet = false
    @State private var isRecording = false
    @State private var isLivePhotoRecording = false
    @State private var showingFontPicker = false
    
    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $notepadText)
                    .font(fontFromName(selectedFont))
                    .padding()
            }
            .navigationTitle("记事本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingFontPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "textformat")
                            Text(selectedFont == "System" ? "系统" : selectedFont)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isShowingArtPreview = true
                        } label: {
                            Label("音乐的诞生", systemImage: "sparkles")
                        }
                    } label: {
                        Text("Art").bold()
                    }
                }
            }
            .sheet(isPresented: $showingFontPicker) {
                BundledFontPicker(selectedFont: $selectedFont)
            }
            .fullScreenCover(isPresented: $isShowingArtPreview) {
                ZStack {
                    P5WebView(
                        text: notepadText,
                        fontName: selectedFont,
                        webViewManager: webViewManager,
                        onActionRequested: {
                            showingActionSheet = true
                        },
                        onVideoGenerated: { base64 in
                            isRecording = false
                            if isLivePhotoRecording {
                                MediaSaver.shared.saveLivePhoto(base64String: base64) { success, error in
                                    print("LivePhoto saved: \(success), error: \(error?.localizedDescription ?? "none")")
                                }
                                isLivePhotoRecording = false
                            } else {
                                MediaSaver.shared.saveVideo(base64String: base64) { success, error in
                                    print("Video saved: \(success)")
                                }
                            }
                        }
                    )
                    .ignoresSafeArea()
                    
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: { isShowingArtPreview = false }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(Color.gray.opacity(0.8))
                            }
                            .padding()
                        }
                        
                        Spacer()
                        
                        // 显式添加底部导出按钮组，确保用户可以看见
                        if !isRecording {
                            HStack(spacing: 20) {
                                Button(action: {
                                    startRecordingProcess()
                                }) {
                                    Text("保存为视频")
                                        .font(.headline)
                                        .padding()
                                        .background(Color.blue.opacity(0.8))
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                                
                                Button(action: {
                                    startRecordingProcess(forLivePhoto: true)
                                }) {
                                    Text("保存为 LivePhoto")
                                        .font(.headline)
                                        .padding()
                                        .background(Color.purple.opacity(0.8))
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                            }
                            .padding(.bottom, 40)
                        }
                    }
                    
                    if isRecording {
                        VStack {
                            ProgressView("正在倾听并录制音符...")
                                .padding(20)
                                .background(Color(UIColor.systemBackground).opacity(0.9))
                                .cornerRadius(12)
                        }
                    }
                }
            }
        }
    }
    
    func startRecordingProcess(forLivePhoto: Bool = false) {
        isRecording = true
        isLivePhotoRecording = forLivePhoto
        webViewManager.startRecording()
        
        // LivePhoto 录制 3 秒，普通视频录制 5 秒
        let duration: Double = forLivePhoto ? 3.0 : 5.0
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            webViewManager.stopRecording()
        }
    }
    
    func fontFromName(_ name: String) -> Font {
        if name == "System" {
            return .body
        } else {
            return .custom(name, size: 17)
        }
    }
}

// MARK: - 内建字体选择器（内建字体 + 系统字体入口）

/// App 内置的字体列表
let bundledFonts: [(displayName: String, postScriptName: String)] = [
    ("McDonald's Fries Font", "McDonald'sFriesFont-Regular"),
]

struct BundledFontPicker: View {
    @Binding var selectedFont: String
    @Environment(\.dismiss) var dismiss
    @State private var showSystemPicker = false

    var body: some View {
        NavigationStack {
            List {
                // ── 内建字体 ───────────────────────────────────
                Section("内建字体") {
                    ForEach(bundledFonts, id: \.postScriptName) { font in
                        Button {
                            selectedFont = font.postScriptName
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(font.displayName)
                                        .font(.custom(font.postScriptName, size: 18))
                                    Text(font.postScriptName)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedFont == font.postScriptName {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }

                // ── 系统字体 ───────────────────────────────────
                Section("系统字体") {
                    Button {
                        showSystemPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "textformat")
                            Text("浏览系统字体…")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("选择字体")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("重置") {
                        selectedFont = "System"
                        dismiss()
                    }
                    .foregroundColor(.red.opacity(0.8))
                }
            }
            .sheet(isPresented: $showSystemPicker) {
                SystemFontPicker(selectedFont: $selectedFont)
                    .onDisappear { if selectedFont != "System" { dismiss() } }
            }
        }
    }
}

// MARK: - UIFontPickerViewController 包装（系统字体）

struct SystemFontPicker: UIViewControllerRepresentable {
    @Binding var selectedFont: String
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIFontPickerViewController {
        let config = UIFontPickerViewController.Configuration()
        config.includeFaces = false
        let picker = UIFontPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIFontPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIFontPickerViewControllerDelegate {
        var parent: SystemFontPicker
        init(_ parent: SystemFontPicker) { self.parent = parent }

        func fontPickerViewControllerDidPickFont(_ viewController: UIFontPickerViewController) {
            if let descriptor = viewController.selectedFontDescriptor {
                let name = descriptor.fontAttributes[.family] as? String ?? descriptor.postscriptName
                parent.selectedFont = name
            }
            parent.dismiss()
        }

        func fontPickerViewControllerDidCancel(_ viewController: UIFontPickerViewController) {
            parent.dismiss()
        }
    }
}

#Preview {
    ContentView()
}
