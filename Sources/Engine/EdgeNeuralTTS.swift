import Foundation

public enum NeuralVoiceActor: String, CaseIterable, Codable, Identifiable {
    public var id: String { rawValue }
    case yunxi = "zh-CN-YunxiNeural"
    case yunxia = "zh-CN-YunxiaNeural"
    case xiaoxiao = "zh-CN-XiaoxiaoNeural"
    case xiaoyi = "zh-CN-XiaoyiNeural"
    case yunjian = "zh-CN-YunjianNeural"
    case yunyang = "zh-CN-YunyangNeural"
    case xiaobei = "zh-CN-liaoning-XiaobeiNeural"
    case xiaoni = "zh-CN-shaanxi-XiaoniNeural"
    case hsiaochen = "zh-TW-HsiaoChenNeural"
    case yunjhe = "zh-TW-YunJheNeural"
    
    public var displayName: String {
        switch self {
        case .yunxi: return "云希 · 阳光少年音 (荐)"
        case .yunxia: return "云夏 · 热血动漫少年 (高情感)"
        case .xiaoxiao: return "晓晓 · 温柔知性女声"
        case .xiaoyi: return "晓伊 · 灵动甜美少女"
        case .yunjian: return "云健 · 浑厚武侠评书"
        case .yunyang: return "云扬 · 沉稳旁白男声"
        case .xiaobei: return "晓北 · 东北幽默女声"
        case .xiaoni: return "晓妮 · 陕西爽朗女声"
        case .hsiaochen: return "晓臻 · 温柔台湾女声"
        case .yunjhe: return "云哲 · 温润台湾男声"
        }
    }
    
    public var shortName: String {
        switch self {
        case .yunxi: return "云希(男)"
        case .yunxia: return "云夏(燃系)"
        case .xiaoxiao: return "晓晓(女)"
        case .xiaoyi: return "晓伊(甜美)"
        case .yunjian: return "云健(评书)"
        case .yunyang: return "云扬(旁白)"
        case .xiaobei: return "晓北(东北)"
        case .xiaoni: return "晓妮(陕西)"
        case .hsiaochen: return "晓臻(台女)"
        case .yunjhe: return "云哲(台男)"
        }
    }

    public var isFemale: Bool {
        switch self {
        case .xiaoxiao, .xiaoyi, .xiaobei, .xiaoni, .hsiaochen:
            return true
        case .yunxi, .yunxia, .yunjian, .yunyang, .yunjhe:
            return false
        }
    }

    public var xmlLang: String {
        switch self {
        case .hsiaochen, .yunjhe:
            return "zh-TW"
        default:
            return "zh-CN"
        }
    }
}

public enum SpeechExpressiveStyle: String, CaseIterable, Codable, Identifiable {
    public var id: String { rawValue }
    case multiRoleDrama = "drama"
    case emotionalSingleVoice = "emotional"
    case flat = "flat"

    public var displayName: String {
        switch self {
        case .multiRoleDrama:
            return "多角色剧场 · 旁白+男女对话 (荐)"
        case .emotionalSingleVoice:
            return "单人情感演绎 · 抑扬顿挫"
        case .flat:
            return "平稳标准播读"
        }
    }

    public var shortName: String {
        switch self {
        case .multiRoleDrama:
            return "剧场分角"
        case .emotionalSingleVoice:
            return "情感演绎"
        case .flat:
            return "标准平稳"
        }
    }
}

public enum NovelClauseEmotion: String, Equatable {
    case neutral
    case excitedOrAngry
    case questioning
    case somberOrWhisper
    case coldOrSolemn
    case joyfulOrWarm
}

public enum NovelSpeechRole: Equatable {
    case narration
    case maleDialogue
    case femaleDialogue

    public var isDialogue: Bool {
        self != .narration
    }
}

public struct DramaVoiceCast: Equatable {
    public let narrator: NeuralVoiceActor
    public let maleDialogue: NeuralVoiceActor
    public let femaleDialogue: NeuralVoiceActor

    public static func resolve(primary: NeuralVoiceActor) -> DramaVoiceCast {
        switch primary {
        case .yunxi:
            return DramaVoiceCast(narrator: .yunjian, maleDialogue: .yunxi, femaleDialogue: .xiaoxiao)
        case .yunxia:
            return DramaVoiceCast(narrator: .yunjian, maleDialogue: .yunxia, femaleDialogue: .xiaoyi)
        case .yunjian:
            return DramaVoiceCast(narrator: .yunjian, maleDialogue: .yunxi, femaleDialogue: .xiaoxiao)
        case .yunyang:
            return DramaVoiceCast(narrator: .yunyang, maleDialogue: .yunxi, femaleDialogue: .xiaoxiao)
        case .xiaoxiao:
            return DramaVoiceCast(narrator: .xiaoxiao, maleDialogue: .yunxi, femaleDialogue: .xiaoyi)
        case .xiaoyi:
            return DramaVoiceCast(narrator: .xiaoxiao, maleDialogue: .yunxi, femaleDialogue: .xiaoyi)
        case .xiaobei:
            return DramaVoiceCast(narrator: .xiaobei, maleDialogue: .yunxi, femaleDialogue: .xiaoyi)
        case .xiaoni:
            return DramaVoiceCast(narrator: .xiaoni, maleDialogue: .yunxi, femaleDialogue: .xiaoxiao)
        case .hsiaochen:
            return DramaVoiceCast(narrator: .hsiaochen, maleDialogue: .yunjhe, femaleDialogue: .xiaoyi)
        case .yunjhe:
            return DramaVoiceCast(narrator: .yunjhe, maleDialogue: .yunxi, femaleDialogue: .hsiaochen)
        }
    }
}

public struct ExpressiveProsodySegment: Equatable {
    public let text: String
    public let role: NovelSpeechRole
    public let emotion: NovelClauseEmotion
    public let pitchHz: Int
    public let rateDeltaPercent: Int
    public let volumeDeltaPercent: Int
}

public struct ExpressiveVoiceTurn: Equatable {
    public let voice: NeuralVoiceActor
    public let segments: [ExpressiveProsodySegment]

    public func buildSSML(baseRateMultiplier: Float) -> String {
        let baseRatePercent = Int(round((baseRateMultiplier - 1.0) * 100.0))
        let body = segments.map { segment -> String in
            let pitch = max(-15, min(15, segment.pitchHz))
            let rate = max(-45, min(75, baseRatePercent + segment.rateDeltaPercent))
            let volume = max(-25, min(25, segment.volumeDeltaPercent))
            let pitchStr = pitch >= 0 ? "+\(pitch)Hz" : "\(pitch)Hz"
            let rateStr = rate >= 0 ? "+\(rate)%" : "\(rate)%"
            let volStr = volume >= 0 ? "+\(volume)%" : "\(volume)%"
            let escaped = Self.escapeXML(segment.text)
            return "<prosody pitch='\(pitchStr)' rate='\(rateStr)' volume='\(volStr)'>\(escaped)</prosody>"
        }.joined()
        return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='\(voice.xmlLang)'><voice name='\(voice.rawValue)'>\(body)</voice></speak>"
    }

    public static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

public enum NovelEmotionAnalyzer {
    private static let femaleCues: [String] = [
        "她", "少女", "女子", "姑娘", "小姐", "夫人", "娘子", "妇人", "老妇", "婆婆",
        "姐姐", "妹妹", "师姐", "师妹", "公主", "王妃", "仙子", "丫鬟", "侍女",
        "红唇", "美眸", "蹙眉", "轻咬", "娇嗔", "柔声", "娇声", "咯咯", "小女子",
        "本姑娘", "本宫", "妾身", "老身"
    ]

    private static let maleCues: [String] = [
        "他", "少年", "青年", "老者", "老头", "大汉", "壮汉", "汉子", "男子", "男人",
        "公子", "先生", "师兄", "师弟", "老夫", "在下", "老祖", "本座", "小爷",
        "老子", "朕", "胡须", "朗声", "洪声", "粗声", "瓮声"
    ]

    private static let excitedOrAngryCues: [String] = [
        "怒", "喝道", "咆哮", "嘶吼", "大吼", "大喊", "暴喝", "厉喝", "厉声", "尖叫",
        "惊呼", "骇然", "失声", "滚", "找死", "该死", "可恶", "休想", "杀", "轰", "破开"
    ]

    private static let somberOrWhisperCues: [String] = [
        "低声", "轻声", "喃喃", "叹息", "叹了口气", "叹道", "长叹", "苦笑", "凄然",
        "哽咽", "颤声", "抽泣", "流泪", "悲痛", "悲伤", "幽幽", "微不可察", "耳语",
        "沙哑", "嘶哑", "低沉", "垂眸", "黯然", "沉默"
    ]

    private static let coldOrSolemnCues: [String] = [
        "冷笑", "冷哼", "寒声", "冷冷", "漠然", "沉声", "淡淡", "面无表情", "森然",
        "杀意", "冰冷", "威严", "不容置疑"
    ]

    private static let joyfulOrWarmCues: [String] = [
        "笑道", "微笑", "轻笑", "大笑", "哈哈", "呵呵", "莞尔", "笑眯眯", "欣喜",
        "狂喜", "惊喜", "温柔", "柔声", "甜笑", "笑吟吟"
    ]

    private static let questioningCues: [String] = [
        "难道", "莫非", "怎么可能", "为何", "为什么", "岂有此理", "是谁", "当真", "究竟"
    ]

    public static func detectDialogueRole(
        quoteText: String,
        precedingNarration: String,
        followingNarration: String,
        defaultVoice: NeuralVoiceActor
    ) -> NovelSpeechRole {
        let selfFemale = ["小女子", "本姑娘", "本宫", "妾身", "老身", "人家"]
        let selfMale = ["老夫", "在下", "小爷", "本座", "老子", "朕", "小生"]
        if selfFemale.contains(where: { quoteText.contains($0) }) { return .femaleDialogue }
        if selfMale.contains(where: { quoteText.contains($0) }) { return .maleDialogue }

        let preWindow = String(precedingNarration.suffix(34))
        let postWindow = String(followingNarration.prefix(24))

        let preFemaleScore = score(text: preWindow, cues: femaleCues,preferSuffix: true)
        let preMaleScore = score(text: preWindow, cues: maleCues, preferSuffix: true)
        if preFemaleScore != preMaleScore {
            return preFemaleScore > preMaleScore ? .femaleDialogue : .maleDialogue
        }

        let postFemaleScore = score(text: postWindow, cues: femaleCues, preferSuffix: false)
        let postMaleScore = score(text: postWindow, cues: maleCues, preferSuffix: false)
        if postFemaleScore != postMaleScore {
            return postFemaleScore > postMaleScore ? .femaleDialogue : .maleDialogue
        }

        return defaultVoice.isFemale ? .femaleDialogue : .maleDialogue
    }

    private static func score(text: String, cues: [String], preferSuffix: Bool) -> Int {
        guard !text.isEmpty else { return 0 }
        var total = 0
        for cue in cues where text.contains(cue) {
            total += cue.count >= 2 ? 3 : 2
            if preferSuffix, let range = text.range(of: cue, options: .backwards) {
                let distance = text.distance(from: range.upperBound, to: text.endIndex)
                if distance <= 10 { total += 3 }
            } else if !preferSuffix, let range = text.range(of: cue) {
                let distance = text.distance(from: text.startIndex, to: range.lowerBound)
                if distance <= 10 { total += 3 }
            }
        }
        return total
    }

    public static func detectEmotion(clause: String, attributionContext: String = "") -> NovelClauseEmotion {
        let trimmed = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .neutral }
        let contextWindow = String(attributionContext.suffix(24))

        let hasEllipsis = trimmed.contains("……") || trimmed.contains("...") || trimmed.contains("…")
        let endsWithQuestion = trimmed.hasSuffix("？") || trimmed.hasSuffix("?") || trimmed.hasSuffix("？”") || trimmed.hasSuffix("?”") || trimmed.hasSuffix("？」")
        let endsWithExclamation = trimmed.hasSuffix("！") || trimmed.hasSuffix("!") || trimmed.hasSuffix("！”") || trimmed.hasSuffix("!”") || trimmed.hasSuffix("！」")

        if somberOrWhisperCues.contains(where: { trimmed.contains($0) || contextWindow.contains($0) }) {
            return .somberOrWhisper
        }
        if coldOrSolemnCues.contains(where: { trimmed.contains($0) || contextWindow.contains($0) }) {
            return .coldOrSolemn
        }
        if excitedOrAngryCues.contains(where: { trimmed.contains($0) || contextWindow.contains($0) }) {
            return .excitedOrAngry
        }
        if endsWithQuestion || questioningCues.contains(where: { trimmed.contains($0) }) {
            return .questioning
        }
        if joyfulOrWarmCues.contains(where: { trimmed.contains($0) || contextWindow.contains($0) }) {
            return .joyfulOrWarm
        }
        if endsWithExclamation {
            return .excitedOrAngry
        }
        if hasEllipsis {
            return .somberOrWhisper
        }
        return .neutral
    }

    public static func prosodySegment(text: String, role: NovelSpeechRole, emotion: NovelClauseEmotion) -> ExpressiveProsodySegment {
        let basePitch = role.isDialogue ? 3 : -1
        let baseRate = role.isDialogue ? 2 : 0
        let baseVol = role.isDialogue ? 4 : 0

        switch emotion {
        case .neutral:
            return ExpressiveProsodySegment(
                text: text,
                role: role,
                emotion: emotion,
                pitchHz: basePitch,
                rateDeltaPercent: baseRate,
                volumeDeltaPercent: baseVol
            )
        case .excitedOrAngry:
            return ExpressiveProsodySegment(
                text: text,
                role: role,
                emotion: emotion,
                pitchHz: basePitch + 5,
                rateDeltaPercent: baseRate + 7,
                volumeDeltaPercent: baseVol + 10
            )
        case .questioning:
            return ExpressiveProsodySegment(
                text: text,
                role: role,
                emotion: emotion,
                pitchHz: basePitch + 4,
                rateDeltaPercent: baseRate + 2,
                volumeDeltaPercent: baseVol + 4
            )
        case .somberOrWhisper:
            return ExpressiveProsodySegment(
                text: text,
                role: role,
                emotion: emotion,
                pitchHz: (role.isDialogue ? -3 : -5),
                rateDeltaPercent: -8,
                volumeDeltaPercent: -6
            )
        case .coldOrSolemn:
            return ExpressiveProsodySegment(
                text: text,
                role: role,
                emotion: emotion,
                pitchHz: -4,
                rateDeltaPercent: -4,
                volumeDeltaPercent: baseVol + 2
            )
        case .joyfulOrWarm:
            return ExpressiveProsodySegment(
                text: text,
                role: role,
                emotion: emotion,
                pitchHz: basePitch + 3,
                rateDeltaPercent: baseRate + 3,
                volumeDeltaPercent: baseVol + 4
            )
        }
    }
}

public enum ExpressiveSpeechPlanner {
    private struct RawSpan {
        let text: String
        let isQuoted: Bool
    }

    public static func plan(
        paragraph: String,
        primaryVoice: NeuralVoiceActor,
        style: SpeechExpressiveStyle,
        maxTurns: Int = 6
    ) -> [ExpressiveVoiceTurn] {
        let clean = paragraph
            .replacingOccurrences(of: "　", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }

        if style == .flat {
            let seg = ExpressiveProsodySegment(
                text: clean,
                role: .narration,
                emotion: .neutral,
                pitchHz: 0,
                rateDeltaPercent: 0,
                volumeDeltaPercent: 0
            )
            return [ExpressiveVoiceTurn(voice: primaryVoice, segments: [seg])]
        }

        let spans = splitQuotedSpans(clean)
        var segments: [ExpressiveProsodySegment] = []

        for idx in spans.indices {
            let span = spans[idx]
            let prevNarration = idx > 0 && !spans[idx - 1].isQuoted ? spans[idx - 1].text : ""
            let nextNarration = idx + 1 < spans.count && !spans[idx + 1].isQuoted ? spans[idx + 1].text : ""
            let role: NovelSpeechRole
            let attribution: String
            if span.isQuoted {
                role = NovelEmotionAnalyzer.detectDialogueRole(
                    quoteText: span.text,
                    precedingNarration: prevNarration,
                    followingNarration: nextNarration,
                    defaultVoice: primaryVoice
                )
                attribution = prevNarration + " " + nextNarration
            } else {
                role = .narration
                attribution = ""
            }

            let clauses = splitClauses(span.text)
            for clause in clauses {
                let emotion = NovelEmotionAnalyzer.detectEmotion(clause: clause, attributionContext: attribution)
                segments.append(NovelEmotionAnalyzer.prosodySegment(text: clause, role: role, emotion: emotion))
            }
        }

        guard !segments.isEmpty else {
            return [ExpressiveVoiceTurn(voice: primaryVoice, segments: [
                ExpressiveProsodySegment(text: clean, role: .narration, emotion: .neutral, pitchHz: 0, rateDeltaPercent: 0, volumeDeltaPercent: 0)
            ])]
        }

        let cast = DramaVoiceCast.resolve(primary: primaryVoice)
        var turns: [ExpressiveVoiceTurn] = []
        for segment in segments {
            let targetVoice: NeuralVoiceActor
            switch style {
            case .flat, .emotionalSingleVoice:
                targetVoice = primaryVoice
            case .multiRoleDrama:
                switch segment.role {
                case .narration:
                    targetVoice = cast.narrator
                case .maleDialogue:
                    targetVoice = cast.maleDialogue
                case .femaleDialogue:
                    targetVoice = cast.femaleDialogue
                }
            }
            if let last = turns.last, last.voice == targetVoice {
                turns[turns.count - 1] = ExpressiveVoiceTurn(voice: targetVoice, segments: last.segments + [segment])
            } else {
                turns.append(ExpressiveVoiceTurn(voice: targetVoice, segments: [segment]))
            }
        }

        let limit = max(1, maxTurns)
        if turns.count > limit {
            let head = Array(turns.prefix(limit - 1))
            let tailSegments = turns.dropFirst(limit - 1).flatMap(\.segments)
            let tailVoice = turns[limit - 1].voice
            return head + [ExpressiveVoiceTurn(voice: tailVoice, segments: tailSegments)]
        }
        return turns
    }

    private static func splitQuotedSpans(_ text: String) -> [RawSpan] {
        let pairs: [Character: Character] = [
            "“": "”",
            "「": "」",
            "『": "』",
            "\"": "\""
        ]
        var spans: [RawSpan] = []
        var buffer = ""
        var activeClose: Character? = nil

        for ch in text {
            if let close = activeClose {
                buffer.append(ch)
                if ch == close {
                    let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        spans.append(RawSpan(text: trimmed, isQuoted: true))
                    }
                    buffer = ""
                    activeClose = nil
                }
            } else if let expectedClose = pairs[ch] {
                let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    spans.append(RawSpan(text: trimmed, isQuoted: false))
                }
                buffer = String(ch)
                activeClose = expectedClose
            } else {
                buffer.append(ch)
            }
        }

        let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            spans.append(RawSpan(text: remaining, isQuoted: false))
        }
        return spans
    }

    private static func splitClauses(_ text: String) -> [String] {
        let terminators: Set<Character> = ["。", "！", "？", "；", "!", "?", ";"]
        var clauses: [String] = []
        var current = ""

        for ch in text {
            current.append(ch)
            if terminators.contains(ch) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    clauses.append(trimmed)
                }
                current = ""
            }
        }

        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            if tail.allSatisfy({ "”」』\"'）)".contains($0) }), !clauses.isEmpty {
                clauses[clauses.count - 1].append(tail)
            } else {
                clauses.append(tail)
            }
        }
        return clauses.isEmpty ? [text] : clauses
    }
}

public final class EdgeNeuralTTS {
    public static let shared = EdgeNeuralTTS()
    
    private let trustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private let secMsGecVersion = "2-143.0.3650.75"
    private var cachedClockSkew: TimeInterval? = nil
    
    private init() {}
    
    // MARK: - Public Synthesize API (Edge Neural WS -> Baidu Neural HTTP Fallback)
    public func synthesize(
        text: String,
        voice: NeuralVoiceActor,
        rateMultiplier: Float,
        style: SpeechExpressiveStyle = .multiRoleDrama
    ) async throws -> Data {
        let clean = text
            .replacingOccurrences(of: "　", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw NSError(domain: "EdgeNeuralTTS", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty text"])
        }
        
        let turns = ExpressiveSpeechPlanner.plan(paragraph: clean, primaryVoice: voice, style: style)
        if let edgeData = try? await synthesizeViaEdgeWebSocket(turns: turns, rateMultiplier: rateMultiplier),
           edgeData.count > 256 {
            return edgeData
        }

        if style != .flat {
            let flatTurns = ExpressiveSpeechPlanner.plan(paragraph: clean, primaryVoice: voice, style: .flat)
            if let fallbackEdgeData = try? await synthesizeViaEdgeWebSocket(turns: flatTurns, rateMultiplier: rateMultiplier),
               fallbackEdgeData.count > 256 {
                return fallbackEdgeData
            }
        }
        
        // 2. Fallback to Baidu Online Neural TTS HTTP MP3 stream
        if let baiduData = try? await synthesizeViaBaiduHTTP(text: clean, rateMultiplier: rateMultiplier),
           baiduData.count > 256 {
            return baiduData
        }
        
        throw NSError(domain: "EdgeNeuralTTS", code: -2, userInfo: [NSLocalizedDescriptionKey: "Online neural TTS unavailable"])
    }
    
    // MARK: - 1. Microsoft Edge ReadAloud Neural WebSocket
    private func synthesizeViaEdgeWebSocket(turns: [ExpressiveVoiceTurn], rateMultiplier: Float) async throws -> Data {
        guard !turns.isEmpty else {
            throw NSError(domain: "EdgeNeuralTTS", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty turns"])
        }
        let serverTimestamp = await getSyncedUnixTimestamp()
        let gecToken = Self.generateSecMsGecV2(unixTimestamp: serverTimestamp)
        let connId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let muid = UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        
        let urlString = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=\(trustedClientToken)&ConnectionId=\(connId)&Sec-MS-GEC=\(gecToken)&Sec-MS-GEC-Version=\(secMsGecVersion)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("muid=\(muid);", forHTTPHeaderField: "Cookie")
        
        let wsTask = URLSession.shared.webSocketTask(with: request)
        wsTask.resume()
        defer {
            wsTask.cancel(with: .normalClosure, reason: nil)
        }
        
        let timestampStr = Self.jsDateString()
        let configPayload = "X-Timestamp:\(timestampStr)\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"true\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}\r\n"
        try await wsTask.send(.string(configPayload))
        
        var audioBuffer = Data()
        for turn in turns {
            try Task.checkCancellation()
            let ssml = turn.buildSSML(baseRateMultiplier: rateMultiplier)
            let reqId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let ssmlPayload = "X-RequestId:\(reqId)\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:\(timestampStr)Z\r\nPath:ssml\r\n\r\n\(ssml)"
            try await wsTask.send(.string(ssmlPayload))

            while true {
                let message = try await wsTask.receive()
                switch message {
                case .string(let str):
                    if str.contains("Path:turn.end") {
                        break
                    }
                    continue
                case .data(let data):
                    if data.count >= 2 {
                        let headerLen = (Int(data[0]) << 8) | Int(data[1])
                        let audioStart = 2 + headerLen
                        if audioStart < data.count {
                            let headerData = data.subdata(in: 2..<audioStart)
                            if let headerStr = String(data: headerData, encoding: .utf8),
                               headerStr.contains("Path:audio") {
                                audioBuffer.append(data.subdata(in: audioStart..<data.count))
                            }
                        }
                    }
                    continue
                @unknown default:
                    continue
                }
                break
            }
        }
        return audioBuffer
    }
    
    // MARK: - 2. Baidu Online Neural TTS HTTP Fallback
    private func synthesizeViaBaiduHTTP(text: String, rateMultiplier: Float) async throws -> Data {
        let spd = max(3, min(9, Int(round(5.0 * rateMultiplier))))
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://fanyi.baidu.com/gettts?lan=zh&text=\(encoded)&spd=\(spd)&source=web") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        req.setValue("https://fanyi.baidu.com/", forHTTPHeaderField: "Referer")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 200, data.count > 256 {
            return data
        }
        throw URLError(.badServerResponse)
    }
    
    // MARK: - Server Clock Sync (Prevents 403 on Device Clock Skew)
    private func getSyncedUnixTimestamp() async -> TimeInterval {
        if let skew = cachedClockSkew {
            return Date().timeIntervalSince1970 + skew
        }
        guard let url = URL(string: "https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/voices/list?trustedclienttoken=\(trustedClientToken)") else {
            return Date().timeIntervalSince1970
        }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 3.5
        if let (_, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse,
           let dateStr = http.value(forHTTPHeaderField: "Date") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let serverDate = formatter.date(from: dateStr) {
                let skew = serverDate.timeIntervalSince1970 - Date().timeIntervalSince1970
                cachedClockSkew = skew
                return serverDate.timeIntervalSince1970
            }
        }
        return Date().timeIntervalSince1970
    }
    
    private static func jsDateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
        return formatter.string(from: Date())
    }
    
    // MARK: - Sec-MS-GEC v2 Token Generator (Ported from edge-tts drm.py)
    private static let sha256Initial: [UInt32] = [
        0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
        0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
    ]
    private static let sha256State: [UInt32] = [
        0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A,
        0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2
    ]
    private static let sha256Schedule: [UInt32] = [
        0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA,
        0xA622EE8C, 0xD1DD9491, 0xC0DD25A0, 0xF9E70AB6,
        0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33,
        0xD258B060, 0x72766564
    ]
    private static let sha256RoundConstants: [UInt32] = [
        0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
        0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
        0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
        0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
        0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
        0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
    ]
    private static let sha256Adjustment: UInt32 = 0xC9DC06A7
    private static let sha256Sigma0Adjustment: UInt32 = 0x059C0B80
    private static let sha256Sigma1Adjustment: UInt32 = 0x000B92C0
    private static let cs64Coefficients: [(UInt32, UInt32)] = [
        (0xE82E91B1, 0xB32700D0), (0x44DE24C6, 0x88DFF51D),
        (0x3BEB65BC, 0x29514038), (0xC89C5933, 0xB328CBDF),
        (0x8D1EC211, 0xD405B4D5), (0x314EF5D5, 0x26E55F3C),
        (0xE92491B1, 0x607801C6), (0xF0A5B9D5, 0x82B2C1FB),
        (0x06064CF3, 0xFA51A3DA), (0xDA79FA60, 0x207CC464),
        (0xBED20560, 0x3C3C74F3), (0x89F9C9F8, 0xD2D14B61),
        (0x35FA38C6, 0xBB04A2C1), (0xCB49E3C6, 0xC5626167)
    ]
    
    @inline(__always) private static func rol16(_ v: UInt32) -> UInt32 {
        (v << 16) | (v >> 16)
    }
    @inline(__always) private static func rotr(_ v: UInt32, _ n: UInt32) -> UInt32 {
        (v >> n) | (v << (32 - n))
    }
    @inline(__always) private static func sigma0(_ v: UInt32) -> UInt32 {
        rotr(v, 7) ^ rotr(v, 18) ^ (v >> 3)
    }
    @inline(__always) private static func sigma1(_ v: UInt32) -> UInt32 {
        rotr(v, 17) ^ rotr(v, 19) ^ (v >> 10)
    }
    
    private static func sha256Rounds(state: [UInt32], words: [UInt32], firstRound: Int = 0) -> [UInt32] {
        var a = state[0], b = state[1], c = state[2], d = state[3]
        var e = state[4], f = state[5], g = state[6], h = state[7]
        for index in firstRound..<64 {
            let k = (firstRound == 14 && index == 14) ? sha256Adjustment : sha256RoundConstants[index]
            let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
            let ch = g ^ (e & (f ^ g))
            let t1 = h &+ s1 &+ ch &+ k &+ words[index]
            let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
            let maj = (a & b) | (c & (a | b))
            let t2 = s0 &+ maj
            h = g; g = f; f = e; e = d &+ t1
            d = c; c = b; b = a; a = t1 &+ t2
        }
        return [a, b, c, d, e, f, g, h]
    }
    
    private static func expandSchedule(_ words: inout [UInt32], firstWord: Int = 16) {
        for index in firstWord..<64 {
            let s1 = sigma1(words[index - 2])
            let s0 = sigma0(words[index - 15])
            words.append(s1 &+ words[index - 7] &+ s0 &+ words[index - 16])
        }
    }
    
    private static func sha256Init(_ data7: [UInt8]) -> [UInt32] {
        var words = Array(repeating: UInt32(0), count: 14)
        let w14 = (UInt32(data7[0]) << 16) | (UInt32(data7[1]) << 8) | UInt32(data7[2])
        let w15 = (UInt32(data7[3]) << 24) | (UInt32(data7[4]) << 16) | (UInt32(data7[5]) << 8) | UInt32(data7[6])
        words.append(w14)
        words.append(w15)
        for index in 16..<30 {
            var val = sha256Schedule[index - 16]
            if index - 2 >= 14 {
                val = val &+ (index == 16 ? (sigma1(words[index - 2]) ^ sha256Sigma1Adjustment) : sigma1(words[index - 2]))
            }
            if index - 7 >= 14 {
                val = val &+ words[index - 7]
            }
            if index - 15 >= 14 {
                val = val &+ (index == 29 ? (sigma0(words[index - 15]) ^ sha256Sigma0Adjustment) : sigma0(words[index - 15]))
            }
            words.append(val)
        }
        let w30 = sigma1(words[28]) &+ words[23] &+ sigma0(words[15]) &+ words[14] &+ sha256Adjustment &- sha256RoundConstants[14]
        words.append(w30)
        expandSchedule(&words, firstWord: 31)
        let working = sha256Rounds(state: sha256State, words: words, firstRound: 14)
        return zip(sha256Initial, working).map { $0 &+ $1 }
    }
    
    private static func sha256Digest(_ data: [UInt8]) -> [UInt8] {
        let length = 57 + data.count
        var padded = Array(data.dropFirst(7))
        padded.append(0x80)
        let padZeros = ((55 - length) % 64 + 64) % 64
        padded.append(contentsOf: Array(repeating: UInt8(0), count: padZeros))
        let bitLen = UInt64(length) * 8
        for shift in stride(from: 56, through: 0, by: -8) {
            padded.append(UInt8((bitLen >> shift) & 0xFF))
        }
        var state = sha256Init(Array(data.prefix(7)))
        for offset in stride(from: 0, to: padded.count, by: 64) {
            var words: [UInt32] = []
            words.reserveCapacity(64)
            for i in 0..<16 {
                let p = offset + i * 4
                let w = (UInt32(padded[p]) << 24) | (UInt32(padded[p+1]) << 16) | (UInt32(padded[p+2]) << 8) | UInt32(padded[p+3])
                words.append(w)
            }
            expandSchedule(&words)
            let working = sha256Rounds(state: state, words: words)
            state = zip(state, working).map { $0 &+ $1 }
        }
        var out: [UInt8] = []
        for w in state {
            out.append(UInt8((w >> 24) & 0xFF))
            out.append(UInt8((w >> 16) & 0xFF))
            out.append(UInt8((w >> 8) & 0xFF))
            out.append(UInt8(w & 0xFF))
        }
        return out
    }
    
    private static func cs64Digest(data: [UInt8], digest: [UInt8]) -> (UInt32, UInt32) {
        var keyA = UInt32(digest[0]) | (UInt32(digest[1]) << 8) | (UInt32(digest[2]) << 16) | (UInt32(digest[3]) << 24)
        var keyB = UInt32(digest[4]) | (UInt32(digest[5]) << 8) | (UInt32(digest[6]) << 16) | (UInt32(digest[7]) << 24)
        keyA |= 1
        keyB |= 1
        let factor: UInt32 = 0x82893933
        let factors = (keyA &* factor, keyB &* factor)
        var terms: [UInt32] = cs64Coefficients.enumerated().map { idx, pair in
            pair.0 &* (idx % 2 == 0 ? factors.0 : factors.1)
        }
        var offsets: [UInt32] = cs64Coefficients.map { $0.1 }
        
        var prefixed: [UInt8] = [0x00] + data
        while prefixed.count % 4 != 0 { prefixed.append(0x00) }
        var leWords: [UInt32] = []
        for i in stride(from: 0, to: prefixed.count, by: 4) {
            let w = UInt32(prefixed[i]) | (UInt32(prefixed[i+1]) << 8) | (UInt32(prefixed[i+2]) << 16) | (UInt32(prefixed[i+3]) << 24)
            leWords.append(w)
        }
        if leWords.count % 2 != 0 { leWords.append(0) }
        
        for (index, word) in leWords.enumerated() {
            var term = word &* (index % 2 == 0 ? keyA : keyB)
            var offset = rol16(word) &* (index % 2 == 0 ? 0xEF0569FB : 0xC31713DB)
            if index == 0 {
                term = term &+ (0xF2F90B1A &* factors.0)
                offset = offset &+ 0x0B1A0000
            }
            terms.append(term)
            offsets.append(offset)
        }
        
        var swapAcc: UInt32 = 0
        var swapLast: UInt32 = 0
        var state: UInt32 = 0
        var acc: UInt32 = 0
        for index in stride(from: 0, to: terms.count, by: 2) {
            let x = terms[index], y = terms[index + 1]
            var t = rol16(offsets[index] &+ x)
            var q = t &* 0x76F50F34
            swapAcc = swapAcc &+ (rol16(q) &* 0xC3EFEA97 &+ q)
            t = rol16(offsets[index + 1] &+ y)
            q = t &* 0x1881CE3C
            swapLast = rol16(q) &* 0x35BD1EC9 &+ q
            swapAcc = swapAcc &+ swapLast
            
            state = state &* keyA &+ x
            state = rol16(state) &* 0xCF98B111
            state = rol16(state) &* 0x87085B9F
            state = rol16(state) &* 0x12CEB96D
            state = rol16(state) &* 0x257E1D83
            acc = acc &+ state
            t = state &* keyB &+ y
            t = rol16(t) &* 0xA27416F5
            t = rol16(t) &* 0xD38396FF
            state = rol16(rol16(t) &* 0x7C932B89) &* 0xBFA49F69
            acc = acc &+ state
        }
        return (swapLast ^ state, swapAcc ^ acc)
    }
    
    public static func generateSecMsGecV2(unixTimestamp: TimeInterval) -> String {
        let winEpoch: Double = 11644473600.0
        var ticks = floor(unixTimestamp) + winEpoch
        ticks -= ticks.truncatingRemainder(dividingBy: 300.0)
        ticks *= 10_000_000.0
        let strToHash = String(format: "%.0f6A5AA1D4EAFF4E9FB37E23D68491D6F4", ticks)
        let bytes = Array(strToHash.utf8)
        let digest = sha256Digest(bytes)
        let (cs0, cs1) = cs64Digest(data: bytes, digest: digest)
        let csBytes: [UInt8] = [
            UInt8(cs0 & 0xFF), UInt8((cs0 >> 8) & 0xFF), UInt8((cs0 >> 16) & 0xFF), UInt8((cs0 >> 24) & 0xFF),
            UInt8(cs1 & 0xFF), UInt8((cs1 >> 8) & 0xFF), UInt8((cs1 >> 16) & 0xFF), UInt8((cs1 >> 24) & 0xFF)
        ]
        let csHex = csBytes.map { String(format: "%02X", $0) }.joined()
        let shaHex = digest.map { String(format: "%02X", $0) }.joined()
        return "\(csHex)-\(shaHex)"
    }
}
