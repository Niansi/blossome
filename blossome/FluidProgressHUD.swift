import SwiftUI

enum FluidProgressState: Equatable {
    case idle
    case processing(type: MediaType, estimatedDuration: TimeInterval)
    case success
    case error(String)
}

enum MediaType {
    case video
    case livePhoto
    
    var iconName: String {
        switch self {
        case .video: return "video.fill"
        case .livePhoto: return "livephoto"
        }
    }
    
    var processingText: String {
        switch self {
        case .video: return "正在导出..."
        case .livePhoto: return "生成 Live Photo..."
        }
    }
}

struct FluidProgressHUD: View {
    @Binding var state: FluidProgressState
    var onViewPortfolio: (() -> Void)?
    
    @State private var progress: CGFloat = 0.0
    @State private var timer: Timer?
    @State private var isSuccessForm = false
    @State private var isErrorForm = false
    @State private var containerScale: CGFloat = 1.0
    
    // 呼吸灯光效
    @State private var iconOpacity: Double = 0.8
    @State private var breathingTimer: Timer?
    
    private var iconView: some View {
        ZStack {
            if isSuccessForm {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 24, weight: .medium))
                    .transition(.scale.combined(with: .opacity))
                    .id("successIcon")
            } else if isErrorForm {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 24, weight: .medium))
                    .transition(.scale.combined(with: .opacity))
                    .id("errorIcon")
            } else {
                // 进度图标与环形轨迹
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 3)
                        .frame(width: 28, height: 28)
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(-90))
                    
                    if case .processing(let type, _) = state {
                        Image(systemName: type.iconName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.primary)
                            .opacity(iconOpacity)
                    }
                }
                .transition(.scale.combined(with: .opacity))
                .id("progressIcon")
            }
        }
        .frame(width: 32, height: 32)
    }
    
    // 右侧文案
    private var textView: some View {
        Group {
            if isSuccessForm {
                Text("已保存到相册，点击查看")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .transition(.push(from: .bottom).combined(with: .opacity))
                    .id("successMsg")
            } else if case .error(let msg) = state {
                Text(msg)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
                    .transition(.push(from: .bottom).combined(with: .opacity))
                    .id("errorMsg")
            } else if case .processing(let type, _) = state {
                Text(type.processingText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .transition(.push(from: .bottom).combined(with: .opacity))
                    .id("processMsg")
            }
        }
    }
    
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                iconView
                
                textView
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSuccessForm)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isErrorForm)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background {
                // 毛玻璃材质胶囊
                Capsule()
                    .fill(Color(UIColor.systemBackground).opacity(0.4))
                    .glassEffect(.regular)
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
            }
            .scaleEffect(containerScale)
            .onTapGesture {
                if isSuccessForm {
                    onViewPortfolio?()
                }
            }
        }
        .onChange(of: state) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
        .onAppear {
            handleStateChange(from: .idle, to: state)
        }
        .onDisappear {
            stopAllTimers()
        }
    }
    
    private func handleStateChange(from oldState: FluidProgressState, to newState: FluidProgressState) {
        stopAllTimers()
        
        switch newState {
        case .processing(_, let duration):
            isSuccessForm = false
            isErrorForm = false
            progress = 0.0
            
            // 启动呼吸灯
            breathingTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.8)) {
                    iconOpacity = iconOpacity == 0.8 ? 1.0 : 0.8
                }
            }
            
            // 估算进度（在 duration 时长内涨到 95% 左右）
            let interval = 0.05
            let increment = 0.95 / (duration / interval)
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                if progress < 0.95 {
                    withAnimation(.linear(duration: interval)) {
                        progress += increment
                    }
                }
            }
            
        case .success:
            // 平滑步进至 100%
            withAnimation(.easeOut(duration: 0.2)) {
                progress = 1.0
            }
            
            // 延迟一点点触发形变，让用户看到 100% 的满圆效果
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    isSuccessForm = true
                }
                
                // 容器弹性放大再弹回
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    containerScale = 1.05
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        containerScale = 1.0
                    }
                }
                
                // 3 秒后自动消失
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                    if self.state == .success {
                        withAnimation(.easeIn(duration: 0.3)) {
                            self.state = .idle
                        }
                    }
                }
            }
            
        case .error:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                isErrorForm = true
            }
            
            // Shake 动画
            withAnimation(.spring(response: 0.2, dampingFraction: 0.2)) {
                containerScale = 1.02
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.2)) {
                    containerScale = 1.0
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                if case .error = self.state {
                    withAnimation(.easeIn(duration: 0.3)) {
                        self.state = .idle
                    }
                }
            }
            
        case .idle:
            isSuccessForm = false
            isErrorForm = false
            progress = 0.0
            containerScale = 1.0
        }
    }
    
    private func stopAllTimers() {
        timer?.invalidate()
        timer = nil
        breathingTimer?.invalidate()
        breathingTimer = nil
        iconOpacity = 0.8
    }

}
