//
//  ReplayKitRecorder.swift
//  blossome
//
//  Phase 2 录制优化：用 RPScreenRecorder GPU 级帧捕获替代 drawHierarchy 主线程 CPU Readback。
//  全程在后台线程处理（crop → scale → encode），主线程零阻塞，p5.js 动画不再因录制而卡顿。
//

import ReplayKit
import AVFoundation
import CoreImage
import Photos
import ImageIO
import UniformTypeIdentifiers

class ReplayKitRecorder: NSObject {

    // MARK: - Properties

    private var assetWriter: AVAssetWriter!
    private var videoInput: AVAssetWriterInput!
    private var bufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    private var pixelBufferPool: CVPixelBufferPool?
    private var metadataInput: AVAssetWriterInput?
    private var metadataAdaptor: AVAssetWriterInputMetadataAdaptor?

    private var videoURL: URL!
    private var imageURL: URL?
    private var isLivePhoto: Bool = false
    private var assetIdentifier: String = ""

    /// Canvas 在屏幕中的归一化坐标（0-1，相对全屏），在实际帧里乘以帧尺寸得到像素级裁剪区域
    private var canvasRectNormalized: CGRect?
    private var outputSize: CGSize = .zero

    private var recordStartTime: CMTime?
    private var duration: TimeInterval = 0

    // Live Photo keyframe
    private var hasCapturedKeyframe = false
    private var keyframeImage: CGImage?
    private var keyframeTime: CMTime?

    private var isRecording = false
    private var isStopping = false
    private var writerReady = false   // setupWriter 已完成（第一帧时延迟初始化）
    private var completion: ((URL?, URL?, Error?) -> Void)?

    /// GPU 加速的 CIContext，跨帧复用，避免重复初始化（每次初始化约 5-20ms）
    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: CGColorSpaceCreateDeviceRGB() as Any
    ])

    // MARK: - Public API

    /// 开始 ReplayKit 录制。
    /// - Parameters:
    ///   - canvasRectInScreenPixels: Canvas 在屏幕像素坐标中的矩形（UIKit 坐标，原点左上角）。
    ///     传 nil 时捕获全屏（不裁剪）。
    ///   - duration: 录制时长（秒）
    ///   - forLivePhoto: 是否生成 Live Photo（同时输出 JPEG 关键帧）
    ///   - completion: 录制完成回调。视频录制返回 (videoURL, nil, nil)；
    ///     Live Photo 返回 (videoURL, imageURL, nil)；失败返回 (nil, nil, error)。
    func start(
        canvasRectNormalized: CGRect?,
        duration: TimeInterval,
        forLivePhoto: Bool,
        completion: @escaping (URL?, URL?, Error?) -> Void
    ) {
        self.canvasRectNormalized = canvasRectNormalized
        self.duration = duration
        self.isLivePhoto = forLivePhoto
        self.completion = completion
        self.assetIdentifier = UUID().uuidString

        let fileId = UUID().uuidString
        self.videoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileId).appendingPathExtension("mov")
        if forLivePhoto {
            self.imageURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(fileId).appendingPathExtension("jpg")
        }

        // outputSize 和 AVAssetWriter 在首帧时才能确定，因为 RPScreenRecorder 的帧分辨率
        // 不一定等于 UIScreen.main.scale × screenBounds（系统可能下采样）。
        // 因此这里只准备 URL，setup 推迟到 processSampleBuffer 首帧。

        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            completion(nil, nil, NSError(
                domain: "ReplayKitRecorder", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "RPScreenRecorder 不可用，请检查设备权限"]
            ))
            return
        }

        // 先标记开始，防止 startCapture handler 比 completionHandler 先到
        isRecording = true

        recorder.startCapture(handler: { [weak self] sampleBuffer, bufferType, error in
            guard let self, self.isRecording else { return }
            if let error = error {
                self.stop(with: error)
                return
            }
            guard bufferType == .video else { return }
            self.processSampleBuffer(sampleBuffer)
        }) { [weak self] error in
            if let error = error {
                self?.isRecording = false
                self?.completion?(nil, nil, error)
            }
        }
    }

    func stop() {
        stop(with: nil)
    }

    // MARK: - Setup（延迟到首帧，基于实际 buffer 尺寸）

    /// 在第一帧时调用，基于实际 buffer 尺寸 + 归一化裁剪区域计算真实的 outputSize
    private func setupWriter(actualBufferWidth: Int, actualBufferHeight: Int) -> Bool {
        // 计算实际像素裁剪区域
        let pixelCropRect: CGRect
        if let norm = canvasRectNormalized {
            let bw = CGFloat(actualBufferWidth)
            let bh = CGFloat(actualBufferHeight)
            let px = norm.minX * bw
            let py = norm.minY * bh
            let pw = norm.width * bw
            let ph = norm.height * bh
            pixelCropRect = CGRect(x: px, y: py, width: pw, height: ph)
        } else {
            pixelCropRect = CGRect(x: 0, y: 0, width: CGFloat(actualBufferWidth), height: CGFloat(actualBufferHeight))
        }
        outputSize = computeOutputSize(from: pixelCropRect.size)
        print("[ReplayKitRecorder] buffer=\(actualBufferWidth)×\(actualBufferHeight) pixelCrop=\(pixelCropRect) outputSize=\(outputSize)")

        do {
            assetWriter = try AVAssetWriter(outputURL: videoURL, fileType: .mov)

            if isLivePhoto {
                let item = AVMutableMetadataItem()
                item.identifier = .quickTimeMetadataContentIdentifier
                item.value = assetIdentifier as NSString
                item.dataType = kCMMetadataBaseDataType_UTF8 as String
                assetWriter.metadata = [item]
            }

            let w = Int(outputSize.width)
            let h = Int(outputSize.height)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: w,
                AVVideoHeightKey: h
            ]
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true

            let bufAttrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]
            bufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: bufAttrs
            )
            assetWriter.add(videoInput)

            if isLivePhoto { setupStillImageTimeTrack() }

            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: .zero)

            createPixelBufferPool(width: w, height: h)
            return true
        } catch {
            completion?(nil, nil, error)
            return false
        }
    }

    private func computeOutputSize(from cropSize: CGSize) -> CGSize {
        // 最大短边 1080px，与 Phase 1 [方案C] 保持一致
        let maxShortSide: CGFloat = 1080
        let shortSide = min(cropSize.width, cropSize.height)
        let scale = shortSide > maxShortSide ? maxShortSide / shortSide : 1.0
        let w = Int(cropSize.width * scale) / 2 * 2   // 保证偶数（H264 要求）
        let h = Int(cropSize.height * scale) / 2 * 2
        return CGSize(width: CGFloat(w), height: CGFloat(h))
    }

    private func createPixelBufferPool(width: Int, height: Int) {
        // 预分配 6 个缓冲区：捕获 1 + 编码队列 2 + 裁剪处理 1 + 安全余量 2
        let poolAttrs: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 6]
        let bufAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault, poolAttrs as CFDictionary, bufAttrs as CFDictionary, &pixelBufferPool
        )
        if status != kCVReturnSuccess {
            print("[ReplayKitRecorder] ⚠️ CVPixelBufferPool 创建失败: \(status)，将影响性能")
        }
    }

    // MARK: - Frame Processing (后台线程)

    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 首帧：延迟初始化 AVAssetWriter（此时才知道实际帧分辨率）
        if !writerReady {
            let bw = CVPixelBufferGetWidth(pixelBuffer)
            let bh = CVPixelBufferGetHeight(pixelBuffer)
            guard setupWriter(actualBufferWidth: bw, actualBufferHeight: bh) else { return }
            writerReady = true
        }

        guard assetWriter.status == .writing else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if recordStartTime == nil { recordStartTime = timestamp }

        let elapsed = CMTimeGetSeconds(CMTimeSubtract(timestamp, recordStartTime!))
        guard elapsed >= 0 else { return }

        if elapsed >= duration {
            stop()
            return
        }

        let presentationTime = CMTime(seconds: elapsed, preferredTimescale: 600)

        guard let outputBuffer = cropAndScale(pixelBuffer: pixelBuffer) else { return }

        if isLivePhoto && !hasCapturedKeyframe && elapsed >= duration * 0.5 {
            hasCapturedKeyframe = true
            keyframeTime = presentationTime
            let ciImg = CIImage(cvPixelBuffer: outputBuffer)
            keyframeImage = ciContext.createCGImage(ciImg, from: ciImg.extent)
            writeStillImageTimeMetadata(at: presentationTime)
        }

        if videoInput.isReadyForMoreMediaData {
            bufferAdaptor.append(outputBuffer, withPresentationTime: presentationTime)
        }
    }

    /// GPU 加速：CIImage 裁剪（基于归一化坐标）+ 缩放 → CVPixelBuffer
    private func cropAndScale(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let bw = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bh = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        var processed = ciImage

        if let norm = canvasRectNormalized {
            // 归一化坐标 × 实际帧尺寸 → 像素级 UIKit 裁剪区域（y 从顶部）
            let pxX   = norm.minX * bw
            let pxY   = norm.minY * bh         // UIKit: y 从屏幕顶部
            let pxW   = norm.width * bw
            let pxH   = norm.height * bh

            // CIImage 坐标 Y 轴朝上（左下角原点）→ 翻转 Y
            let ciY = bh - (pxY + pxH)
            let ciCropRect = CGRect(x: pxX, y: ciY, width: pxW, height: pxH)
            processed = ciImage.cropped(to: ciCropRect)
        }

        // 平移到 CIImage 原点，再等比缩放到 outputSize
        let scaleX = outputSize.width / processed.extent.width
        let scaleY = outputSize.height / processed.extent.height
        if abs(scaleX - 1.0) > 0.001 || abs(scaleY - 1.0) > 0.001 {
            let translated = processed.transformed(by: CGAffineTransform(
                translationX: -processed.extent.minX, y: -processed.extent.minY
            ))
            processed = translated.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        }

        // 从 Pool 取 buffer（零 malloc，避免每帧内存抖动）
        var outBuffer: CVPixelBuffer?
        if let pool = pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outBuffer)
        }
        guard let buffer = outBuffer else { return nil }

        // CIContext.render：GPU 加速，直接写入 IOSurface-backed buffer
        ciContext.render(
            processed,
            to: buffer,
            bounds: CGRect(origin: .zero, size: outputSize),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return buffer
    }

    // MARK: - Stop

    private func stop(with error: Error?) {
        guard isRecording && !isStopping else { return }
        isStopping = true
        isRecording = false

        RPScreenRecorder.shared().stopCapture { [weak self] stopError in
            guard let self else { return }

            self.videoInput.markAsFinished()
            self.metadataInput?.markAsFinished()
            self.pixelBufferPool = nil

            if let err = error ?? stopError {
                self.completion?(nil, nil, err)
                return
            }

            self.assetWriter.finishWriting { [weak self] in
                guard let self else { return }
                if self.assetWriter.status == .completed {
                    if self.isLivePhoto {
                        self.saveLivePhotoKeyframe { saveError in
                            if let saveError = saveError {
                                self.completion?(nil, nil, saveError)
                            } else {
                                self.completion?(self.videoURL, self.imageURL, nil)
                            }
                        }
                    } else {
                        self.completion?(self.videoURL, nil, nil)
                    }
                } else {
                    self.completion?(nil, nil, self.assetWriter.error
                        ?? NSError(domain: "ReplayKitRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "写入失败"]))
                }
            }
        }
    }

    // MARK: - Live Photo Metadata（与 ScreenRecorder 逻辑相同）

    private func setupStillImageTimeTrack() {
        let identifier = "mdta/com.apple.quicktime.still-image-time"
        let spec: NSDictionary = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier: identifier,
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType: kCMMetadataBaseDataType_SInt8 as String
        ]
        var formatDesc: CMFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [spec] as CFArray,
            formatDescriptionOut: &formatDesc
        )
        guard let desc = formatDesc else { return }
        let input = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: desc)
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
        assetWriter.add(input)
        metadataInput = input
        metadataAdaptor = adaptor
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

    private func saveLivePhotoKeyframe(completion: @escaping (Error?) -> Void) {
        guard let cgImage = keyframeImage, let imageURL = imageURL else {
            completion(NSError(
                domain: "ReplayKitRecorder", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "未能捕获关键帧"]
            ))
            return
        }
        guard let dest = CGImageDestinationCreateWithURL(
            imageURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            completion(NSError(
                domain: "ReplayKitRecorder", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG destination"]
            ))
            return
        }
        // 写入 Apple MakerNote：assetIdentifier 用于与 MOV 配对
        let makerApple: [String: Any] = ["17": assetIdentifier]
        let metadata: [String: Any] = [kCGImagePropertyMakerAppleDictionary as String: makerApple]
        CGImageDestinationAddImage(dest, cgImage, metadata as CFDictionary)
        if CGImageDestinationFinalize(dest) {
            completion(nil)
        } else {
            completion(NSError(
                domain: "ReplayKitRecorder", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Failed to finalize JPEG"]
            ))
        }
    }
}
