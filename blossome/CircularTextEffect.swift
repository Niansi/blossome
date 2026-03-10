//
//  CircularTextEffect.swift
//  blossome
//

import SwiftUI

struct CircularTextEffect: View {
    var text: String = "blossome blossome "
    var radius: CGFloat = 40
    var font: Font = .custom("SourceCodePro-Light", size: 10)
    /// Using primary makes it adapt to light/dark mode naturally
    var textColor: Color = .primary
    var textOpacity: Double = 1.0
    var animationDuration: Double = 15.0

    @State private var isAnimating: Bool = false
    
    private var characters: [String] {
        text.map(String.init)
    }
    
    var body: some View {
        ZStack {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, char in
                let angle = Angle(degrees: Double(index) / Double(characters.count) * 360)
                
                Text(char)
                    .font(font)
                    .foregroundStyle(textColor.opacity(textOpacity))
                    // Move the character up by radius
                    .offset(y: -radius)
                    // Rotate the offset character around the center
                    .rotationEffect(angle)
            }
        }
        // Form a bounding box that encapsulates the rotated text based on radius, to prevent layout compression elsewhere
        .frame(width: radius * 2, height: radius * 2)
        // Continuous rotation for the entire group
        .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
        .onAppear {
            withAnimation(.linear(duration: animationDuration).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

#Preview {
    VStack(spacing: 100) {
        // Light mode
        ZStack {
            Color.white
            CircularTextEffect(textColor: .black)
        }
        .frame(height: 150)
        
        // Dark mode
        ZStack {
            Color.black
            CircularTextEffect(textColor: .white)
        }
        .frame(height: 150)
    }
}
