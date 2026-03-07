//
//  FragmentStore.swift
//  blossome
//

import Foundation
import Combine

class FragmentStore: ObservableObject {
    static let shared = FragmentStore()

    @Published var fragments: [Fragment] = []

    private let storeDir: URL
    private let manifestURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeDir = docs.appendingPathComponent("Fragments", isDirectory: true)
        manifestURL = storeDir.appendingPathComponent("fragments.json")

        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        loadManifest()
    }

    // MARK: - Public

    /// 创建一条新碎片并返回
    @discardableResult
    func create(content: String = "") -> Fragment {
        let fragment = Fragment(content: content)
        fragments.insert(fragment, at: 0)
        saveManifest()
        return fragment
    }

    /// 更新碎片内容
    func update(id: UUID, content: String) {
        guard let index = fragments.firstIndex(where: { $0.id == id }) else { return }
        // 内容没有变化时不更新时间和排序
        guard fragments[index].content != content else { return }
        fragments[index].content = content
        fragments[index].updatedAt = Date()
        // 重新排序（最新编辑的排最前）
        let updated = fragments[index]
        fragments.remove(at: index)
        fragments.insert(updated, at: 0)
        saveManifest()
    }

    /// 删除碎片
    func delete(id: UUID) {
        fragments.removeAll { $0.id == id }
        saveManifest()
    }

    /// 根据 ID 获取碎片
    func fragment(by id: UUID) -> Fragment? {
        fragments.first { $0.id == id }
    }

    // MARK: - Private

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([Fragment].self, from: data) else {
            return
        }
        // 按 updatedAt 倒序
        fragments = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(fragments) else { return }
        try? data.write(to: manifestURL)
    }
}
