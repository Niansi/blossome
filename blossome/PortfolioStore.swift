//
//  PortfolioStore.swift
//  blossome
//

import Foundation
import Combine
import AVFoundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

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

    func saveToPortfolio(videoURL: URL, effectName: String, type: PortfolioItemType, completion: @escaping (PortfolioItem?) -> Void) {
        let id = UUID()
        let videoFileName = "\(id.uuidString).mov"
        let thumbFileName = "\(id.uuidString)_thumb.jpg"
        let destVideoURL = portfolioDir.appendingPathComponent(videoFileName)
        let thumbURL = portfolioDir.appendingPathComponent(thumbFileName)

        do {
            try FileManager.default.copyItem(at: videoURL, to: destVideoURL)
        } catch {
            print("[Portfolio] Failed to copy video: \(error)")
            completion(nil)
            return
        }

        generateThumbnail(from: destVideoURL, to: thumbURL) { success in
            let item = PortfolioItem(type: type, fileName: videoFileName, thumbnailFileName: thumbFileName, effectName: effectName)

            DispatchQueue.main.async {
                self.items.insert(item, at: 0)
                self.saveManifest()
                completion(item)
            }
        }
    }

    func saveLivePhotoToPortfolio(videoURL: URL, imageURL: URL, effectName: String, completion: @escaping (PortfolioItem?) -> Void) {
        let id = UUID()
        let rawVideoFileName = "\(id.uuidString).mov"
        let thumbFileName = "\(id.uuidString)_thumb.jpg"
        let liveImageFileName = "\(id.uuidString)_live.jpg"
        let liveVideoFileName = "\(id.uuidString)_live.mov"

        let destVideoURL = portfolioDir.appendingPathComponent(rawVideoFileName)
        let thumbURL = portfolioDir.appendingPathComponent(thumbFileName)
        let destLiveImageURL = portfolioDir.appendingPathComponent(liveImageFileName)
        let destLiveVideoURL = portfolioDir.appendingPathComponent(liveVideoFileName)

        do {
            try FileManager.default.copyItem(at: videoURL, to: destVideoURL)
            try FileManager.default.copyItem(at: imageURL, to: destLiveImageURL)
            try FileManager.default.copyItem(at: videoURL, to: destLiveVideoURL)
        } catch {
            print("[Portfolio] Failed to copy LivePhoto resources: \(error)")
            completion(nil)
            return
        }

        generateThumbnail(from: destVideoURL, to: thumbURL) { [weak self] _ in
            guard let self = self else { return }
            let item = PortfolioItem(
                type: .livePhoto,
                fileName: rawVideoFileName,
                thumbnailFileName: thumbFileName,
                effectName: effectName,
                livePhotoImageFileName: liveImageFileName,
                livePhotoVideoFileName: liveVideoFileName
            )

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

        if let liveImageName = item.livePhotoImageFileName {
            try? FileManager.default.removeItem(at: portfolioDir.appendingPathComponent(liveImageName))
        }
        if let liveVideoName = item.livePhotoVideoFileName {
            try? FileManager.default.removeItem(at: portfolioDir.appendingPathComponent(liveVideoName))
        }

        items.removeAll { $0.id == item.id }
        saveManifest()
    }

    func fileURL(for item: PortfolioItem) -> URL {
        portfolioDir.appendingPathComponent(item.fileName)
    }

    func thumbnailURL(for item: PortfolioItem) -> URL {
        portfolioDir.appendingPathComponent(item.thumbnailFileName)
    }

    func livePhotoImageURL(for item: PortfolioItem) -> URL? {
        guard let name = item.livePhotoImageFileName else { return nil }
        return portfolioDir.appendingPathComponent(name)
    }

    func livePhotoVideoURL(for item: PortfolioItem) -> URL? {
        guard let name = item.livePhotoVideoFileName else { return nil }
        return portfolioDir.appendingPathComponent(name)
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
