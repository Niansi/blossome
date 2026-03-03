//
//  PortfolioDetailView.swift
//  blossome
//
//  Created by 武翔宇 on 2026/3/3.
//

import SwiftUI
import AVKit
import PhotosUI

struct PortfolioDetailView: View {
    let item: PortfolioItem
    @EnvironmentObject var portfolioStore: PortfolioStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var player: AVPlayer?
    @State private var isLivePhotoPlayback = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(item.effectName)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Text(item.createdAt, style: .date)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding()
                
                // Media viewer
                if item.type == .livePhoto {
                    livePhotoView
                } else {
                    videoView
                }
                
                Spacer()
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
        }
    }
    
    @ViewBuilder
    private var videoView: some View {
        if let player = player {
            VideoPlayer(player: player)
                .aspectRatio(contentMode: .fit)
                .cornerRadius(16)
                .shadow(radius: 20)
                .padding()
                .onAppear {
                    player.play()
                }
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    Image(systemName: "video.slash")
                        .font(.title)
                        .foregroundColor(.secondary)
                )
                .padding()
        }
    }
    
    @ViewBuilder
    private var livePhotoView: some View {
        // For Live Photo, we'll need to fetch it from Photos library
        // For now, let's show the video and note it's a Live Photo
        VStack(spacing: 12) {
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(16)
                    .shadow(radius: 20)
                    .onAppear {
                        player.play()
                    }
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        Image(systemName: "livephoto.slash")
                            .font(.title)
                            .foregroundColor(.secondary)
                    )
            }
            
            HStack(spacing: 8) {
                Image(systemName: "livephoto")
                    .foregroundColor(.purple)
                Text("这是一张 Live Photo（已保存到相册）")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding()
    }
    
    private func setupPlayer() {
        let videoURL = portfolioStore.fileURL(for: item)
        player = AVPlayer(url: videoURL)
    }
}
