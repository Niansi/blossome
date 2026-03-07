//
//  PortfolioDetailView.swift
//  blossome
//
//  Created by 武翔宇 on 2026/3/3.
//

import SwiftUI
import AVKit
import PhotosUI

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

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        if uiView.livePhoto == nil {
            loadLivePhoto(into: uiView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func loadLivePhoto(into view: PHLivePhotoView) {
        PHLivePhoto.request(
            withResourceFileURLs: [imageURL, videoURL],
            placeholderImage: UIImage(contentsOfFile: imageURL.path),
            targetSize: .zero,
            contentMode: .default
        ) { livePhoto, info in
            let isDegraded = (info[PHLivePhotoInfoIsDegradedKey] as? Bool) ?? false
            if let livePhoto = livePhoto {
                DispatchQueue.main.async {
                    view.livePhoto = livePhoto
                    if !isDegraded {
                        view.startPlayback(with: .full)
                    }
                }
            }
        }
    }

    class Coordinator: NSObject, PHLivePhotoViewDelegate {
        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            livePhotoView.startPlayback(with: .full)
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
            deactivatePlayer()
        }
        .onChange(of: item.id) { _, _ in
            // Defensive: ensure reused page views don't keep stale AVPlayer state.
            deactivatePlayer()
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
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        player?.pause()
        player = nil
        isPlaying = true
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
           FileManager.default.fileExists(atPath: imageURL.path),
           FileManager.default.fileExists(atPath: videoURL.path) {
            LivePhotoUIView(imageURL: imageURL, videoURL: videoURL)
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
    let items: [PortfolioItem]
    let initialIndex: Int
    @EnvironmentObject var portfolioStore: PortfolioStore
    @Environment(\.dismiss) private var dismiss

    @State private var scrolledID: PortfolioItem.ID?
    @State private var currentIndex: Int = 0

    private var currentItem: PortfolioItem {
        items[currentIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Paging ScrollView
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        PortfolioPageView(item: item, isCurrentPage: item.id == scrolledID)
                            .environmentObject(portfolioStore)
                            .containerRelativeFrame(.horizontal)
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledID)
            .ignoresSafeArea()

            // Overlay: top bar + bottom info
            VStack {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()

                    // Page indicator
                    Text("\(currentIndex + 1) / \(items.count)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding()

                Spacer()

                // Bottom info
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: currentItem.type == .livePhoto ? "livephoto" : "video.fill")
                        Text(currentItem.effectName)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 2)

                    Text(currentItem.createdAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 2)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            currentIndex = initialIndex
            scrolledID = items[safe: initialIndex]?.id
        }
        .onChange(of: scrolledID) { _, newID in
            if let newID, let idx = items.firstIndex(where: { $0.id == newID }) {
                currentIndex = idx
            }
        }
        .statusBarHidden()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
