//
//  PortfolioStore.swift
//  blossome
//

import Foundation
import Combine
import AVFoundation
import UIKit

class PortfolioStore: ObservableObject {
    static let shared = PortfolioStore()

    @Published var items: [PortfolioItem] = []

    private let portfolioDir: URL
    private let manifestURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        portfolioDir = docs.appendingPathComponent("Portfolio", isDirectory: true)
        manifestURL = portfolioDir.appendingPathComponent("portfolio.json")

        try? FileManager.default.createDirectory(at: portfolioDir, withIntermediateDirectories: true)
        loadManifest()
    }

    // MARK: - Public

    func saveToPortfolio(base64String: String, effectName: String, type: PortfolioItemType, completion: @escaping (PortfolioItem?) -> Void) {
        let parts = base64String.components(separatedBy: "base64,")
        let base64Data = parts.count > 1 ? parts[1] : base64String

        guard let data = Data(base64Encoded: base64Data, options: .ignoreUnknownCharacters) else {
            completion(nil)
            return
        }

        let id = UUID()
        let videoFileName = "\(id.uuidString).mp4"
        let thumbFileName = "\(id.uuidString)_thumb.jpg"
        let videoURL = portfolioDir.appendingPathComponent(videoFileName)
        let thumbURL = portfolioDir.appendingPathComponent(thumbFileName)

        do {
            try data.write(to: videoURL)
        } catch {
            print("[Portfolio] Failed to write video: \(error)")
            completion(nil)
            return
        }

        generateThumbnail(from: videoURL, to: thumbURL) { success in
            let item = PortfolioItem(type: type, fileName: videoFileName, thumbnailFileName: thumbFileName, effectName: effectName)

            DispatchQueue.main.async {
                self.items.insert(item, at: 0)
                self.saveManifest()
                completion(item)
            }
        }
    }

    func deleteItem(_ item: PortfolioItem) {
        let videoURL = portfolioDir.appendingPathComponent(item.fileName)
        let thumbURL = portfolioDir.appendingPathComponent(item.thumbnailFileName)
        try? FileManager.default.removeItem(at: videoURL)
        try? FileManager.default.removeItem(at: thumbURL)

        items.removeAll { $0.id == item.id }
        saveManifest()
    }

    func fileURL(for item: PortfolioItem) -> URL {
        portfolioDir.appendingPathComponent(item.fileName)
    }

    func thumbnailURL(for item: PortfolioItem) -> URL {
        portfolioDir.appendingPathComponent(item.thumbnailFileName)
    }

    // MARK: - Private

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([PortfolioItem].self, from: data) else {
            return
        }
        items = decoded
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: manifestURL)
    }

    private func generateThumbnail(from videoURL: URL, to thumbURL: URL, completion: @escaping (Bool) -> Void) {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)

        Task {
            do {
                let (cgImage, _) = try await generator.image(at: time)
                let uiImage = UIImage(cgImage: cgImage)
                if let jpegData = uiImage.jpegData(compressionQuality: 0.7) {
                    try jpegData.write(to: thumbURL)
                    completion(true)
                } else {
                    completion(false)
                }
            } catch {
                print("[Portfolio] Thumbnail generation failed: \(error)")
                // Write a placeholder — still save the item
                completion(false)
            }
        }
    }
}
