//
//  PortfolioView.swift
//  blossome
//

import SwiftUI

struct PortfolioView: View {
    @EnvironmentObject var portfolioStore: PortfolioStore
    @State private var selectedItem: PortfolioItem?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        Group {
            if portfolioStore.items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("还没有作品")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("创建并保存你的第一个作品吧")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(portfolioStore.items) { item in
                            portfolioCell(item)
                                .onTapGesture {
                                    selectedItem = item
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("作品集")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedItem) { item in
            if let index = portfolioStore.items.firstIndex(where: { $0.id == item.id }) {
                PortfolioDetailView(initialIndex: index)
                    .environmentObject(portfolioStore)
            }
        }
    }

    @ViewBuilder
    private func portfolioCell(_ item: PortfolioItem) -> some View {
        let thumbURL = portfolioStore.thumbnailURL(for: item)
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if let uiImage = UIImage(contentsOfFile: thumbURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 160)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 160)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundColor(.secondary)
                        )
                }

                // Type badge with glass style
                HStack(spacing: 4) {
                    Image(systemName: item.type == .livePhoto ? "livephoto" : "video.fill")
                    Text(item.type == .livePhoto ? "Live" : "Video")
                }
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(8)
            }

            Text(item.effectName)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            Text(item.createdAt, style: .date)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .contextMenu {
            Button(role: .destructive) {
                portfolioStore.deleteItem(item)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
