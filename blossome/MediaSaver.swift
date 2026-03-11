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
import ReplayKit
import UniformTypeIdentifiers

class WebViewManager: ObservableObject {
    weak var webView: WKWebView?
    
    func startRecording() {
        webView?.evaluateJavaScript("startRecording()")
    }
}

class MediaSaver: NSObject {
    static let shared = MediaSaver()

    private var replayKitRecorder: ReplayKitRecorder?
    private var screenRecorder: ScreenRecorder?

    func startRecording(webView: WKWebView, duration: TimeInterval, forLivePhoto: Bool, effectName: String, completion: @escaping (URL?, URL?, Error?) -> Void) {
        // 停止任何已有录制
        replayKitRecorder?.stop()
        screenRecorder?.stop()

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
            guard let self else { return }

            // JS getBoundingClientRect() 返回的是 viewport 坐标（CSS 像素 = 逻辑点）
            // 对 ReplayKit 路径：直接使用 viewport 坐标转换为屏幕像素坐标（不加 adjustedContentInset）
            // 对 ScreenRecorder 降级路径：加 adjustedContentInset 转换为 WebView scrollView 坐标
            var viewportRect: CGRect? = nil
            if let dict = result as? [String: Any],
               let x = dict["x"] as? CGFloat,
               let y = dict["y"] as? CGFloat,
               let w = dict["width"] as? CGFloat,
               let h = dict["height"] as? CGFloat,
               w > 0, h > 0 {
                viewportRect = CGRect(x: x, y: y, width: w, height: h)
            }

            // 2. 尝试使用 ReplayKit（GPU 级捕获，主线程零阻塞）
            if RPScreenRecorder.shared().isAvailable {
                // viewport 坐标 → 窗口坐标（webView.convert 自动处理 WebView 在屏幕中的偏移）
                // → 屏幕像素坐标（乘以 screenScale）
                var canvasRectInScreenPixels: CGRect? = nil
                if let vpRect = viewportRect {
                    // viewport 坐标与 WebView 视图坐标一致（WKWebView ignoresSafeArea 情况下）
                    let windowRect = webView.convert(vpRect, to: nil)
                    let scale = webView.window?.screen.scale ?? UIScreen.main.scale
                    canvasRectInScreenPixels = CGRect(
                        x: windowRect.minX * scale,
                        y: windowRect.minY * scale,
                        width: windowRect.width * scale,
                        height: windowRect.height * scale
                    )
                }

                let recorder = ReplayKitRecorder()
                self.replayKitRecorder = recorder
                recorder.start(
                    canvasRectInScreenPixels: canvasRectInScreenPixels,
                    duration: duration,
                    forLivePhoto: forLivePhoto
                ) { video, image, err in
                    completion(video, image, err)
                    self.replayKitRecorder = nil
                }
            } else {
                // 3. 降级：使用 ScreenRecorder（drawHierarchy，需要 scrollView 坐标）
                print("[MediaSaver] RPScreenRecorder 不可用，降级为 ScreenRecorder")
                var canvasRectInScrollView: CGRect? = nil
                if let vpRect = viewportRect {
                    let inset = webView.scrollView.adjustedContentInset
                    canvasRectInScrollView = CGRect(
                        x: vpRect.minX + inset.left,
                        y: vpRect.minY + inset.top,
                        width: vpRect.width,
                        height: vpRect.height
                    )
                }
                let recorder = ScreenRecorder()
                self.screenRecorder = recorder
                recorder.start(
                    webView: webView,
                    duration: duration,
                    forLivePhoto: forLivePhoto,
                    canvasRect: canvasRectInScrollView
                ) { video, image, err in
                    completion(video, image, err)
                    self.screenRecorder = nil
                }
            }
        }
    }

    func stop() {
        replayKitRecorder?.stop()
        screenRecorder?.stop()
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
    
    // StillImageTime metadata track (required for Live Photo)
    var metadataInput: AVAssetWriterInput?
    var metadataAdaptor: AVAssetWriterInputMetadataAdaptor?
    
    var startTime: CFTimeInterval = 0
    var duration: TimeInterval = 0
    
    var completion: ((URL?, URL?, Error?) -> Void)?
    var isRecording = false
    
    var imageURL: URL?
    var hasCapturedKeyframe = false
    var keyframeImage: CGImage?
    var keyframeTime: CMTime?
    
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
            
            // Inject Content Identifier metadata (pairs MOV with JPEG)
            if isLivePhoto {
                let metadataItem = AVMutableMetadataItem()
                metadataItem.identifier = .quickTimeMetadataContentIdentifier
                metadataItem.value = assetIdentifier as NSString
                metadataItem.dataType = kCMMetadataBaseDataType_UTF8 as String
                assetWriter.metadata = [metadataItem]
            }
            
            let scale = webView.traitCollection.displayScale
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
            
            // Add StillImageTime timed metadata track (required for Live Photo)
            if isLivePhoto {
                setupStillImageTimeMetadataTrack()
            }
            
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: .zero)
            
        } catch {
            completion?(nil, nil, error)
        }
    }
    
    private func setupStillImageTimeMetadataTrack() {
        // Create format description for com.apple.quicktime.still-image-time
        let identifier = "mdta/com.apple.quicktime.still-image-time"
        let spec: NSDictionary = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier: identifier,
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType: kCMMetadataBaseDataType_SInt8 as String
        ]
        
        var formatDescription: CMFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [spec] as CFArray,
            formatDescriptionOut: &formatDescription
        )
        
        guard let desc = formatDescription else { return }
        
        let input = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: desc)
        input.expectsMediaDataInRealTime = true
        
        let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
        
        assetWriter.add(input)
        metadataInput = input
        metadataAdaptor = adaptor
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
        let scale = webView.traitCollection.displayScale
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
            keyframeTime = presentationTime
            
            // Write StillImageTime metadata at this exact time
            writeStillImageTimeMetadata(at: presentationTime)
        }
        
        if videoInput.isReadyForMoreMediaData {
            if let pixelBuffer = pixelBufferFromCGImage(cgImage: cgImage, size: size) {
                bufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            }
        }
    }
    private func writeStillImageTimeMetadata(at time: CMTime) {
        guard let adaptor = metadataAdaptor,
              let input = metadataInput,
              input.isReadyForMoreMediaData else { return }
        
        let item = AVMutableMetadataItem()
        item.identifier = AVMetadataIdentifier(rawValue: "mdta/com.apple.quicktime.still-image-time")
        item.keySpace = .quickTimeMetadata
        item.key = "com.apple.quicktime.still-image-time" as NSString
        item.value = 0 as NSNumber
        item.dataType = kCMMetadataBaseDataType_SInt8 as String
        
        let group = AVTimedMetadataGroup(
            items: [item],
            timeRange: CMTimeRange(start: time, duration: CMTime(value: 1, timescale: 600))
        )
        
        adaptor.append(group)
    }
    
    func stop() {
        guard isRecording else { return }
        isRecording = false
        displayLink.invalidate()
        displayLink = nil
        
        videoInput.markAsFinished()
        metadataInput?.markAsFinished()
        
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
