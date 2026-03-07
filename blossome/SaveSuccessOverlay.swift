//
//  SaveSuccessOverlay.swift
//  blossome
//

import SwiftUI

struct SaveSuccessOverlay: View {
    let item: PortfolioItem
    let portfolioStore: PortfolioStore
    var onViewPortfolio: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)

                Text("保存成功")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                // Thumbnail preview
                let thumbURL = portfolioStore.thumbnailURL(for: item)
                if let uiImage = UIImage(contentsOfFile: thumbURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(spacing: 12) {
                    Button(action: onViewPortfolio) {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.fill")
                            Text("查看作品")
                        }
                    }
                    .buttonStyle(.glass)

                    Button(action: onDismiss) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("继续创作")
                        }
                    }
                    .buttonStyle(.glass)
                }
                .padding(.horizontal, 40)
            }
            .padding()
        }
    }
}
