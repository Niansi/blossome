//
//  PortfolioDetailView.swift
//  blossome
//
//  Created by 武翔宇 on 2026/3/3.
//

import SwiftUI
import AVKit
import PhotosUI
import Photos

// MARK: - Pure Video Rendering View (no system controls)

private class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct PureVideoView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - LivePhoto UIKit Wrapper

struct LivePhotoUIView: UIViewRepresentable {
    let imageURL: URL
    let videoURL: URL
    var isCurrentPage: Bool

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        if uiView.livePhoto == nil {
            loadLivePhoto(into: uiView)
        } else {
            if !isCurrentPage {
                uiView.stopPlayback()
            }
        }
    }

    private func loadLivePhoto(into view: PHLivePhotoView) {
        PHLivePhoto.request(
            withResourceFileURLs: [imageURL, videoURL],
            placeholderImage: UIImage(contentsOfFile: imageURL.path),
            targetSize: .zero,
            contentMode: .default
        ) { livePhoto, info in
            if let livePhoto = livePhoto {
                DispatchQueue.main.async {
                    view.livePhoto = livePhoto
                    if !self.isCurrentPage {
                        view.stopPlayback()
                    }
                }
            }
        }
    }
}

// MARK: - Single Item Page

private struct PortfolioPageView: View {
    let item: PortfolioItem
    let isCurrentPage: Bool
    @EnvironmentObject var portfolioStore: PortfolioStore
    @State private var player: AVPlayer?
    @State private var isPlaying = true
    @State private var loopObserver: NSObjectProtocol?

    var body: some View {
        Group {
            if item.type == .livePhoto {
                livePhotoContent
            } else {
                videoContent
            }
        }
        .onChange(of: isCurrentPage) { _, isCurrent in
            if isCurrent {
                activatePlayer()
            } else {
                deactivatePlayer()
            }
        }
        .onAppear {
            preparePlayer()
            if isCurrentPage {
                player?.play()
                isPlaying = true
            }
        }
        .onDisappear {
            destroyPlayer()
        }
        .onChange(of: item.id) { _, _ in
            // Defensive: ensure reused page views don't keep stale AVPlayer state.
            destroyPlayer()
            preparePlayer()
            if isCurrentPage {
                player?.play()
                isPlaying = true
            }
        }
    }

    private func preparePlayer() {
        guard item.type != .livePhoto else { return }
        guard player == nil else { return }
        let url = portfolioStore.fileURL(for: item)
        let p = AVPlayer(url: url)
        p.pause()
        player = p
        isPlaying = false
        loopObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in
            p.seek(to: .zero)
            p.play()
        }
    }

    private func activatePlayer() {
        guard item.type != .livePhoto else { return }
        if player != nil {
            player?.play()
            isPlaying = true
            return
        }
        preparePlayer()
        player?.play()
        isPlaying = true
    }

    private func deactivatePlayer() {
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
    }

    private func destroyPlayer() {
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
    }

    @ViewBuilder
    private var videoContent: some View {
        if let player = player {
            ZStack {
                PureVideoView(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .onTapGesture {
                        togglePlayback()
                    }

                if !isPlaying {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.5), radius: 8)
                        .onTapGesture {
                            togglePlayback()
                        }
                }
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var livePhotoContent: some View {
        if let imageURL = portfolioStore.livePhotoImageURL(for: item),
           let videoURL = portfolioStore.livePhotoVideoURL(for: item),
           let imageSize = UIImage(contentsOfFile: imageURL.path)?.size,
           FileManager.default.fileExists(atPath: videoURL.path) {
            LivePhotoUIView(imageURL: imageURL, videoURL: videoURL, isCurrentPage: isCurrentPage)
                .aspectRatio(imageSize, contentMode: .fit)
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
        } else {
            if let player = player {
                ZStack {
                    PureVideoView(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture { togglePlayback() }

                    if !isPlaying {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.5), radius: 8)
                            .onTapGesture { togglePlayback() }
                    }

                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "livephoto")
                                .foregroundColor(.white)
                            Text("这是一张 Live Photo（已保存到相册）")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                .ignoresSafeArea()
            } else {
                Color.clear
                    .onAppear {
                        if isCurrentPage {
                            activatePlayer()
                        }
                    }
            }
        }
    }

    private func togglePlayback() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
}

// MARK: - Detail View (Full Screen + Paging)

struct PortfolioDetailView: View {
    let initialIndex: Int
    @EnvironmentObject var portfolioStore: PortfolioStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentIndex: Int
    
    @State private var dragOffset: CGSize = .zero
    @State private var isDraggingDown = false
    
    // ... menu states
    @State private var showShareSheet = false
    @State private var showDeleteAlert = false
    @State private var saveToAlbumMessage: String?
    @State private var showSaveToast = false

    private var items: [PortfolioItem] {
        portfolioStore.items
    }

    init(initialIndex: Int) {
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }

    private var currentItem: PortfolioItem? {
        items[safe: currentIndex]
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()

            // Paging TabView
            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PortfolioPageView(item: item, isCurrentPage: index == currentIndex)
                        .environmentObject(portfolioStore)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Overlay: top bar + bottom info
            VStack {
                // Top bar
                ZStack {
                    // Page indicator
                    Text("\(currentIndex + 1) / \(items.count)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)

                        Spacer()

                        // ... More menu
                        Menu {
                            Button {
                                saveCurrentItemToAlbum()
                            } label: {
                                Label("保存到相册", systemImage: "square.and.arrow.down")
                            }
                            Button {
                                showShareSheet = true
                            } label: {
                                Label("分享", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button(role: .destructive) {
                                showDeleteAlert = true
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 32, height: 32)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 44)

                Spacer()

                // Bottom info
                if let currentItem = currentItem {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: currentItem.type == .livePhoto ? "livephoto" : "video.fill")
                            Text(currentItem.effectName)
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.primary)

                        Text(currentItem.createdAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .offset(y: dragOffset.height > 0 ? dragOffset.height : 0)
        .opacity(1.0 - Double(max(0, dragOffset.height) / max(1, UIApplication.screenBoundsHeight)))
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if !isDraggingDown {
                        let isVertical = abs(value.translation.height) > abs(value.translation.width) + 15
                        if isVertical && value.translation.height > 0 {
                            let startY = value.startLocation.y
                            let screenHeight = UIApplication.screenBoundsHeight
                            // 标题栏和底部信息区域不响应下滑手势
                            if startY > 120 && startY < screenHeight - 150 {
                                isDraggingDown = true
                            }
                        }
                    }
                    if isDraggingDown && value.translation.height > 0 {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    if isDraggingDown {
                        if dragOffset.height > 150 || value.velocity.height > 500 {
                            dismiss()
                        } else {
                            withAnimation(.spring()) {
                                dragOffset = .zero
                            }
                        }
                        isDraggingDown = false
                    }
                }
        )
        .statusBarHidden()
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteCurrentItem()
            }
        } message: {
            Text("删除后无法恢复，确定要删除这个作品吗？")
        }
        .sheet(isPresented: $showShareSheet) {
            if let item = currentItem {
                let fileURL = portfolioStore.fileURL(for: item)
                ActivityViewController(activityItems: [fileURL])
                    .presentationDetents([.medium, .large])
            }
        }
        .overlay(alignment: .top) {
            if showSaveToast, let msg = saveToAlbumMessage {
                Text(msg)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Actions
    
    private func saveCurrentItemToAlbum() {
        guard let item = currentItem else { return }
        let fileURL = portfolioStore.fileURL(for: item)
        
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    showToast("需要相册权限才能保存")
                }
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                if item.type == .livePhoto,
                   let imageURL = self.portfolioStore.livePhotoImageURL(for: item),
                   let videoURL = self.portfolioStore.livePhotoVideoURL(for: item) {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: imageURL, options: nil)
                    let videoOptions = PHAssetResourceCreationOptions()
                    videoOptions.shouldMoveFile = false
                    request.addResource(with: .pairedVideo, fileURL: videoURL, options: videoOptions)
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                }
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        showToast("已保存到相册")
                    } else {
                        showToast("保存失败：\(error?.localizedDescription ?? "未知错误")")
                    }
                }
            }
        }
    }
    
    private func deleteCurrentItem() {
        guard currentIndex < items.count else { return }
        let item = items[currentIndex]
        
        if items.count == 1 {
            // 最后一个，先关闭详情页再删除
            dismiss()
            // 延迟删除，确保 dismiss 动画完成后再移除数据
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                portfolioStore.deleteItem(item)
            }
        } else {
            // 先计算删除后应该显示的索引
            let newIndex = currentIndex >= items.count - 1 ? items.count - 2 : currentIndex
            withAnimation {
                portfolioStore.deleteItem(item)
                currentIndex = min(newIndex, max(0, items.count - 1))
            }
        }
    }
    
    private func showToast(_ message: String) {
        saveToAlbumMessage = message
        withAnimation(.spring(response: 0.3)) {
            showSaveToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.spring(response: 0.3)) {
                showSaveToast = false
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

extension UIApplication {
    static var screenBoundsHeight: CGFloat {
        if let windowScene = shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene {
            return windowScene.screen.bounds.height
        }
        return 852 // Fallback
    }
}

// MARK: - UIActivityViewController Wrapper

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
