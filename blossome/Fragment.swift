//
//  Fragment.swift
//  blossome
//

import Foundation

struct Fragment: Identifiable, Codable {
    let id: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date

    init(content: String = "") {
        self.id = UUID()
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// 用于列表预览的标题（首行或截取前 30 字符）
    var previewTitle: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "新碎片" }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        if firstLine.count > 30 {
            return String(firstLine.prefix(30)) + "..."
        }
        return firstLine
    }

    /// 用于列表预览的摘要（去掉首行后的剩余内容）
    var previewBody: String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { return nil }
        let body = lines.dropFirst().joined(separator: " ")
        if body.count > 60 {
            return String(body.prefix(60)) + "..."
        }
        return body
    }
}
