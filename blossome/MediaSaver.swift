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
}

class MediaSaver: NSObject {
    static let shared = MediaSaver()
    
    private var screenRecorder: ScreenRecorder?
    
    func startRecording(webView: WKWebView, duration: TimeInterval, forLivePhoto: Bool, effectName: String, completion: @escaping (URL?, URL?, Error?) -> Void) {
        if screenRecorder != nil {
            screenRecorder?.stop()
        }
        
        let js = """
        (function() {
            var canvas = document.querySelector('canvas');
            if (canvas) {
                var rect = canvas.getBoundingClientRect();
                return {x: rect.left, y: rect.top, width: rect.width, height: rect.height};
            }
            return null;
        })();
        """
        
        webView.evaluateJavaScript(js) { [weak self] result, error in
            var canvasRect: CGRect? = nil
            if let dict = result as? [String: Any],
               let x = dict["x"] as? CGFloat,
               let y = dict["y"] as? CGFloat,
               let w = dict["width"] as? CGFloat,
               let h = dict["height"] as? CGFloat {
                let inset = webView.scrollView.adjustedContentInset
                canvasRect = CGRect(x: x + inset.left, y: y + inset.top, width: w, height: h)
            }
            
            self?.screenRecorder = ScreenRecorder()
            self?.screenRecorder?.start(webView: webView, duration: duration, forLivePhoto: forLivePhoto, canvasRect: canvasRect) { video, image, err in
                completion(video, image, err)
                self?.screenRecorder = nil
            }
        }
    }
}

class ScreenRecorder {
    var webView: WKWebView!
    var videoURL: URL!
    var isLivePhoto: Bool = false
    var assetIdentifier: String = ""
    var canvasRect: CGRect?
    var captureSize: CGSize!
    
    var assetWriter: AVAssetWriter!
    var videoInput: AVAssetWriterInput!
    var bufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    var displayLink: CADisplayLink!
    
    var startTime: CFTimeInterval = 0
    var duration: TimeInterval = 0
    
    var completion: ((URL?, URL?, Error?) -> Void)?
    var isRecording = false
    
    var imageURL: URL?
    var hasCapturedKeyframe = false
    var keyframeImage: CGImage?
    
    func start(webView: WKWebView, duration: TimeInterval, forLivePhoto: Bool, canvasRect: CGRect? = nil, completion: @escaping (URL?, URL?, Error?) -> Void) {
        self.webView = webView
        self.duration = duration
        self.isLivePhoto = forLivePhoto
        self.completion = completion
        self.canvasRect = canvasRect
        self.assetIdentifier = UUID().uuidString
        
        let fileId = UUID().uuidString
        self.videoURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileId).appendingPathExtension("mov")
        if forLivePhoto {
            self.imageURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileId).appendingPathExtension("jpg")
        }
        
        setupWriter()
        
        startTime = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink.preferredFramesPerSecond = 30
        displayLink.add(to: .main, forMode: .common)
        isRecording = true
    }
    
    private func setupWriter() {
        do {
            assetWriter = try AVAssetWriter(outputURL: videoURL, fileType: .mov)
            
            // Scheme C: Inject Metadata dynamically on writing (Single Pass)
            if isLivePhoto {
                let metadataItem = AVMutableMetadataItem()
                metadataItem.identifier = .quickTimeMetadataContentIdentifier
                metadataItem.value = assetIdentifier as NSString
                metadataItem.dataType = kCMMetadataBaseDataType_UTF8 as String
                assetWriter.metadata = [metadataItem]
            }
            
            let scale = UIScreen.main.scale
            let targetSize = canvasRect?.size ?? webView.bounds.size
            let width = Int(targetSize.width * scale) / 2 * 2
            let height = Int(targetSize.height * scale) / 2 * 2
            self.captureSize = CGSize(width: CGFloat(width), height: CGFloat(height))
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
            bufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: attributes)
            
            assetWriter.add(videoInput)
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: .zero)
            
        } catch {
            completion?(nil, nil, error)
        }
    }
    
    @objc private func tick() {
        guard isRecording, assetWriter.status == .writing else { return }
        let currentTime = CACurrentMediaTime() - startTime
        
        if currentTime >= duration {
            stop()
            return
        }
        
        captureFrame(at: currentTime)
    }
    
    private func captureFrame(at time: CFTimeInterval) {
        let viewBounds = webView.bounds
        let size = self.captureSize!
        let scale = UIScreen.main.scale
        let presentationTime = CMTime(seconds: time, preferredTimescale: 600)
        
        let targetSize = canvasRect?.size ?? viewBounds.size
        
        // Use drawHierarchy synchronously for WKWebView
        UIGraphicsBeginImageContextWithOptions(targetSize, false, scale)
        if let context = UIGraphicsGetCurrentContext() {
            if let rect = canvasRect {
                context.translateBy(x: -rect.origin.x, y: -rect.origin.y)
            }
            webView.drawHierarchy(in: viewBounds, afterScreenUpdates: false)
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let cgImage = image?.cgImage else { return }
        
        if isLivePhoto && !hasCapturedKeyframe && time >= duration * 0.5 {
            hasCapturedKeyframe = true
            keyframeImage = cgImage
        } // We capture keyframe directly in memory (Single Pass Export)
        
        if videoInput.isReadyForMoreMediaData {
            if let pixelBuffer = pixelBufferFromCGImage(cgImage: cgImage, size: size) {
                bufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            }
        }
    }
    
    func stop() {
        guard isRecording else { return }
        isRecording = false
        displayLink.invalidate()
        displayLink = nil
        
        videoInput.markAsFinished()
        
        assetWriter.finishWriting { [weak self] in
            guard let self = self else { return }
            
            if self.assetWriter.status == .completed {
                if self.isLivePhoto {
                    self.saveLivePhotoKeyframe { error in
                        if let error = error {
                            self.completion?(nil, nil, error)
                        } else {
                            self.completion?(self.videoURL, self.imageURL, nil)
                        }
                    }
                } else {
                    self.completion?(self.videoURL, nil, nil)
                }
            } else {
                self.completion?(nil, nil, self.assetWriter.error ?? NSError(domain: "ScreenRecorder", code: 4, userInfo: nil))
            }
        }
    }
    
    private func saveLivePhotoKeyframe(completion: @escaping (Error?) -> Void) {
        guard let cgImage = keyframeImage, let imageURL = imageURL else {
            completion(NSError(domain: "ScreenRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No keyframe captured"]))
            return
        }
        
        guard let imageDestination = CGImageDestinationCreateWithURL(imageURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            completion(NSError(domain: "ScreenRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create destination"]))
            return
        }
        
        // Single Pass Export: Add MakerNote directly
        let makerAppleDictionary: [String: Any] = ["17": assetIdentifier]
        let metadata: [String: Any] = [kCGImagePropertyMakerAppleDictionary as String: makerAppleDictionary]
        
        CGImageDestinationAddImage(imageDestination, cgImage, metadata as CFDictionary)
        if !CGImageDestinationFinalize(imageDestination) {
            completion(NSError(domain: "ScreenRecorder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize image"]))
            return
        }
        
        completion(nil)
    }
    
    private func pixelBufferFromCGImage(cgImage: CGImage, size: CGSize) -> CVPixelBuffer? {
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var pxbuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, options as CFDictionary, &pxbuffer)
        
        guard status == kCVReturnSuccess, let buffer = pxbuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        let pxdata = CVPixelBufferGetBaseAddress(buffer)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        if let context = CGContext(data: pxdata, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        return buffer
    }
}
