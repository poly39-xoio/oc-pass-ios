import Foundation

/// 已送出圖片的獨立紀錄(不依賴 transcript),確保更新/清快取後圖片仍能還原
struct SentImageRecord: Codable {
    let id: UUID
    let session: String
    let paths: [String]
    let date: Date
    let text: String
}

enum ImageJournal {
    private static var file: URL? {
        guard let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("sent-images.json")
    }

    /// 從舊位置(Application Support)搬到 Documents,並把檔案一起搬
    static func migrateIfNeeded() {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let oldDir = base.appendingPathComponent("Attachments", isDirectory: true)
        guard let newBase = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let newDir = newBase.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        if let items = try? FileManager.default.contentsOfDirectory(at: oldDir, includingPropertiesForKeys: nil) {
            for src in items {
                let dst = newDir.appendingPathComponent(src.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dst.path) {
                    try? FileManager.default.copyItem(at: src, to: dst)
                }
            }
        }
        let oldJournal = base.appendingPathComponent("sent-images.json")
        let newJournal = newBase.appendingPathComponent("sent-images.json")
        if !FileManager.default.fileExists(atPath: newJournal.path),
           FileManager.default.fileExists(atPath: oldJournal.path) {
            try? FileManager.default.copyItem(at: oldJournal, to: newJournal)
        }
    }

    static func all() -> [SentImageRecord] {
        guard let f = file, let d = try? Data(contentsOf: f),
              let list = try? JSONDecoder().decode([SentImageRecord].self, from: d) else { return [] }
        return list
    }

    static func add(id: UUID, session: String, paths: [String], text: String, date: Date) {
        guard let f = file, !paths.isEmpty else { return }
        var list = all().filter { $0.id != id }
        list.append(SentImageRecord(id: id, session: session, paths: paths, date: date, text: text))
        if let d = try? JSONEncoder().encode(list) { try? d.write(to: f, options: .atomic) }
    }

    static func remove(id: UUID) {
        guard let f = file else { return }
        let list = all().filter { $0.id != id }
        if let d = try? JSONEncoder().encode(list) { try? d.write(to: f, options: .atomic) }
    }

    /// 把日誌裡的圖片接回訊息列表(缺的補回、有的補路徑)
    static func apply(to messages: inout [ChatMessage], session: String) {
        let recs = all().filter { $0.session == session && $0.paths.contains { FileManager.default.fileExists(atPath: $0) } }
        guard !recs.isEmpty else { return }
        for r in recs {
            if let i = messages.firstIndex(where: { $0.id == r.id }) {
                messages[i].imagePaths = r.paths
            } else {
                var m = ChatMessage(role: .user, text: r.text, createdAt: r.date)
                m.id = r.id
                m.imagePaths = r.paths
                let idx = messages.firstIndex(where: { $0.createdAt > r.date }) ?? messages.count
                messages.insert(m, at: idx)
            }
        }
    }
}

// persistence experiment build
