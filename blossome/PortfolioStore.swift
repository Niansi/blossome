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

    func saveLivePhotoToPortfolio(base64String: String, effectName: String, completion: @escaping (PortfolioItem?) -> Void) {
        let parts = base64String.components(separatedBy: "base64,")
        let base64Data = parts.count > 1 ? parts[1] : base64String

        guard let data = Data(base64Encoded: base64Data, options: .ignoreUnknownCharacters) else {
            completion(nil)
            return
        }

        let id = UUID()
        let rawVideoFileName = "\(id.uuidString).mp4"
        let thumbFileName = "\(id.uuidString)_thumb.jpg"
        let liveImageFileName = "\(id.uuidString)_live.jpg"
        let liveVideoFileName = "\(id.uuidString)_live.mov"

        let rawVideoURL = portfolioDir.appendingPathComponent(rawVideoFileName)
        let thumbURL = portfolioDir.appendingPathComponent(thumbFileName)
        let liveImageURL = portfolioDir.appendingPathComponent(liveImageFileName)
        let liveVideoURL = portfolioDir.appendingPathComponent(liveVideoFileName)

        do {
            try data.write(to: rawVideoURL)
        } catch {
            print("[Portfolio] Failed to write video: \(error)")
            completion(nil)
            return
        }

        let assetIdentifier = UUID().uuidString

        Task {
            // Transcode raw video to .mov
            let rawAsset = AVURLAsset(url: rawVideoURL)
            let transcodedURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")

            guard let exportSession = AVAssetExportSession(asset: rawAsset, presetName: AVAssetExportPresetHighestQuality) else {
                print("[Portfolio] Failed to create export session")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            exportSession.outputURL = transcodedURL
            exportSession.outputFileType = .mov
            await exportSession.export()

            guard exportSession.status == .completed else {
                print("[Portfolio] Transcode failed: \(exportSession.error?.localizedDescription ?? "unknown")")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Extract key frame for LivePhoto image
            let transcodedAsset = AVURLAsset(url: transcodedURL)
            let generator = AVAssetImageGenerator(asset: transcodedAsset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero

            do {
                let duration = try await transcodedAsset.load(.duration)
                let midTime = CMTimeMultiplyByFloat64(duration, multiplier: 0.5)
                let (cgImage, _) = try await generator.image(at: midTime)

                // Write JPEG with MakerNote (LivePhoto asset identifier)
                guard let imageDestination = CGImageDestinationCreateWithURL(liveImageURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                    print("[Portfolio] Failed to create image destination")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                let makerAppleDictionary: [String: Any] = ["17": assetIdentifier]
                let metadata: [String: Any] = [kCGImagePropertyMakerAppleDictionary as String: makerAppleDictionary]
                CGImageDestinationAddImage(imageDestination, cgImage, metadata as CFDictionary)
                guard CGImageDestinationFinalize(imageDestination) else {
                    print("[Portfolio] Failed to finalize LivePhoto image")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                // Inject ContentIdentifier metadata into video
                LivePhotoVideoWriter.addMetadataViaExportSession(to: transcodedURL, outputURL: liveVideoURL, assetIdentifier: assetIdentifier) { [weak self] error in
                    guard let self = self else { return }
                    if let error = error {
                        print("[Portfolio] LivePhoto video metadata injection failed: \(error)")
                        DispatchQueue.main.async { completion(nil) }
                        return
                    }

                    // Generate thumbnail
                    self.generateThumbnail(from: rawVideoURL, to: thumbURL) { _ in
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

                    // Clean up temp transcoded file
                    try? FileManager.default.removeItem(at: transcodedURL)
                }
            } catch {
                print("[Portfolio] Failed to generate LivePhoto key frame: \(error)")
                DispatchQueue.main.async { completion(nil) }
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
