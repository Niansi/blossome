//
//  LiquidGlassButtonStyle.swift
//  blossome
//
//  Created by 武翔宇 on 2026/3/3.
//

import SwiftUI

struct LiquidGlassButtonStyle: ButtonStyle {
    var backgroundColor: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .glassEffect(backgroundColor.map { .regular.tint($0) } ?? .regular)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static func liquidGlass(backgroundColor: Color? = nil) -> Self {
        LiquidGlassButtonStyle(backgroundColor: backgroundColor)
    }
}
