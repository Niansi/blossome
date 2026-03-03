//
//  PortfolioItem.swift
//  blossome
//

import Foundation

enum PortfolioItemType: String, Codable {
    case video
    case livePhoto
}

struct PortfolioItem: Identifiable, Codable {
    let id: UUID
    let type: PortfolioItemType
    let fileName: String
    let thumbnailFileName: String
    let createdAt: Date
    let effectName: String

    init(type: PortfolioItemType, fileName: String, thumbnailFileName: String, effectName: String) {
        self.id = UUID()
        self.type = type
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
        self.createdAt = Date()
        self.effectName = effectName
    }
}
