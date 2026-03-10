//
//  blossomeApp.swift
//  blossome
//
//  Created by 武翔宇 on 2026/3/2.
//

import SwiftUI

@main
struct blossomeApp: App {
    @StateObject private var portfolioStore = PortfolioStore.shared
    @StateObject private var fragmentStore = FragmentStore.shared

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .bottomLeading) {
                FragmentListView()
                    .environmentObject(portfolioStore)
                    .environmentObject(fragmentStore)
                
                // 全局水印
                CircularTextEffect(
                    text: "blossome blossome blossome ",
                    radius: 140,
                    font: .custom("SourceCodePro-Light", size: 24),
                    textColor: .primary,
                    textOpacity: 0.12
                )
                .allowsHitTesting(false)
                .padding(.leading, -120)
                .padding(.bottom, -100)
                .ignoresSafeArea()
            }
        }
    }
}
