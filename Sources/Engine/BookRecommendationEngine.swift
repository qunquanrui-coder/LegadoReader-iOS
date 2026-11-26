import Foundation
import Combine

public struct RecommendedBook: Identifiable, Equatable, Hashable, Codable {
    public var id: String { "\(title)_\(author)" }
    public let title: String
    public let author: String
    public let category: NovelCategory
    public let rating: String
    public let tagline: String
    public let intro: String
    public let coverUrl: String?
    public let isLive: Bool
    
    public init(
        title: String,
        author: String,
        category: NovelCategory,
        rating: String,
        tagline: String,
        intro: String,
        coverUrl: String? = nil,
        isLive: Bool = false
    ) {
        self.title = title
        self.author = author
        self.category = category
        self.rating = rating
        self.tagline = tagline
        self.intro = intro
        self.coverUrl = coverUrl
        self.isLive = isLive
    }
}

public enum NovelCategory: String, CaseIterable, Identifiable, Codable {
    public var id: String { rawValue }
    case trending = "实时热榜"
    case newBooks = "最新新书"
    case xianxia = "仙侠修真"
    case xuanhuan = "玄幻奇幻"
    case mystery = "悬疑诡秘"
    case urban = "都市百态"
    case historySciFi = "历史科幻"
    case classics = "经典殿堂"
    
    public var iconName: String {
        switch self {
        case .trending: return "flame.fill"
        case .newBooks: return "sparkle"
        case .xianxia: return "sparkles"
        case .xuanhuan: return "moon.stars.fill"
        case .mystery: return "eye.fill"
        case .urban: return "building.2.fill"
        case .historySciFi: return "hourglass"
        case .classics: return "crown.fill"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .trending: return "全网实时月票与畅销口碑"
        case .newBooks: return "2025-2026 潜力爆款新书"
        case .xianxia: return "问道长生 · 家族群像与新派修真"
        case .xuanhuan: return "异界诸天 · 宏大史诗与高燃爽文"
        case .mystery: return "无限智斗 · 规则怪谈与克苏鲁"
        case .urban: return "年代商战 · 高武觉醒与百态人生"
        case .historySciFi: return "考据架空 · 星际文明与硬核科幻"
        case .classics: return "网文二十年封神必读佳作"
        }
    }
}

public struct SearchSuggestion: Identifiable, Equatable {
    public var id: String { "\(title)_\(author ?? "")" }
    public let title: String
    public let author: String?
    public let tag: String?
    public let isCurated: Bool
}

private struct CachedLiveRankingsSnapshot: Codable {
    let updatedAt: Date
    let statusLabel: String
    let booksByCategoryRaw: [String: [RecommendedBook]]
}

public final class BookRecommendationEngine: ObservableObject {
    public static let shared = BookRecommendationEngine()
    
    @Published public private(set) var liveBooks: [NovelCategory: [RecommendedBook]] = [:]
    @Published public private(set) var isRefreshingRankings: Bool = false
    @Published public private(set) var lastRefreshedAt: Date? = nil
    @Published public private(set) var liveStatusLabel: String = "2026 高分口碑精选"
    
    private let cacheDefaultsKey = "LegadoReader_LiveRankingsSnapshot_v4_2"
    private let cacheTTL: TimeInterval = 6 * 3600
    
    public let curatedBooks: [RecommendedBook] = [
        // 实时热榜 (2025-2026 高分热门兜底榜)
        RecommendedBook(
            title: "玄鉴仙族",
            author: "季越人",
            category: .trending,
            rating: "9.8分",
            tagline: "古朴家族修仙群像 · 近年仙侠口碑天花板",
            intro: "陆江仙熬夜猝死，残魂附于一面裂痕铜镜飘落修仙世界。大黎山旁一个小家族拾得铜镜，由此传仙道、授仙法，开启波澜壮阔的家族修仙史诗。",
            coverUrl: "https://bookcover.yuewen.com/qdbimg/349573/1035420986/180"
        ),
        RecommendedBook(
            title: "夜无疆",
            author: "辰东",
            category: .trending,
            rating: "9.6分",
            tagline: "起点月票霸榜大作 · 那一天太阳再未升起",
            intro: "那一天太阳落下，再也没有升起。无尽永夜笼罩大世，古今强者沉眠复苏，少年秦铭于微末烛火中走出，照破山河万朵。",
            coverUrl: "https://bookcover.yuewen.com/qdbimg/349573/1039391177/180"
        ),
        RecommendedBook(
            title: "神宠供应商",
            author: "轻泉流响",
            category: .trending,
            rating: "9.7分",
            tagline: "2026 实时月票黑马 · 海洋纪元御兽大冒险",
            intro: "海洋纪元，人类与变异海兽共存。百米巨型乌贼拉动战船穿过危险海峡，洛羽穿越成为见习御兽师，开启大航海时代的传奇御兽之路。",
            coverUrl: "https://bookcover.yuewen.com/qdbimg/349573/1050460263/180"
        ),
        RecommendedBook(
            title: "十日终焉",
            author: "杀虫队队员",
            category: .trending,
            rating: "9.9分",
            tagline: "现象级无限流智斗神作 · 反转天花板",
            intro: "当我以为这只是寻常的一天时，却发现自己被捉到了终焉之地。十二生肖死亡游戏、十日轮回与回响觉醒，齐夏以凡人之智博弈神明。",
            coverUrl: nil
        ),
        RecommendedBook(
            title: "没钱修什么仙？",
            author: "熊狼狗",
            category: .trending,
            rating: "9.6分",
            tagline: "赛博金融修仙 · 脑洞与笑点齐飞",
            intro: "仙道工业化与金融化的赛博修真世界！“老者：想报仇吗？把你手机给我，这天庭备用功力先借你三成，分期慢慢还……”",
            coverUrl: "https://bookcover.yuewen.com/qdbimg/349573/1038484664/180"
        ),
        RecommendedBook(
            title: "我不是戏神",
            author: "三九音域",
            category: .trending,
            rating: "9.7分",
            tagline: "都市高武异能爆款 · 红色戏袍镇人间",
            intro: "赤色流星划过天际后，人类文明陷入停滞。大灾变后的灰烬时代，少年陈伶披上戏袍，在诡异与灾厄横行的世界里演绎人间惊鸿。",
            coverUrl: nil
        ),
        RecommendedBook(
            title: "廓晋",
            author: "榴弹怕水",
            category: .trending,
            rating: "9.7分",
            tagline: "东晋十六国硬核历史 · 考据文笔双巅峰",
            intro: "铁马金戈，衣冠南渡。乱世十六国风云激荡，且看主角如何于门阀林立与胡骑纵横之间运筹帷幄、再造山河。",
            coverUrl: nil
        ),
        RecommendedBook(
            title: "1979黄金时代",
            author: "睡觉会变白",
            category: .trending,
            rating: "9.5分",
            tagline: "年代文口碑神作 · 电影与时代的滚烫记忆",
            intro: "重回1979年那个万物复苏的黄金年代，从厂矿少年到时代见证者，细腻笔触勾勒改革开放浪潮下的烟火气与理想光芒。",
            coverUrl: nil
        ),
        
        // 最新新书 (2025-2026 潜力新书榜)
        RecommendedBook(
            title: "请勿高考时渡劫",
            author: "最白的乌鸦",
            category: .newBooks,
            rating: "9.5分",
            tagline: "2026 热读新书黑马 · 都市修真轻松爆笑",
            intro: "灵气复苏后的现代校园，高三学子正埋头刷题，考场外突然乌云密布雷劫降临——监考老师崩溃大喊：请勿在高考时渡劫！",
            coverUrl: nil
        ),
        RecommendedBook(
            title: "让仙门再次伟大",
            author: "一月九十秋",
            category: .newBooks,
            rating: "9.5分",
            tagline: "月票榜新锐佳作 · 宗门建设经营流",
            intro: "穿成没落仙门掌门，外有强敌环伺，内有债台高筑。既如此，便以现代宗门管理学重整山门，让仙门再次伟大！",
            coverUrl: nil
        ),
        RecommendedBook(
            title: "有仙则名",
            author: "金色茉莉花",
            category: .newBooks,
            rating: "9.6分",
            tagline: "潜力新书榜前列 · 志怪古风仙侠",
            intro: "山不在高，有仙则名。水不在深，有龙则灵。于烟雨江湖与志怪奇谈之中，写尽人间草木皆有灵的古典仙侠气象。",
            coverUrl: nil
        ),
        RecommendedBook(
            title: "旧生物",
            author: "穿黄衣的阿肥",
            category: .newBooks,
            rating: "9.5分",
            tagline: "2026 悬疑科幻新书 · 诡谲异星生态",
            intro: "当旧日纪元的沉眠造物重新苏醒，人类引以为傲的秩序在未知生态面前摇摇欲坠。一场跨越物种边界的深渊探索就此启程。",
            coverUrl: nil
        ),
        RecommendedBook(
            title: "异度旅社",
            author: "远瞳",
            category: .newBooks,
            rating: "9.7分",
            tagline: "科幻奇幻脑洞新书 · 诡秘时空群像",
            intro: "远瞳口碑新作，融合宏大时空设定与温暖细腻的旅社群像，在诡谲莫测的异度世界里点亮一盏接引旅人的明灯。",
            coverUrl: nil
        ),
        RecommendedBook(
            title: "黑仙",
            author: "纵横热榜新锐",
            category: .newBooks,
            rating: "9.4分",
            tagline: "暗黑诡道修仙新书 · 借邪祟法则修行",
            intro: "人人都说邪祟只能杀、不能碰。可沈暮偏要逆流而上，借邪祟法则淬炼己身，踏出一条前所未见的黑仙大道。",
            coverUrl: nil
        ),
        
        // 仙侠修真
        RecommendedBook(title: "玄鉴仙族", author: "季越人", category: .xianxia, rating: "9.8分", tagline: "家族修仙群像巅峰 · 古典韵味十足", intro: "陆江仙残魂附于一面铜镜，见证一个小家族历经数代风雨，在残酷修仙界步步登仙的宏大群像史诗。", coverUrl: "https://bookcover.yuewen.com/qdbimg/349573/1035420986/180"),
        RecommendedBook(title: "没钱修什么仙？", author: "熊狼狗", category: .xianxia, rating: "9.6分", tagline: "赛博修仙 · 仙道工业化金融化", intro: "老者：“你想报仇？”少年：“我被强者反复侮辱，怎么可能不想报仇？”老者：“好孩子，把你手机给我，这天庭备用功力借你……”", coverUrl: "https://bookcover.yuewen.com/qdbimg/349573/1038484664/180"),
        RecommendedBook(title: "赤心巡天", author: "情何以甚", category: .xianxia, rating: "9.7分", tagline: "天地至公如无情，我有赤心一颗以巡天", intro: "山河千里写伏尸，乾坤百年描恶虎。天地至公如无情，我有赤心一颗，以巡天！少年姜望执剑行走诸国。", coverUrl: nil),
        RecommendedBook(title: "光阴之外", author: "耳根", category: .xianxia, rating: "9.6分", tagline: "残酷废土修真 · 许青微末拔刀", intro: "天地是万物众生的客舍，光阴是古往今来的过客。残酷废土修真世界中，许青于微末中拔刀而起。", coverUrl: nil),
        RecommendedBook(title: "剑来", author: "烽火戏诸侯", category: .xianxia, rating: "9.7分", tagline: "大千世界，无奇不有，唯我一剑", intro: "大千世界，无奇不有。我陈平安，唯有一剑，可搬山，倒海，降妖，镇魔，敕神，摘星，断江，摧城，开天！", coverUrl: nil),
        RecommendedBook(title: "仙逆", author: "耳根", category: .xianxia, rating: "9.7分", tagline: "顺为凡，逆则仙，只在心中一念间", intro: "顺为凡，逆则仙，只在心中一念间……讲述平庸少年王林踏入修真界，逆天改命的传奇。", coverUrl: nil),
        
        // 玄幻奇幻
        RecommendedBook(title: "夜无疆", author: "辰东", category: .xuanhuan, rating: "9.6分", tagline: "永夜降临 · 辰东最新东方玄幻巨制", intro: "那一天太阳落下再也没有升起。长夜漫漫，微光不灭，少年于永夜时代逆境崛起，揭开纪元更迭的终极真相。", coverUrl: "https://bookcover.yuewen.com/qdbimg/349573/1039391177/180"),
        RecommendedBook(title: "无敌天命", author: "青鸾峰上", category: .xuanhuan, rating: "9.5分", tagline: "纵横月票榜首 · 我命由我不由天", intro: "谁言天命天注定？我命由我不由天！热血剑道与快节奏爽感拉满的长篇玄幻热作。", coverUrl: nil),
        RecommendedBook(title: "神通者", author: "天蚕土豆", category: .xuanhuan, rating: "9.4分", tagline: "热血玄幻新作 · 万道神通登峰造极", intro: "天地异变，神通觉醒。少年执掌无上神通，横扫诸天强敌，节奏明快、酣畅淋漓。", coverUrl: nil),
        RecommendedBook(title: "宿命之环", author: "爱潜水的乌贼", category: .xuanhuan, rating: "9.5分", tagline: "诡秘世界第二部 · 救赎与宿命", intro: "1368之年，七月之末，深红将从天而降。卢米安在科尔杜村开启了属于他的非凡旅途。", coverUrl: nil),
        RecommendedBook(title: "牧神记", author: "宅猪", category: .xuanhuan, rating: "9.6分", tagline: "大墟的祖训说，天黑，别出门", intro: "大墟残老村的老弱病残们从江边捡到了一个婴儿，取名秦牧，含辛茹苦将他养大。", coverUrl: nil),
        RecommendedBook(title: "万相之王", author: "天蚕土豆", category: .xuanhuan, rating: "9.3分", tagline: "天地间有万相，而我终将成为万相之王", intro: "天地间，有万相。而我李洛，终将成为这万相之王。", coverUrl: nil),
        
        // 悬疑诡秘
        RecommendedBook(title: "十日终焉", author: "杀虫队队员", category: .mystery, rating: "9.9分", tagline: "智斗悬疑无限流天花板", intro: "当我以为这只是寻常的一天时，却发现自己被捉到了终焉之地。众人觉醒超自然回响，在十日轮回中展开极限智斗。", coverUrl: nil),
        RecommendedBook(title: "道诡异仙", author: "狐尾的笔", category: .mystery, rating: "9.7分", tagline: "东方克苏鲁巅峰 · 坐忘道与白玉京", intro: "诡异的天道，异常的仙佛，是真？是假？陷入迷惘的李火旺无法分辨。分不清，我真的分不清啊！", coverUrl: nil),
        RecommendedBook(title: "神秘复苏", author: "佛前献花", category: .mystery, rating: "9.5分", tagline: "五浊恶世，厉鬼复苏，人间如狱", intro: "五浊恶世，地狱已空，厉鬼复苏，人间如狱。这个世界鬼出现了……那么神又在哪里？", coverUrl: nil),
        RecommendedBook(title: "我有一座冒险屋", author: "我会修空调", category: .mystery, rating: "9.6分", tagline: "半夜千万不要看 · 治愈系鬼屋老板陈歌", intro: "陈歌继承了失踪父母留下的冒险屋，整理时意外发现一部黑色手机，由此踏入一个个惊心动魄的灵异场景。", coverUrl: nil),
        RecommendedBook(title: "惊悚乐园", author: "三天两觉", category: .mystery, rating: "9.7分", tagline: "超越维度的游戏 · 封不觉的推理秀", intro: "这是超越维度的游戏，亦是追寻真理的竞逐。欢迎来到，惊悚乐园！", coverUrl: nil),
        
        // 都市百态
        RecommendedBook(title: "我不是戏神", author: "三九音域", category: .urban, rating: "9.7分", tagline: "都市高武灾变爆款 · 群像封神", intro: "灾变纪元下的红衣戏神，以凡胎之躯演绎惊世之戏，守护万家灯火。", coverUrl: nil),
        RecommendedBook(title: "1979黄金时代", author: "睡觉会变白", category: .urban, rating: "9.5分", tagline: "年代文高分神作 · 温暖细腻烟火气", intro: "重返1979，见证中国电影与改革开放初期的黄金浪潮，文风扎实温暖。", coverUrl: nil),
        RecommendedBook(title: "逆流1983", author: "纵横都市热作", category: .urban, rating: "9.4分", tagline: "无系统硬核重生 · 实业兴家", intro: "好消息：重生了！坏消息：没有系统也没有金手指。靠着前世眼光与脚踏实地，在1983年闯出一片天地。", coverUrl: nil),
        RecommendedBook(title: "深空彼岸", author: "辰东", category: .urban, rating: "9.4分", tagline: "旧术与新术交替 · 王煊超凡之路", intro: "浩瀚的宇宙中，一片星系的生灭，也不过是刹那的斑驳流光。王煊在旧术与新术交替的时代踏上超凡之路。", coverUrl: nil),
        RecommendedBook(title: "大医凌然", author: "志鸟村", category: .urban, rating: "9.4分", tagline: "硬核外科医生逆袭之路", intro: "医学院学生凌然有一个小目标，要成为世界上最伟大的医生，结果不小心实现了。", coverUrl: nil),
        
        // 历史科幻
        RecommendedBook(title: "廓晋", author: "榴弹怕水", category: .historySciFi, rating: "9.7分", tagline: "东晋十六国硬核历史 · 口碑新巅峰", intro: "聚焦东晋十六国风云激荡的北伐时代，考据严谨、人物鲜活，尽显家国情怀与权谋张力。", coverUrl: nil),
        RecommendedBook(title: "异度旅社", author: "远瞳", category: .historySciFi, rating: "9.7分", tagline: "科幻诡秘群像 · 远瞳最新力作", intro: "跨越现实与异度的奇幻旅社，宏大世界观与温暖日常完美交融。", coverUrl: nil),
        RecommendedBook(title: "黎明之剑", author: "远瞳", category: .historySciFi, rating: "9.7分", tagline: "高文爵士领主种田与纪元揭秘", intro: "高文穿越了，在某个异界大陆上空飘了十几万年之后，他终于找到了一具身体，开启席卷魔导时代的文明变革。", coverUrl: nil),
        RecommendedBook(title: "超神机械师", author: "齐佩甲", category: .historySciFi, rating: "9.5分", tagline: "星际科幻网游巅峰 · 黑星军团韩萧", intro: "韩萧穿越成星际网游公测前的NPC，毅然选择机械系，从萌芽小卒一步步成长为威震星海的黑星阁下。", coverUrl: nil),
        RecommendedBook(title: "庆余年", author: "猫腻", category: .historySciFi, rating: "9.6分", tagline: "积善之家，必有余庆 · 范闲庙堂江湖路", intro: "少年范闲自澹州入京都，在权谋与武道交织的世界里揭开神庙与叶轻眉的千年秘密。", coverUrl: nil),
        RecommendedBook(title: "三体", author: "刘慈欣", category: .historySciFi, rating: "9.9分", tagline: "给岁月以文明，而不是给文明以岁月", intro: "红岸工程向宇宙发出的第一声啼鸣，彻底改变了人类文明在黑暗森林中的命运。", coverUrl: nil),
        
        // 经典殿堂
        RecommendedBook(title: "诡秘之主", author: "爱潜水的乌贼", category: .classics, rating: "9.9分", tagline: "克苏鲁蒸汽朋克封神之作", intro: "蒸汽与机械的浪潮中，谁能触及非凡？历史和黑暗的迷雾里，又是谁在耳语？我从诡秘中醒来，睁眼看见这个世界。", coverUrl: "https://bookcover.yuewen.com/qdbimg/349573/1010868264/180"),
        RecommendedBook(title: "凡人修仙传", author: "忘语", category: .classics, rating: "9.8分", tagline: "凡人流开山鼻祖 · 百读不厌", intro: "一个普通山村穷小子韩立，偶然跨入江湖小门派，虽资质平庸，但依靠自身努力和稳健算计最终踏上仙途。", coverUrl: nil),
        RecommendedBook(title: "遮天", author: "辰东", category: .classics, rating: "9.7分", tagline: "九龙拉棺，开启浩瀚仙侠大世", intro: "冰冷与黑暗并存的宇宙深处，九具庞大的龙尸拉着一口青铜古棺，亘古长存。仙路尽头谁为峰，一见无始道成空。", coverUrl: nil),
        RecommendedBook(title: "雪中悍刀行", author: "烽火戏诸侯", category: .classics, rating: "9.6分", tagline: "天不生我李淳罡，剑道万古如长夜", intro: "有个白狐儿脸，佩双刀绣冬春雷，要做那天下第一。北凉世子徐凤年三入江湖，写尽庙堂与侠义。", coverUrl: nil),
        RecommendedBook(title: "大奉打更人", author: "卖报小郎君", category: .classics, rating: "9.5分", tagline: "仙侠探案破纪录现象级神作", intro: "这个世界，有儒、有道、有佛、有妖、有术士。警校毕业的许七安于牢狱中醒来，破奇案、斩奸邪、护大奉。", coverUrl: nil),
        RecommendedBook(title: "诛仙", author: "萧鼎", category: .classics, rating: "9.8分", tagline: "天地不仁，以万物为刍狗", intro: "青云门下普通少年张小凡，因缘际会卷入正邪两道千年纷争，谱写一段荡气回肠的仙侠绝恋。", coverUrl: nil),
        RecommendedBook(title: "完美世界", author: "辰东", category: .classics, rating: "9.6分", tagline: "一粒尘可填海，一根草斩尽日月星辰", intro: "群雄并起，万族林立，诸圣争霸，乱天动地。石昊自大荒走出，独断万古！", coverUrl: nil),
        RecommendedBook(title: "全职高手", author: "蝴蝶蓝", category: .classics, rating: "9.7分", tagline: "如果喜欢，就把这一切当作是荣耀", intro: "网游荣耀顶尖教科书叶修遭俱乐部驱逐后寄身网吧，手持千机伞重返巅峰赛场。", coverUrl: nil)
    ]
    
    private init() {
        loadCachedLiveRankings()
    }
    
    public func books(for category: NovelCategory) -> [RecommendedBook] {
        let live = liveBooks[category] ?? []
        let curated = curatedBooks.filter { $0.category == category }
        guard !live.isEmpty else { return curated }
        
        var merged: [RecommendedBook] = []
        var seen = Set<String>()
        for book in live + curated {
            let key = Self.normalizedTitleKey(book.title)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            merged.append(book)
        }
        return Array(merged.prefix(20))
    }
    
    public var dynamicHotKeywords: [String] {
        let liveTrending = (liveBooks[.trending] ?? []).prefix(8).map(\.title)
        let liveNew = (liveBooks[.newBooks] ?? []).prefix(4).map(\.title)
        let fallback = [
            "玄鉴仙族", "夜无疆", "神宠供应商", "十日终焉",
            "没钱修什么仙？", "我不是戏神", "廓晋", "1979黄金时代",
            "请勿高考时渡劫", "异度旅社", "剑来", "诡秘之主"
        ]
        var seen = Set<String>()
        var result: [String] = []
        for kw in liveTrending + liveNew + fallback {
            let key = Self.normalizedTitleKey(kw)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(kw)
            if result.count >= 12 { break }
        }
        return result
    }
    
    public func canonicalAuthor(for normalizedKeyword: String) -> String? {
        for list in liveBooks.values {
            if let hit = list.first(where: { Self.normalizedTitleKey($0.title) == normalizedKeyword }),
               !hit.author.isEmpty {
                return hit.author
            }
        }
        return curatedBooks.first(where: { Self.normalizedTitleKey($0.title) == normalizedKeyword })?.author
    }
    
    // MARK: - Live Online Ranking Refresh (Qidian Mobile SSR + Zongheng JSON API)
    public func refreshLiveRankingsIfNeeded(force: Bool = false) async {
        let shouldSkip = await MainActor.run { () -> Bool in
            if self.isRefreshingRankings { return true }
            if !force, let updated = self.lastRefreshedAt,
               Date().timeIntervalSince(updated) < self.cacheTTL,
               !(self.liveBooks[.trending]?.isEmpty ?? true) {
                return true
            }
            self.isRefreshingRankings = true
            return false
        }
        if shouldSkip { return }
        
        async let qidianYuepiao = fetchQidianRank(path: "yuepiao", defaultCategory: .trending, badgeFallback: "起点月票榜")
        async let qidianHotSales = fetchQidianRank(path: "hotsales", defaultCategory: .trending, badgeFallback: "24h热销榜")
        async let qidianNewFans = fetchQidianRank(path: "newfans", defaultCategory: .newBooks, badgeFallback: "潜力新书")
        async let zonghengMonthly = fetchZonghengRank(rankType: 1, defaultCategory: .trending, badgeFallback: "纵横月票")
        async let zonghengNew = fetchZonghengRank(rankType: 4, defaultCategory: .newBooks, badgeFallback: "纵横新书")
        
        let (qdYP, qdHot, qdNew, zhMon, zhNew) = await (qidianYuepiao, qidianHotSales, qidianNewFans, zonghengMonthly, zonghengNew)
        
        var bucket: [NovelCategory: [RecommendedBook]] = [:]
        func appendUnique(_ item: RecommendedBook, to category: NovelCategory) {
            var arr = bucket[category] ?? []
            let key = Self.normalizedTitleKey(item.title)
            guard !key.isEmpty, !arr.contains(where: { Self.normalizedTitleKey($0.title) == key }) else { return }
            arr.append(RecommendedBook(
                title: item.title,
                author: item.author,
                category: category,
                rating: item.rating,
                tagline: item.tagline,
                intro: item.intro,
                coverUrl: item.coverUrl,
                isLive: true
            ))
            bucket[category] = arr
        }
        
        // Interleave Qidian & Zongheng so the live trending leaderboard is diverse and up-to-date
        let trendingStream = Self.interleave(qdYP + qdHot, zhMon)
        for item in trendingStream {
            appendUnique(item, to: .trending)
            let mapped = Self.mapRemoteCategory(item.tagline, fallback: .xuanhuan)
            if mapped != .trending && mapped != .newBooks && mapped != .classics {
                appendUnique(item, to: mapped)
            }
        }
        
        let newBookStream = Self.interleave(qdNew, zhNew)
        for item in newBookStream {
            appendUnique(item, to: .newBooks)
            let mapped = Self.mapRemoteCategory(item.tagline, fallback: .xuanhuan)
            if mapped != .trending && mapped != .newBooks && mapped != .classics {
                appendUnique(item, to: mapped)
            }
        }
        
        let hasQidian = !qdYP.isEmpty || !qdHot.isEmpty || !qdNew.isEmpty
        let hasZongheng = !zhMon.isEmpty || !zhNew.isEmpty
        let hasAny = hasQidian || hasZongheng
        
        let summary: String
        if hasQidian && hasZongheng {
            summary = "已同步起点 · 纵横实时榜单"
        } else if hasQidian {
            summary = "已同步起点实时热榜"
        } else if hasZongheng {
            summary = "已同步纵横实时热榜"
        } else {
            summary = "2026 高分口碑精选（离线）"
        }
        
        await MainActor.run {
            self.isRefreshingRankings = false
            if hasAny {
                self.liveBooks = bucket
                self.lastRefreshedAt = Date()
                self.liveStatusLabel = summary
                self.saveCachedLiveRankings(bucket: bucket, statusLabel: summary, updatedAt: Date())
            } else if self.liveBooks.isEmpty {
                self.liveStatusLabel = summary
            }
        }
    }
    
    // MARK: - Live Feed Fetchers & Pure Parsers
    private func fetchQidianRank(path: String, defaultCategory: NovelCategory, badgeFallback: String) async -> [RecommendedBook] {
        guard let url = URL(string: "https://m.qidian.com/rank/\(path)") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 7
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        req.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return []
        }
        return Self.parseQidianRecords(from: html, defaultCategory: defaultCategory, badgeFallback: badgeFallback)
    }
    
    private func fetchZonghengRank(rankType: Int, defaultCategory: NovelCategory, badgeFallback: String) async -> [RecommendedBook] {
        guard let url = URL(string: "https://www.zongheng.com/api/rank/details") else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 7
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = ["rankType": rankType, "pageNum": 1, "pageSize": 15]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }
        return Self.parseZonghengRank(from: data, defaultCategory: defaultCategory, badgeFallback: badgeFallback)
    }
    
    /// Pure, unit-testable parser for Qidian Mobile SSR embedded `"records":[...]` JSON.
    public static func parseQidianRecords(
        from html: String,
        defaultCategory: NovelCategory,
        badgeFallback: String
    ) -> [RecommendedBook] {
        guard let jsonArraySlice = extractJSONArray(afterKey: "\"records\"", in: html),
              let data = jsonArraySlice.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        var results: [RecommendedBook] = []
        for obj in arr {
            guard let name = (obj["bName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            let author = ((obj["bAuth"] as? String) ?? "未知作者").trimmingCharacters(in: .whitespacesAndNewlines)
            let cat = ((obj["cat"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let subCat = ((obj["subCat"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let wordCount = ((obj["cnt"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rankCnt = ((obj["rankCnt"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = ((obj["desc"] as? String) ?? "")
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            var cover: String? = nil
            if let bid = obj["bid"] as? String, !bid.isEmpty {
                cover = "https://bookcover.yuewen.com/qdbimg/349573/\(bid)/180"
            } else if let bidNum = obj["bid"] as? Int {
                cover = "https://bookcover.yuewen.com/qdbimg/349573/\(bidNum)/180"
            }
            
            let badge: String
            if !rankCnt.isEmpty && rankCnt.rangeOfCharacter(from: .decimalDigits) != nil {
                badge = rankCnt.contains("票") || rankCnt.contains("万") ? rankCnt : "热度 \(rankCnt)"
            } else if !wordCount.isEmpty {
                badge = wordCount
            } else {
                badge = badgeFallback
            }
            
            let tagParts = [cat, subCat, wordCount].filter { !$0.isEmpty }
            let tagline = tagParts.isEmpty ? badgeFallback : tagParts.joined(separator: " · ")
            
            results.append(RecommendedBook(
                title: name,
                author: author,
                category: defaultCategory,
                rating: badge,
                tagline: tagline,
                intro: desc.isEmpty ? "全网实时热门连载佳作，点击立即多书源搜索阅读。" : desc,
                coverUrl: cover,
                isLive: true
            ))
        }
        return results
    }
    
    /// Pure, unit-testable parser for Zongheng live rank JSON response.
    public static func parseZonghengRank(
        from data: Data,
        defaultCategory: NovelCategory,
        badgeFallback: String
    ) -> [RecommendedBook] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let list = result["resultList"] as? [[String: Any]] else {
            return []
        }
        
        var books: [RecommendedBook] = []
        for obj in list {
            guard let name = (obj["bookName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            let author = ((obj["pseudonym"] as? String) ?? (obj["authorName"] as? String) ?? "纵横人气作家")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cateName = ((obj["cateFineName"] as? String) ?? (obj["cateName"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cover = (obj["bookCover"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = ((obj["description"] as? String) ?? "")
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let latest = ((obj["latestChapterName"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            
            let badge: String
            if let num = obj["number"] as? Int, num > 0 {
                if num >= 10_000 {
                    badge = String(format: "%.1f万热度", Double(num) / 10_000.0)
                } else {
                    badge = "\(num) 热度"
                }
            } else {
                badge = badgeFallback
            }
            
            let taglineParts = [cateName, latest.isEmpty ? badgeFallback : "更新：\(latest)"].filter { !$0.isEmpty }
            books.append(RecommendedBook(
                title: name,
                author: author,
                category: defaultCategory,
                rating: badge,
                tagline: taglineParts.joined(separator: " · "),
                intro: desc.isEmpty ? "纵横实时榜单热门作品，点击即刻全网搜书。" : desc,
                coverUrl: (cover?.hasPrefix("http") == true) ? cover : nil,
                isLive: true
            ))
        }
        return books
    }
    
    /// Extracts a balanced JSON array `[...]` immediately following `key:` in raw HTML/JS text.
    private static func extractJSONArray(afterKey key: String, in text: String) -> String? {
        guard let keyRange = text.range(of: key) else { return nil }
        var idx = keyRange.upperBound
        while idx < text.endIndex && text[idx] != "[" {
            idx = text.index(after: idx)
        }
        guard idx < text.endIndex, text[idx] == "[" else { return nil }
        
        let start = idx
        var depth = 0
        var inString = false
        var escaped = false
        
        while idx < text.endIndex {
            let ch = text[idx]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == "[" {
                    depth += 1
                } else if ch == "]" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...idx])
                    }
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }
    
    public static func mapRemoteCategory(_ tagText: String, fallback: NovelCategory) -> NovelCategory {
        if tagText.contains("仙侠") || tagText.contains("修真") || tagText.contains("古典") {
            return .xianxia
        }
        if tagText.contains("悬疑") || tagText.contains("灵异") || tagText.contains("推理") || tagText.contains("诡") {
            return .mystery
        }
        if tagText.contains("都市") || tagText.contains("现实") || tagText.contains("职场") || tagText.contains("年代") {
            return .urban
        }
        if tagText.contains("历史") || tagText.contains("科幻") || tagText.contains("军事") || tagText.contains("末世") {
            return .historySciFi
        }
        if tagText.contains("玄幻") || tagText.contains("奇幻") || tagText.contains("武侠") || tagText.contains("轻小说") || tagText.contains("诸天") {
            return .xuanhuan
        }
        return fallback
    }
    
    private static func interleave(_ primary: [RecommendedBook], _ secondary: [RecommendedBook]) -> [RecommendedBook] {
        var result: [RecommendedBook] = []
        var i = 0
        var j = 0
        while i < primary.count || j < secondary.count {
            if i < primary.count { result.append(primary[i]); i += 1 }
            if i < primary.count { result.append(primary[i]); i += 1 }
            if j < secondary.count { result.append(secondary[j]); j += 1 }
        }
        return result
    }
    
    private static func normalizedTitleKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "《", with: "")
            .replacingOccurrences(of: "》", with: "")
            .lowercased()
    }
    
    // MARK: - Local Cache Persistence
    private func loadCachedLiveRankings() {
        guard let data = UserDefaults.standard.data(forKey: cacheDefaultsKey),
              let snapshot = try? JSONDecoder().decode(CachedLiveRankingsSnapshot.self, from: data) else {
            return
        }
        var mapped: [NovelCategory: [RecommendedBook]] = [:]
        for (raw, list) in snapshot.booksByCategoryRaw {
            if let cat = NovelCategory(rawValue: raw) {
                mapped[cat] = list
            }
        }
        if !mapped.isEmpty {
            self.liveBooks = mapped
            self.lastRefreshedAt = snapshot.updatedAt
            self.liveStatusLabel = snapshot.statusLabel
        }
    }
    
    private func saveCachedLiveRankings(bucket: [NovelCategory: [RecommendedBook]], statusLabel: String, updatedAt: Date) {
        var rawDict: [String: [RecommendedBook]] = [:]
        for (cat, list) in bucket {
            rawDict[cat.rawValue] = list
        }
        let snapshot = CachedLiveRankingsSnapshot(updatedAt: updatedAt, statusLabel: statusLabel, booksByCategoryRaw: rawDict)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: cacheDefaultsKey)
        }
    }
    
    // MARK: - Hybrid Instant Local + Online Live Autocomplete
    public func fetchSuggestions(for query: String) async -> [SearchSuggestion] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        
        var results: [SearchSuggestion] = []
        var seenTitles = Set<String>()
        
        // 1. Instant Match from Live Rankings + Curated Catalog
        let pool = liveBooks.values.flatMap { $0 } + curatedBooks
        for book in pool {
            if book.title.localizedCaseInsensitiveContains(q) || book.author.localizedCaseInsensitiveContains(q) {
                if !seenTitles.contains(book.title) {
                    seenTitles.insert(book.title)
                    results.append(SearchSuggestion(
                        title: book.title,
                        author: book.author,
                        tag: "\(book.category.rawValue) · \(book.rating)",
                        isCurated: true
                    ))
                }
            }
        }
        
        // 2. Online Live Novel Autocomplete (Zongheng Novel Suggest API + Douban Book Suggest API)
        guard let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return results
        }
        
        async let zonghengList = fetchZonghengSuggestions(encodedQuery: encoded)
        async let doubanList = fetchDoubanSuggestions(encodedQuery: encoded)
        
        let (zh, db) = await (zonghengList, doubanList)
        for item in zh + db {
            if !seenTitles.contains(item.title) {
                seenTitles.insert(item.title)
                results.append(item)
            }
        }
        
        return Array(results.prefix(12))
    }
    
    private func fetchZonghengSuggestions(encodedQuery: String) async -> [SearchSuggestion] {
        guard let url = URL(string: "https://search.zongheng.com/search/suggest?keyword=\(encodedQuery)") else {
            return []
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any] else {
            return []
        }
        
        var items: [SearchSuggestion] = []
        if let books = dataDict["books"] as? [String] {
            for b in books {
                let clean = b.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    items.append(SearchSuggestion(title: clean, author: nil, tag: "全网热搜", isCurated: false))
                }
            }
        }
        return items
    }
    
    private func fetchDoubanSuggestions(encodedQuery: String) async -> [SearchSuggestion] {
        guard let url = URL(string: "https://book.douban.com/j/subject_suggest?q=\(encodedQuery)") else {
            return []
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        var items: [SearchSuggestion] = []
        for obj in arr.prefix(5) {
            if let title = obj["title"] as? String, !title.isEmpty {
                let author = obj["author_name"] as? String
                items.append(SearchSuggestion(title: title, author: author, tag: "豆瓣图书", isCurated: false))
            }
        }
        return items
    }
}
