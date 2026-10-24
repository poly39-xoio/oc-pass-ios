import Foundation

/// 極簡追蹤:把關鍵步驟寫到 Documents/trace.log,閃退後重開可在設定頁看到
enum Trace {
    private static let url: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("trace.log")
    }()

    static func mark(_ tag: String) {
        let line = "\(Int(Date().timeIntervalSince1970)).\(String(format: "%03d", Int(Date().timeIntervalSince1970 * 1000) % 1000)) \(tag)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            if let d = line.data(using: .utf8) { h.write(d) }
            try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func tail(_ lines: Int = 40) -> String {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return "(no trace)" }
        let arr = s.split(separator: "\n")
        return arr.suffix(lines).joined(separator: "\n")
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }
}
