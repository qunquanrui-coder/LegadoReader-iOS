import Foundation

/// Shared chapter text formatter & chapter-title matcher.
/// Used by both `ReaderView` and the detached background TTS engine so that
/// paragraph indices are always identical between the two.
public enum ChapterTextFormatter {
    
    /// Splits raw chapter content into clean, distinct paragraphs with purification & Chinese conversion applied
    public static func paragraphs(from content: String, config: ReaderConfig) -> [String] {
        guard !content.isEmpty else { return [] }
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{3000}\u{3000}", with: "\n")
            .replacingOccurrences(of: "\u{00A0}\u{00A0}", with: "\n")
        
        let customRules = config.effectivePurifyRules
        let converter = config.effectiveChineseConversion
        
        var rawList = normalized
            .components(separatedBy: .newlines)
            .map { line -> String in
                var cleaned = line
                    .replacingOccurrences(of: "\u{3000}", with: " ")
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                for rule in customRules where !rule.isEmpty {
                    cleaned = cleaned.replacingOccurrences(of: rule, with: "")
                }
                return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        
        if rawList.count <= 3 && content.count > 250 {
            var smartSplit: [String] = []
            for block in rawList {
                let withDialogueBreaks = block.replacingOccurrences(
                    of: "([。！？…][”」』】])",
                    with: "$1\n",
                    options: .regularExpression
                )
                for sub in withDialogueBreaks.components(separatedBy: .newlines) {
                    let s = sub.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !s.isEmpty else { continue }
                    if s.count > 160 {
                        let sentences = s.replacingOccurrences(of: "([。！？])(?=[^”」』】])", with: "$1\n", options: .regularExpression)
                            .components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        var buffer = ""
                        for sent in sentences {
                            buffer += sent
                            if buffer.count >= 85 {
                                smartSplit.append(buffer)
                                buffer = ""
                            }
                        }
                        if !buffer.isEmpty { smartSplit.append(buffer) }
                    } else {
                        smartSplit.append(s)
                    }
                }
            }
            if smartSplit.count > rawList.count {
                rawList = smartSplit
            }
        }
        
        return rawList.map { "　　" + converter.convert($0) }
    }
    
    // MARK: - Chapter Title Matching (used after switching book source)
    
    /// Removes whitespace & punctuation so "第315章 逃" / "第315章：逃" / "第 315 章  逃" compare equal
    public static func normalizeTitle(_ title: String) -> String {
        let scalars = title.lowercased().unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) &&
            !CharacterSet.punctuationCharacters.contains($0) &&
            !CharacterSet.symbols.contains($0)
        }
        return String(String.UnicodeScalarView(scalars))
    }
    
    /// Extracts the chapter name after "第X章" (e.g. "第315章 逃" -> "逃")
    public static func chapterNamePart(_ title: String) -> String {
        if let range = title.range(of: "第[0-9零〇一二两三四五六七八九十百千万]+[章节回卷]", options: .regularExpression) {
            return normalizeTitle(String(title[range.upperBound...]))
        }
        return normalizeTitle(title)
    }
    
    /// Extracts the raw chapter number token (e.g. "第315章 逃" -> "315")
    public static func chapterNumberToken(_ title: String) -> String? {
        guard let range = title.range(of: "第[0-9零〇一二两三四五六七八九十百千万]+[章节回卷]", options: .regularExpression) else {
            return nil
        }
        let token = String(title[range]).dropFirst().dropLast()
        return token.isEmpty ? nil : String(token)
    }
    
    /// Finds the chapter in `chapters` that best matches `title`, preferring the candidate closest to `nearIndex`
    public static func bestMatchIndex(title: String, in chapters: [Chapter], nearIndex: Int) -> Int? {
        guard !chapters.isEmpty else { return nil }
        let target = normalizeTitle(title)
        guard !target.isEmpty else { return nil }
        
        func closest(_ indices: [Int]) -> Int? {
            indices.min(by: { abs($0 - nearIndex) < abs($1 - nearIndex) })
        }
        
        // 1. Exact normalized title match
        let exact = chapters.filter { normalizeTitle($0.title) == target }.map { $0.index }
        if let hit = closest(exact) { return hit }
        
        // 2. Same chapter number + same chapter name
        let targetName = chapterNamePart(title)
        let targetNum = chapterNumberToken(title)
        if let num = targetNum {
            let byNum = chapters.filter { chapterNumberToken($0.title) == num }
            let byNumAndName = byNum.filter { !targetName.isEmpty && chapterNamePart($0.title) == targetName }.map { $0.index }
            if let hit = closest(byNumAndName) { return hit }
            if let hit = closest(byNum.map { $0.index }) { return hit }
        }
        
        // 3. Same chapter name only (handles "第三百一十五章 逃" vs "第315章 逃")
        if targetName.count >= 2 {
            let byName = chapters.filter { chapterNamePart($0.title) == targetName }.map { $0.index }
            if let hit = closest(byName) { return hit }
        }
        
        return nil
    }
}
