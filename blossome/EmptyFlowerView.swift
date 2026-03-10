import SwiftUI

struct FlowerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / 278.0
        let scaleY = rect.height / 251.0
        
        path.move(to: CGPoint(x: 133.658 * scaleX, y: 0.054052 * scaleY))
        path.addCurve(to: CGPoint(x: 182.353 * scaleX, y: 80.8751 * scaleY), control1: CGPoint(x: 187.313 * scaleX, y: 3.19226 * scaleY), control2: CGPoint(x: 188.846 * scaleX, y: 58.2466 * scaleY))
        path.addCurve(to: CGPoint(x: 276.494 * scaleX, y: 106.739 * scaleY), control1: CGPoint(x: 247.274 * scaleX, y: 60.181 * scaleY), control2: CGPoint(x: 272.159 * scaleX, y: 89.5034 * scaleY))
        path.addCurve(to: CGPoint(x: 224.553 * scaleX, y: 161.703 * scaleY), control1: CGPoint(x: 284.278 * scaleX, y: 148.12 * scaleY), control2: CGPoint(x: 245.109 * scaleX, y: 160.625 * scaleY))
        path.addCurve(to: CGPoint(x: 231.047 * scaleX, y: 245.76 * scaleY), control1: CGPoint(x: 266.102 * scaleX, y: 213.424 * scaleY), control2: CGPoint(x: 246.198 * scaleX, y: 239.289 * scaleY))
        path.addCurve(to: CGPoint(x: 149.892 * scaleX, y: 206.96 * scaleY), control1: CGPoint(x: 184.302 * scaleX, y: 258.688 * scaleY), control2: CGPoint(x: 157.468 * scaleX, y: 225.281 * scaleY))
        path.addCurve(to: CGPoint(x: 78.4774 * scaleX, y: 248.988 * scaleY), control1: CGPoint(x: 129.114 * scaleX, y: 250.93 * scaleY), control2: CGPoint(x: 93.6289 * scaleX, y: 253.303 * scaleY))
        path.addCurve(to: CGPoint(x: 68.7372 * scaleX, y: 168.167 * scaleY), control1: CGPoint(x: 34.3272 * scaleX, y: 236.06 * scaleY), control2: CGPoint(x: 53.5926 * scaleX, y: 189.717 * scaleY))
        path.addCurve(to: CGPoint(x: 0.569294 * scaleX, y: 113.21 * scaleY), control1: CGPoint(x: 6.41067 * scaleX, y: 157.82 * scaleY), control2: CGPoint(x: -2.67746 * scaleX, y: 127.218 * scaleY))
        path.addCurve(to: CGPoint(x: 91.4575 * scaleX, y: 80.8751 * scaleY), control1: CGPoint(x: 10.9547 * scaleX, y: 61.4822 * scaleY), control2: CGPoint(x: 65.4904 * scaleX, y: 70.1036 * scaleY))
        path.addCurve(to: CGPoint(x: 133.658 * scaleX, y: 0.054052 * scaleY), control1: CGPoint(x: 81.0721 * scaleX, y: 13.6298 * scaleY), control2: CGPoint(x: 115.267 * scaleX, y: -1.02449 * scaleY))
        path.closeSubpath()
        return path
    }
}

struct EmptyFlowerView: View {
    let title: String
    
    @State private var isAnimating: Bool = false
    
    var body: some View {
        GeometryReader { proxy in
            let screenCenter = CGPoint(
                x: proxy.size.width / 2,
                y: proxy.size.height / 2
            )
            VStack(spacing: 24) {
                FlowerShape()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [4, 4]))
                    .foregroundColor(.secondary)
                    .frame(width: 80, height: 72)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                            isAnimating = true
                        }
                    }
                
                Text(title)
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .position(x: screenCenter.x, y: screenCenter.y)
        }
        .ignoresSafeArea()
    }
}
