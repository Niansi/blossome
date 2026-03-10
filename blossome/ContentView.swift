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
    case dandelion

    var id: String { rawValue }

    var htmlFileName: String { rawValue }

    var fontName: String {
        switch self {
        case .sketch: return "LXGWWenKai-Light"
        case .mcdonald: return "McDonaldsFriesFont"
        case .rainynight: return "LXGWWenKai-Light"
        case .dandelion: return "System"
        }
    }

    var displayName: String {
        switch self {
        case .sketch: return "音乐的诞生"
        case .mcdonald: return "麦门"
        case .rainynight: return "潮湿的雨夜"
        case .dandelion: return "蒲公英的约定"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var fragmentStore: FragmentStore
    @EnvironmentObject var portfolioStore: PortfolioStore

    let fragmentID: UUID

    @State private var notepadText: String = ""
    // 用于预览的"冻结快照"。只在用户点 Art 的那一刻捕获一次，确保 WebView 一定拿到同一份文本。
    @State private var previewText: String = ""
    @State private var activeArtEffect: ArtEffect? = nil
    @FocusState private var isNotepadFocused: Bool

    @State private var forcePreviewNonce: Int = 0

    @StateObject private var webViewManager = WebViewManager()
    @State private var showingActionSheet = false
    @State private var isRecording = false
    @State private var isLivePhotoRecording = false
    @State private var isArtLoading = true

    @State private var showingPortfolio = false
    @State private var fluidProgressState: FluidProgressState = .idle
    @State private var savedPortfolioItem: PortfolioItem? = nil
    @State private var navigateToPortfolioFromOverlay = false

    @State private var showEmptyTextToast = false
    @State private var emptyTextToastMessage = ""

    // 防抖保存用的 timer
    @State private var saveTimer: Timer? = nil
    
    // 用于记录 Art 按钮在全球坐标系中的位置，从而将外环文字贴在上面
    @State private var artButtonFrame: CGRect = .zero
    
    var body: some View {
        TextEditor(text: $notepadText)
            .font(.body)
            .padding(.horizontal)
            .focused($isNotepadFocused)
            .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        openArtEffect(.sketch)
                    } label: {
                        Label("音乐的诞生", systemImage: "sparkles")
                    }
                    Button {
                        openArtEffect(.mcdonald)
                    } label: {
                        Label("麦门", systemImage: "flame")
                    }
                    Button {
                        openArtEffect(.rainynight)
                    } label: {
                        Label("潮湿的雨夜", systemImage: "cloud.rain")
                    }
                    Button {
                        openArtEffect(.dandelion)
                    } label: {
                        Label("蒲公英的约定", systemImage: "wind")
                    }
                } label: {
                    Image("ArtIcon")
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.primary)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        artButtonFrame = geo.frame(in: .global)
                                    }
                                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                        artButtonFrame = newFrame
                                    }
                            }
                        )
                }
            }
        }
        .onAppear {
            if let fragment = fragmentStore.fragment(by: fragmentID) {
                notepadText = fragment.content
            }
        }
        .onDisappear {
            // 离开页面时：空内容则删除碎片，否则保存
            saveTimer?.invalidate()
            let trimmed = notepadText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                fragmentStore.delete(id: fragmentID)
            } else {
                // 仅当内容有变化时才保存（避免更新时间被无谓刷新）
                if let existing = fragmentStore.fragment(by: fragmentID), existing.content != notepadText {
                    fragmentStore.update(id: fragmentID, content: notepadText)
                }
            }
        }
        .onChange(of: notepadText) { _, newValue in
            // 防抖保存：停止输入 1 秒后自动保存
            saveTimer?.invalidate()
            saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                fragmentStore.update(id: fragmentID, content: newValue)
            }
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
                    text: previewText,
                    fontName: effect.fontName,
                    htmlFileName: effect.htmlFileName,
                    webViewManager: webViewManager,
                    onActionRequested: {
                        showingActionSheet = true
                    },
                    onTextRendered: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isArtLoading = false
                        }
                    }
                )
                .id("artPreview_\(forcePreviewNonce)")
                .ignoresSafeArea()
                
                VStack {
                    HStack {
                        Button(action: { activeArtEffect = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.glass)
                        .clipShape(Circle())
                        
                        Spacer()
                    }
                    .padding(.leading, 16)
                    .padding(.top, 6)
                    
                    Spacer()
                    
                    // 显式添加底部导出按钮组，使用 GlassEffectContainer 产生融合形变
                    if !isRecording && fluidProgressState == .idle {
                        GlassEffectContainer {
                            HStack(spacing: 8) {
                                Menu {
                                    Button("5 秒") { startRecordingProcess(duration: 5) }
                                    Button("15 秒") { startRecordingProcess(duration: 15) }
                                    Button("30 秒") { startRecordingProcess(duration: 30) }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "video.fill")
                                        Text("保存为视频")
                                    }
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .menuStyle(.button)
                                .buttonStyle(.glass)

                                Button(action: {
                                    startRecordingProcess(forLivePhoto: true)
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "livephoto")
                                        Text("LivePhoto")
                                    }
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(.glass)
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
                
                if fluidProgressState != .idle {
                    FluidProgressHUD(state: $fluidProgressState, onViewPortfolio: {
                        fluidProgressState = .idle
                        navigateToPortfolioFromOverlay = true
                        activeArtEffect = nil
                    })
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(2)
                }

                // Loading 遮罩：等待文本渲染完成
                if isArtLoading {
                    ZStack {
                        Color(UIColor.systemBackground)
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("准备中...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
        }
        .navigationDestination(isPresented: $showingPortfolio) {
            PortfolioView()
                .environmentObject(portfolioStore)
        }
        .overlay {
            GeometryReader { globalGeo in
                if artButtonFrame != .zero {
                    CircularTextEffect(
                        text: "blossome blossome ",
                        radius: 35,
                        font: .custom("SourceCodePro-Light", size: 8),
                        textColor: .primary,
                        textOpacity: 0.6
                    )
                    .position(
                        x: artButtonFrame.midX - globalGeo.frame(in: .global).minX,
                        y: artButtonFrame.midY - globalGeo.frame(in: .global).minY
                    )
                    .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            if showEmptyTextToast {
                Text(emptyTextToastMessage)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25)) {
                            showEmptyTextToast = false
                        }
                    }
            }
        }
    }

    private func showToast(message: String) {
        emptyTextToastMessage = message
        withAnimation(.spring(response: 0.25)) {
            showEmptyTextToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.spring(response: 0.25)) {
                showEmptyTextToast = false
            }
        }
    }
    
    func openArtEffect(_ effect: ArtEffect) {
        // 强制重建一次 WebView，避免复用旧的 WKWebView/Coordinator 造成首次注入拿到旧文本。
        forcePreviewNonce &+= 1

        // 重置 loading 状态
        isArtLoading = true

        // 1) 强制提交 IME（拼音/手写）组合中的内容
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isNotepadFocused = false

        // 2) 同步捕获当前文本快照，保证 WebView 创建时即拿到正确内容
        previewText = notepadText

        // 3) 下一帧再刷新一次（确保 IME 组合文本已提交），然后做空文本保护并打开 cover
        DispatchQueue.main.async {
            self.previewText = self.notepadText
            let trimmed = self.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                self.showToast(message: "请输入文字后再预览")
                return
            }
            self.activeArtEffect = effect

            // 超时保护：3 秒后强制隐藏 loading，避免永久 loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if self.isArtLoading {
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.isArtLoading = false
                    }
                }
            }
        }
    }

    func startRecordingProcess(forLivePhoto: Bool = false, duration: Double = 5) {
        isRecording = true
        isLivePhotoRecording = forLivePhoto
        
        let recordDuration: Double = forLivePhoto ? 3.0 : duration
        let mediaType: MediaType = forLivePhoto ? .livePhoto : .video
        fluidProgressState = .processing(type: mediaType, estimatedDuration: recordDuration)

        guard let webView = webViewManager.webView, let effect = activeArtEffect else {
            isRecording = false
            fluidProgressState = .error("无法获取画布")
            return
        }
        
        // Trigger any JS preparation hooks (e.g. rainynight scene reset)
        webViewManager.startRecording()

        MediaSaver.shared.startRecording(webView: webView, duration: recordDuration, forLivePhoto: forLivePhoto, effectName: effect.displayName) { videoURL, imageURL, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.fluidProgressState = .error(error.localizedDescription)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { self.isRecording = false }
                    return
                }
                
                guard let videoURL = videoURL else {
                    self.fluidProgressState = .error("视频获取失败")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { self.isRecording = false }
                    return
                }

                if forLivePhoto {
                    guard let imageURL = imageURL else {
                        self.fluidProgressState = .error("封面获取失败")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { self.isRecording = false }
                        return
                    }
                    
                    PortfolioStore.shared.saveLivePhotoToPortfolio(videoURL: videoURL, imageURL: imageURL, effectName: effect.displayName) { item in
                        if let item = item {
                            self.savedPortfolioItem = item
                            self.fluidProgressState = .success
                        } else {
                            self.fluidProgressState = .error("保存到作品集失败")
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { self.isRecording = false; self.isLivePhotoRecording = false }
                    }
                } else {
                    let portfolioType: PortfolioItemType = forLivePhoto ? .livePhoto : .video
                    PortfolioStore.shared.saveToPortfolio(videoURL: videoURL, effectName: effect.displayName, type: portfolioType) { item in
                        if let item = item {
                            self.savedPortfolioItem = item
                            self.fluidProgressState = .success
                        } else {
                            self.fluidProgressState = .error("保存到作品集失败")
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { self.isRecording = false }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ContentView(fragmentID: UUID())
            .environmentObject(FragmentStore.shared)
            .environmentObject(PortfolioStore.shared)
    }
}
