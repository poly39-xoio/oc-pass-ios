import Foundation
import SwiftUI

/// 把訊息裡的網址轉成可點擊的連結（點一下用系統瀏覽器開啟）
enum Linkified {
    static func attributed(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return out }

        let ns = text as NSString
        detector.enumerateMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: ns.length)
        ) { match, _, _ in
            guard let match = match,
                  let url = match.url,
                  let swiftRange = Range(match.range, in: text),
                  let attrRange = Range(swiftRange, in: out) else { return }
            out[attrRange].link = url
        }
        return out
    }
}
