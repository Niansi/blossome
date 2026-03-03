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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(portfolioStore)
        }
    }
}
