import Foundation
import Darwin

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

    static var rssMB: Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.resident_size / 1024 / 1024) : -1
    }

    static func tail(_ lines: Int = 40) -> String {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return "(no trace)" }
        let arr = s.split(separator: "\n")
        return arr.suffix(lines).joined(separator: "\n")
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }

    // MARK: - 崩潰攔截(把 call stack 寫檔,下次開 App 可查看)

    private static var crashURL: URL { url.deletingLastPathComponent().appendingPathComponent("crash.log") }

    static func installCrashHandler() {
        NSSetUncaughtExceptionHandler { ex in
            let text = "UNCAUGHT \(ex.name.rawValue): \(ex.reason ?? "")\n" + Thread.callStackSymbols.joined(separator: "\n")
            Trace.writeCrash(text)
        }
        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            signal(sig, ocCrashSignalHandler)
        }
    }

    static func writeCrash(_ text: String) {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? text.write(to: base.appendingPathComponent("crash.log"), atomically: true, encoding: .utf8)
    }

    static func fullDump() -> String {
        let c = crashTail(20)
        let head = (c == "(no crash log)") ? "crash.log: none" : "crash.log: present\n" + c
        return head + "\n--- image ---\n" + important(30) + "\n--- tail ---\n" + tail(25)
    }

    /// 只挑圖片/載入/合併相關的行,避免被後面的 watch.tick 洗掉
    static func important(_ lines: Int = 30) -> String {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return "(no trace)" }
        let keys = ["img", "load.", "merge.", "send.slimmed", "send.appended"]
        let picked = s.split(separator: "\n").filter { line in keys.contains { line.contains($0) } }
        return picked.suffix(lines).joined(separator: "\n")
    }

    static func crashTail(_ lines: Int = 40) -> String {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let f = base.appendingPathComponent("crash.log")
        guard let s = try? String(contentsOf: f, encoding: .utf8) else { return "(no crash log)" }
        return s.split(separator: "\n").suffix(lines).joined(separator: "\n")
    }
}


/// C 函式指標形式的 signal handler:只能呼叫全域函式
private func ocCrashSignalHandler(_ sig: Int32) {
    let stack = Thread.callStackSymbols.joined(separator: "\n")
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
    try? ("SIGNAL \(sig)\n" + stack).write(to: base.appendingPathComponent("crash.log"), atomically: true, encoding: .utf8)
    signal(sig, SIG_DFL)
    raise(sig)
}
