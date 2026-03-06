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
    let livePhotoImageFileName: String?
    let livePhotoVideoFileName: String?

    init(type: PortfolioItemType, fileName: String, thumbnailFileName: String, effectName: String, livePhotoImageFileName: String? = nil, livePhotoVideoFileName: String? = nil) {
        self.id = UUID()
        self.type = type
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
        self.createdAt = Date()
        self.effectName = effectName
        self.livePhotoImageFileName = livePhotoImageFileName
        self.livePhotoVideoFileName = livePhotoVideoFileName
    }
}
