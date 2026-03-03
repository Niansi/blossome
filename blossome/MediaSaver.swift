//
//  MediaSaver.swift
//  blossome
//

import Photos
import UIKit
import WebKit
import Combine
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

class WebViewManager: ObservableObject {
    weak var webView: WKWebView?
    
    func startRecording() {
        webView?.evaluateJavaScript("startRecording()")
    }
    
    func stopRecording() {
        webView?.evaluateJavaScript("stopRecordingAndGetResult()")
    }
}

class MediaSaver: NSObject {
    static let shared = MediaSaver()
    
    func saveVideo(base64String: String, completion: @escaping (Bool, Error?) -> Void) {
        let parts = base64String.components(separatedBy: "base64,")
        let base64DataString = parts.count > 1 ? parts[1] : base64String
        
        guard let data = Data(base64Encoded: base64DataString, options: .ignoreUnknownCharacters) else {
            completion(false, NSError(domain: "MediaSaver", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid video data"]))
            return
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        do {
            try data.write(to: tempURL)
        } catch {
            completion(false, error)
            return
        }
        
        saveVideoToPhotos(url: tempURL, completion: completion)
    }
    
    func saveVideoToPhotos(url: URL, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                completion(false, NSError(domain: "MediaSaver", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"]))
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                DispatchQueue.main.async {
                    completion(success, error)
                }
            }
        }
    }
    
    func saveLivePhoto(base64String: String, completion: @escaping (Bool, Error?) -> Void) {
        let parts = base64String.components(separatedBy: "base64,")
        let base64DataString = parts.count > 1 ? parts[1] : base64String
        
        guard let data = Data(base64Encoded: base64DataString, options: .ignoreUnknownCharacters) else {
            print("[LivePhoto] ❌ Invalid base64 video data")
            completion(false, NSError(domain: "MediaSaver", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid video data"]))
            return
        }
        
        print("[LivePhoto] ✅ Decoded base64 data, size: \(data.count) bytes")
        
        let assetIdentifier = UUID().uuidString
        // 使用 .mov 作为原始文件扩展名（WKWebView 录制的可能是 webm）
        let rawVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        let transcodedVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        let tempImageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        
        do {
            try data.write(to: rawVideoURL)
            print("[LivePhoto] ✅ Raw video written to: \(rawVideoURL.lastPathComponent)")
        } catch {
            print("[LivePhoto] ❌ Failed to write raw video: \(error)")
            completion(false, error)
            return
        }
        
        // 步骤 0：将原始视频转码为 .mov（兼容 AVFoundation）
        let rawAsset = AVURLAsset(url: rawVideoURL)
        
        Task {
            // 检查原始资源是否能被 AVFoundation 加载
            do {
                let duration = try await rawAsset.load(.duration)
                print("[LivePhoto] ✅ Raw asset duration: \(CMTimeGetSeconds(duration))s")
            } catch {
                print("[LivePhoto] ❌ Raw asset cannot be loaded by AVFoundation: \(error)")
                print("[LivePhoto] ⚠️ This likely means the video is in webm format, which AVFoundation cannot process.")
                DispatchQueue.main.async {
                    completion(false, NSError(domain: "MediaSaver", code: 10, userInfo: [NSLocalizedDescriptionKey: "Video format not compatible. WebView may have recorded in webm format."]))
                }
                return
            }
            
            // 使用 AVAssetExportSession 转码为 .mov
            guard let exportSession = AVAssetExportSession(asset: rawAsset, presetName: AVAssetExportPresetHighestQuality) else {
                print("[LivePhoto] ❌ Failed to create AVAssetExportSession")
                DispatchQueue.main.async {
                    completion(false, NSError(domain: "MediaSaver", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"]))
                }
                return
            }
            
            exportSession.outputURL = transcodedVideoURL
            exportSession.outputFileType = .mov
            
            print("[LivePhoto] 🔄 Starting transcoding to .mov ...")
            await exportSession.export()
            
            guard exportSession.status == .completed else {
                let exportError = exportSession.error
                print("[LivePhoto] ❌ Transcode failed: \(exportError?.localizedDescription ?? "unknown")")
                DispatchQueue.main.async {
                    completion(false, exportError ?? NSError(domain: "MediaSaver", code: 12, userInfo: [NSLocalizedDescriptionKey: "Transcode failed"]))
                }
                return
            }
            
            print("[LivePhoto] ✅ Transcoded to .mov successfully")
            
            // 步骤 1：从转码后的视频中提取关键帧
            let transcodedAsset = AVURLAsset(url: transcodedVideoURL)
            let generator = AVAssetImageGenerator(asset: transcodedAsset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            
            do {
                let duration = try await transcodedAsset.load(.duration)
                let midTime = CMTimeMultiplyByFloat64(duration, multiplier: 0.5)
                print("[LivePhoto] 📸 Generating key photo at \(CMTimeGetSeconds(midTime))s")
                
                let (cgImage, _) = try await generator.image(at: midTime)
                print("[LivePhoto] ✅ Key photo generated")
                
                self.finalizeLivePhoto(cgImage: cgImage, assetIdentifier: assetIdentifier, tempVideoURL: transcodedVideoURL, tempImageURL: tempImageURL, completion: completion)
            } catch {
                print("[LivePhoto] ❌ Failed to generate key photo: \(error)")
                DispatchQueue.main.async {
                    completion(false, NSError(domain: "MediaSaver", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to generate key photo: \(error.localizedDescription)"]))
                }
            }
        }
    }
    
    private func finalizeLivePhoto(cgImage: CGImage, assetIdentifier: String, tempVideoURL: URL, tempImageURL: URL, completion: @escaping (Bool, Error?) -> Void) {
        print("[LivePhoto] 🔧 Finalizing LivePhoto with assetIdentifier: \(assetIdentifier)")
        // 2. Add MakerNote to Image
        guard let imageDestination = CGImageDestinationCreateWithURL(tempImageURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            print("[LivePhoto] ❌ Failed to create image destination")
            DispatchQueue.main.async {
                completion(false, NSError(domain: "MediaSaver", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"]))
            }
            return
        }
        
        // Apple's LivePhoto MakerNote format
        // The correct format is: { kCGImagePropertyMakerAppleDictionary: { "17": assetIdentifier } }
        let makerAppleDictionary: [String: Any] = ["17": assetIdentifier]
        let metadata: [String: Any] = [kCGImagePropertyMakerAppleDictionary as String: makerAppleDictionary]
        
        CGImageDestinationAddImage(imageDestination, cgImage, metadata as CFDictionary)
        if !CGImageDestinationFinalize(imageDestination) {
            print("[LivePhoto] ❌ Failed to finalize image")
            DispatchQueue.main.async {
                completion(false, NSError(domain: "MediaSaver", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize image"]))
            }
            return
        }
        print("[LivePhoto] ✅ Key photo with MakerNote saved to: \(tempImageURL.lastPathComponent)")
        print("[LivePhoto] 📋 AssetIdentifier used: \(assetIdentifier)")
        
        // 3. Inject Metadata to Video using AVAssetExportSession
        let outputVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        print("[LivePhoto] 🔄 Injecting metadata to video using AVAssetExportSession...")
        LivePhotoVideoWriter.addMetadataViaExportSession(to: tempVideoURL, outputURL: outputVideoURL, assetIdentifier: assetIdentifier) { error in
            if let error = error {
                print("[LivePhoto] ❌ Metadata injection failed: \(error)")
                DispatchQueue.main.async {
                    completion(false, error)
                }
                return
            }
            print("[LivePhoto] ✅ Metadata injected successfully")
            
            // 4. Save to Photos

            // Verify video metadata before saving
            Task {
                let verifyAsset = AVURLAsset(url: outputVideoURL)
                let metadata = try? await verifyAsset.load(.metadata)
                print("[LivePhoto] 🔍 Video metadata items: \(metadata?.count ?? 0)")
                for item in metadata ?? [] {
                    let valueString: String
                    if let stringValue = item.value as? String {
                        valueString = stringValue
                    } else if let value = item.value {
                        valueString = String(describing: value)
                    } else {
                        valueString = "nil"
                    }
                    let identifierRaw = (item.identifier?.rawValue as? String) ?? "unknown"
                    print("[LivePhoto] 🔍 Metadata: \(identifierRaw) = \(valueString)")
                }
            }

            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    DispatchQueue.main.async {
                        completion(false, NSError(domain: "MediaSaver", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"]))
                    }
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()

                    // Photo options - set asset identifier in the filename
                    let photoOptions = PHAssetResourceCreationOptions()
                    photoOptions.originalFilename = "\(assetIdentifier)_IMG.jpg"

                    // Video options - set asset identifier in the filename
                    let videoOptions = PHAssetResourceCreationOptions()
                    videoOptions.originalFilename = "\(assetIdentifier)_VID.mov"

                    request.addResource(with: .photo, fileURL: tempImageURL, options: photoOptions)
                    request.addResource(with: .pairedVideo, fileURL: outputVideoURL, options: videoOptions)
                }) { success, error in
                    print("[LivePhoto] \(success ? "✅" : "❌") PHPhotoLibrary save result: success=\(success), error=\(error?.localizedDescription ?? "none")")
                    DispatchQueue.main.async {
                        completion(success, error)
                    }
                }
            }
        }
    }
}

struct LivePhotoVideoWriter {
    // Use AVAssetExportSession for reliable metadata injection
    static func addMetadataViaExportSession(to videoURL: URL, outputURL: URL, assetIdentifier: String, completion: @escaping (Error?) -> Void) {
        let asset = AVURLAsset(url: videoURL)

        Task {
            do {
                // Create metadata item
                let metadataItem = AVMutableMetadataItem()
                metadataItem.identifier = .quickTimeMetadataContentIdentifier
                metadataItem.value = assetIdentifier as NSString
                metadataItem.dataType = kCMMetadataBaseDataType_UTF8 as String

                let identifierString = metadataItem.identifier?.rawValue as? String ?? "nil"
                let valueString = metadataItem.value as? String ?? assetIdentifier
                print("[LivePhoto] 📋 Writing metadata to video - Identifier: \(identifierString), Value: \(valueString)")

                // Create export session with metadata
                guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                    print("[LivePhoto] ❌ Failed to create AVAssetExportSession")
                    DispatchQueue.main.async {
                        completion(NSError(domain: "MediaSaver", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"]))
                    }
                    return
                }

                // Set metadata
                exportSession.metadata = [metadataItem]

                exportSession.outputURL = outputURL
                exportSession.outputFileType = .mov

                print("[LivePhoto] 🔄 Starting export with metadata...")
                await exportSession.export()

                guard exportSession.status == .completed else {
                    let exportError = exportSession.error
                    print("[LivePhoto] ❌ Export failed: \(exportError?.localizedDescription ?? "unknown")")
                    DispatchQueue.main.async {
                        completion(exportError ?? NSError(domain: "MediaSaver", code: 12, userInfo: [NSLocalizedDescriptionKey: "Export failed"]))
                    }
                    return
                }

                print("[LivePhoto] ✅ Export with metadata successful")

                // Verify metadata was written
                let verifyAsset = AVURLAsset(url: outputURL)
                let metadata = try? await verifyAsset.load(.metadata)
                print("[LivePhoto] 🔍 Video metadata items: \(metadata?.count ?? 0)")
                for item in metadata ?? [] {
                    let valueString: String
                    if let stringValue = item.value as? String {
                        valueString = stringValue
                    } else if let value = item.value {
                        valueString = String(describing: value)
                    } else {
                        valueString = "nil"
                    }
                    let identifier = (item.identifier?.rawValue as? String) ?? "unknown"
                    print("[LivePhoto] 🔍 Metadata: \(identifier) = \(valueString)")
                }

                DispatchQueue.main.async {
                    completion(nil)
                }
            } catch {
                print("[LivePhoto] ❌ Error during metadata export: \(error)")
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }
}
