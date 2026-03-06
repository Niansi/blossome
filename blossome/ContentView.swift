//
//  ContentView.swift
//  blossome
//
//  Created by 武翔宇 on 2026/3/2.
//

import SwiftUI

enum ArtEffect: String, Identifiable {
    case sketch
    case mcdonald
    case rainynight

    var id: String { rawValue }

    var htmlFileName: String { rawValue }

    var fontName: String {
        switch self {
        case .sketch: return "LXGWWenKai-Light"
        case .mcdonald: return "McDonaldsFriesFont"
        case .rainynight: return "LXGWWenKai-Light"
        }
    }

    var displayName: String {
        switch self {
        case .sketch: return "音乐的诞生"
        case .mcdonald: return "麦门"
        case .rainynight: return "潮湿的雨夜"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var portfolioStore: PortfolioStore
    @State private var notepadText: String = "输入一些文字...\n来看看音符如何诞生。"
    @State private var activeArtEffect: ArtEffect? = nil

    @StateObject private var webViewManager = WebViewManager()
    @State private var showingActionSheet = false
    @State private var isRecording = false
    @State private var isLivePhotoRecording = false

    @State private var showingPortfolio = false
    @State private var showingSaveSuccess = false
    @State private var savedPortfolioItem: PortfolioItem? = nil
    @State private var navigateToPortfolioFromOverlay = false
    
    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $notepadText)
                    .font(.body)
                    .padding()
            }
            .navigationTitle("记事本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingPortfolio = true
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            activeArtEffect = .sketch
                        } label: {
                            Label("音乐的诞生", systemImage: "sparkles")
                        }
                        Button {
                            activeArtEffect = .mcdonald
                        } label: {
                            Label("麦门", systemImage: "flame")
                        }
                        Button {
                            activeArtEffect = .rainynight
                        } label: {
                            Label("潮湿的雨夜", systemImage: "cloud.rain")
                        }
                    } label: {
                        Text("Art").bold()
                    }
                }
            }
            .navigationDestination(isPresented: $showingPortfolio) {
                PortfolioView()
                    .environmentObject(portfolioStore)
            }
            .fullScreenCover(item: $activeArtEffect, onDismiss: {
                if navigateToPortfolioFromOverlay {
                    navigateToPortfolioFromOverlay = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingPortfolio = true
                    }
                }
            }) { effect in
                ZStack {
                    P5WebView(
                        text: notepadText,
                        fontName: effect.fontName,
                        htmlFileName: effect.htmlFileName,
                        webViewManager: webViewManager,
                        onActionRequested: {
                            showingActionSheet = true
                        },
                        onVideoGenerated: { base64 in
                            isRecording = false
                            let effectName = effect.displayName
                            let itemType: PortfolioItemType = isLivePhotoRecording ? .livePhoto : .video

                            if isLivePhotoRecording {
                                MediaSaver.shared.saveLivePhoto(base64String: base64) { success, error in
                                    print("LivePhoto saved: \(success), error: \(error?.localizedDescription ?? "none")")
                                    if success {
                                        portfolioStore.saveLivePhotoToPortfolio(base64String: base64, effectName: effectName) { item in
                                            if let item = item {
                                                savedPortfolioItem = item
                                                showingSaveSuccess = true
                                            }
                                        }
                                    }
                                }
                                isLivePhotoRecording = false
                            } else {
                                MediaSaver.shared.saveVideo(base64String: base64) { success, error in
                                    print("Video saved: \(success)")
                                    if success {
                                        portfolioStore.saveToPortfolio(base64String: base64, effectName: effectName, type: itemType) { item in
                                            if let item = item {
                                                savedPortfolioItem = item
                                                showingSaveSuccess = true
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    )
                    .ignoresSafeArea()
                    
                    VStack {
                        HStack {
                            Button(action: { activeArtEffect = nil }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 36, height: 36)
                                    .glassEffect(.regular)
                            }
                            Spacer()
                        }
                        .padding()
                        
                        Spacer()
                        
                        // 显式添加底部导出按钮组，确保用户可以看见
                        if !isRecording {
                            HStack(spacing: 0) {
                                Menu {
                                    Button("5 秒") { startRecordingProcess(duration: 5) }
                                    Button("15 秒") { startRecordingProcess(duration: 15) }
                                    Button("30 秒") { startRecordingProcess(duration: 30) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "video.fill")
                                        Text("保存为视频")
                                    }
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 14)
                                }

                                Divider()
                                    .frame(height: 24)

                                Button(action: {
                                    startRecordingProcess(forLivePhoto: true)
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "livephoto")
                                        Text("LivePhoto")
                                    }
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 14)
                                }
                            }
                            .glassEffect(.regular)
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

                    if showingSaveSuccess, let item = savedPortfolioItem {
                        SaveSuccessOverlay(
                            item: item,
                            portfolioStore: portfolioStore,
                            onViewPortfolio: {
                                showingSaveSuccess = false
                                navigateToPortfolioFromOverlay = true
                                activeArtEffect = nil
                            },
                            onDismiss: {
                                showingSaveSuccess = false
                            }
                        )
                    }
                }
            }
        }
    }
    
    func startRecordingProcess(forLivePhoto: Bool = false, duration: Double = 5) {
        isRecording = true
        isLivePhotoRecording = forLivePhoto
        webViewManager.startRecording()

        let recordDuration: Double = forLivePhoto ? 3.0 : duration
        DispatchQueue.main.asyncAfter(deadline: .now() + recordDuration) {
            webViewManager.stopRecording()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PortfolioStore.shared)
}
