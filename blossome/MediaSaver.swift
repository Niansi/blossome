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

final class VideoProcessingState: @unchecked Sendable {
    let videoWriterInput: AVAssetWriterInput
    let reader: AVAssetReader
    let readerOutput: AVAssetReaderTrackOutput
    let writer: AVAssetWriter
    
    init(videoWriterInput: AVAssetWriterInput, reader: AVAssetReader, readerOutput: AVAssetReaderTrackOutput, writer: AVAssetWriter) {
        self.videoWriterInput = videoWriterInput
        self.reader = reader
        self.readerOutput = readerOutput
        self.writer = writer
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
        
        let makerApple = ["17": assetIdentifier] as [String: Any]
        let metadata = [kCGImagePropertyMakerAppleDictionary as String: makerApple] as [String: Any]
        
        CGImageDestinationAddImage(imageDestination, cgImage, metadata as CFDictionary)
        if !CGImageDestinationFinalize(imageDestination) {
            print("[LivePhoto] ❌ Failed to finalize image")
            DispatchQueue.main.async {
                completion(false, NSError(domain: "MediaSaver", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize image"]))
            }
            return
        }
        print("[LivePhoto] ✅ Key photo with MakerNote saved to: \(tempImageURL.lastPathComponent)")
        
        // 3. Inject Metadata to Video
        let outputVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        print("[LivePhoto] 🔄 Injecting metadata to video...")
        LivePhotoVideoWriter.addMetadata(to: tempVideoURL, outputURL: outputVideoURL, assetIdentifier: assetIdentifier) { error in
            if let error = error {
                print("[LivePhoto] ❌ Metadata injection failed: \(error)")
                DispatchQueue.main.async {
                    completion(false, error)
                }
                return
            }
            print("[LivePhoto] ✅ Metadata injected successfully")
            
            // 4. Save to Photos
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    DispatchQueue.main.async {
                        completion(false, NSError(domain: "MediaSaver", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"]))
                    }
                    return
                }
                
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: tempImageURL, options: nil)
                    request.addResource(with: .pairedVideo, fileURL: outputVideoURL, options: nil)
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
    static func addMetadata(to videoURL: URL, outputURL: URL, assetIdentifier: String, completion: @escaping (Error?) -> Void) {
        let asset = AVURLAsset(url: videoURL)
        
        Task {
            guard let assetTrack = try? await asset.loadTracks(withMediaType: .video).first else {
                completion(NSError(domain: "MediaSaver", code: 4, userInfo: [NSLocalizedDescriptionKey: "No video track"]))
                return
            }
            
            do {
                let preferredTransform = try await assetTrack.load(.preferredTransform)
                let duration = try await asset.load(.duration)
                let timeRange = CMTimeRangeMake(start: .zero, duration: duration)
                
                let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
                
                // Using passthrough output settings
                let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
                videoWriterInput.expectsMediaDataInRealTime = false
                videoWriterInput.transform = preferredTransform
                writer.add(videoWriterInput)
                
                let metadataSpec: [String: Any] = [
                    kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: AVMetadataIdentifier.quickTimeMetadataContentIdentifier.rawValue,
                    kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: kCMMetadataBaseDataType_UTF8 as String
                ]
                var formatDesc: CMFormatDescription?
                CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
                    allocator: kCFAllocatorDefault,
                    metadataType: kCMMetadataFormatType_Boxed,
                    metadataSpecifications: [metadataSpec] as CFArray,
                    formatDescriptionOut: &formatDesc
                )
                guard let formatDesc else {
                    completion(NSError(domain: "MediaSaver", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create metadata format"]))
                    return
                }
                
                let metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: formatDesc)
                let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
                writer.add(metadataAdaptor.assetWriterInput)
                
                let reader = try AVAssetReader(asset: asset)
                // Passthrough reader output
                let readerOutput = AVAssetReaderTrackOutput(track: assetTrack, outputSettings: nil)
                reader.add(readerOutput)
                
                guard writer.startWriting() else {
                    completion(writer.error ?? NSError(domain: "MediaSaver", code: 6, userInfo: [NSLocalizedDescriptionKey: "Writer failed to start"]))
                    return
                }
                writer.startSession(atSourceTime: .zero)
                
                guard reader.startReading() else {
                    completion(reader.error ?? NSError(domain: "MediaSaver", code: 7, userInfo: [NSLocalizedDescriptionKey: "Reader failed to start"]))
                    return
                }
                
                let metadataItem = AVMutableMetadataItem()
                metadataItem.identifier = .quickTimeMetadataContentIdentifier
                metadataItem.value = assetIdentifier as NSString
                metadataItem.dataType = kCMMetadataBaseDataType_UTF8 as String
                
                let metadataGroup = AVTimedMetadataGroup(items: [metadataItem], timeRange: timeRange)
                metadataAdaptor.append(metadataGroup)
                
                let state = VideoProcessingState(videoWriterInput: videoWriterInput, reader: reader, readerOutput: readerOutput, writer: writer)
                
                state.videoWriterInput.requestMediaDataWhenReady(on: DispatchQueue(label: "videoWriterQueue")) { [state] in
                    while state.videoWriterInput.isReadyForMoreMediaData {
                        if state.reader.status == .reading, let sampleBuffer = state.readerOutput.copyNextSampleBuffer() {
                            state.videoWriterInput.append(sampleBuffer)
                        } else {
                            state.videoWriterInput.markAsFinished()
                            state.writer.finishWriting {
                                completion(state.writer.error)
                            }
                            break
                        }
                    }
                }
            } catch {
                completion(error)
            }
        }
    }
}
