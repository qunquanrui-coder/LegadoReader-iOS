import Foundation

public struct RecommendedBook: Identifiable, Equatable, Hashable {
    public var id: String { "\(title)_\(author)" }
    public let title: String
    public let author: String
    public let category: NovelCategory
    public let rating: String
    public let tagline: String
    public let intro: String
}

public enum NovelCategory: String, CaseIterable {
    case trending = "巅峰热榜"
    case xianxia = "仙侠修真"
    case xuanhuan = "玄幻奇幻"
    case mystery = "悬疑诡秘"
    case urban = "都市百态"
    case historySciFi = "历史科幻"
    
    public var iconName: String {
        switch self {
        case .trending: return "flame.fill"
        case .xianxia: return "sparkles"
        case .xuanhuan: return "moon.stars.fill"
        case .mystery: return "eye.fill"
        case .urban: return "building.2.fill"
        case .historySciFi: return "hourglass"
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

public class BookRecommendationEngine {
    public static let shared = BookRecommendationEngine()
    
    public let curatedBooks: [RecommendedBook] = [
        // 巅峰热榜
        RecommendedBook(title: "凡人修仙传", author: "忘语", category: .trending, rating: "9.8分", tagline: "凡人流开山鼻祖 · 百读不厌", intro: "一个普通山村穷小子，偶然之下，跨入到一个江湖小门派，虽然资质平庸，但依靠自身努力和合理算计最后修炼成仙的故事。"),
        RecommendedBook(title: "诡秘之主", author: "爱潜水的乌贼", category: .trending, rating: "9.9分", tagline: "克苏鲁蒸汽朋克封神之作", intro: "蒸汽与机械的浪潮中，谁能触及非凡？历史和黑暗的迷雾里，又是谁在耳语？我从诡秘中醒来，睁眼看见这个世界。"),
        RecommendedBook(title: "剑来", author: "烽火戏诸侯", category: .trending, rating: "9.7分", tagline: "大千世界，无奇不有，唯我一剑", intro: "大千世界，无奇不有。我陈平安，唯有一剑，可搬山，倒海，降妖，镇魔，敕神，摘星，断江，摧城，开天！"),
        RecommendedBook(title: "道诡异仙", author: "狐尾的笔", category: .trending, rating: "9.6分", tagline: "东方克苏鲁巅峰 · 精神病院与修真界", intro: "诡异的天道，异常的仙佛，是真？是假？陷入迷惘的李火旺无法分辨。分不清，我真的分不清啊！"),
        RecommendedBook(title: "遮天", author: "辰东", category: .trending, rating: "9.7分", tagline: "九龙拉棺，开启浩瀚仙侠大世", intro: "冰冷与黑暗并存的宇宙深处，九具庞大的龙尸拉着一口青铜古棺，亘古长存。仙路尽头谁为峰，一见无始道成空。"),
        RecommendedBook(title: "大奉打更人", author: "卖报小郎君", category: .trending, rating: "9.5分", tagline: "仙侠探案破纪录现象级神作", intro: "这个世界，有儒；有道；有佛；有妖；有术士。警校毕业的许七安幽幽醒来，发现自己身处牢狱之中，三日后流放边陲……"),
        RecommendedBook(title: "雪中悍刀行", author: "烽火戏诸侯", category: .trending, rating: "9.6分", tagline: "天不生我李淳罡，剑道万古如长夜", intro: "有个白狐儿脸，佩双刀绣冬春雷，要做那天下第一。湖底有白发老魁爱吃荤。缺门牙老仆背剑匣。山上有个骑青牛的年轻师叔祖……"),
        RecommendedBook(title: "宿命之环", author: "爱潜水的乌贼", category: .trending, rating: "9.5分", tagline: "诡秘世界第二部 · 救赎与宿命", intro: "诡秘世界第二部。1368之年，七月之末，深红将从天而降。卢米安在科尔杜村开启了属于他的非凡旅途。"),
        
        // 仙侠修真
        RecommendedBook(title: "仙逆", author: "耳根", category: .xianxia, rating: "9.7分", tagline: "顺为凡，逆则仙，只在心中一念间", intro: "顺为凡，逆则仙，只在心中一念间……请看耳根作品《仙逆》，讲述平庸少年王林踏入修真界，逆天改命的传奇。"),
        RecommendedBook(title: "诛仙", author: "萧鼎", category: .xianxia, rating: "9.8分", tagline: "天地不仁，以万物为刍狗", intro: "天地不仁，以万物为刍狗！青云门下普通少年张小凡，因缘际会卷入正邪两道千年纷争，谱写一段荡气回肠的仙侠绝恋。"),
        RecommendedBook(title: "一念永恒", author: "耳根", category: .xianxia, rating: "9.5分", tagline: "一念成沧海，一念化桑田", intro: "一念成沧海，一念化桑田。一念斩千魔，一念诛万仙。唯我念……永恒！这是耳根继《仙逆》《求魔》后的爆笑仙侠大作。"),
        RecommendedBook(title: "求魔", author: "耳根", category: .xianxia, rating: "9.6分", tagline: "魔前一叩三千年，回首凡尘不做仙", intro: "魔前一叩三千年，回首凡尘不做仙，只为她……掌缘生灭！苏铭在一场场的宿命轮回中追寻真相。"),
        RecommendedBook(title: "光阴之外", author: "耳根", category: .xianxia, rating: "9.5分", tagline: "天地是万物众生的客舍，光阴是古往今来的过客", intro: "天地是万物众生的客舍，光阴是古往今来的过客。残酷废土修真世界中，许青于微末中拔刀而起。"),
        RecommendedBook(title: "凡人修仙之仙界篇", author: "忘语", category: .xianxia, rating: "9.4分", tagline: "韩立飞升仙界后的再续传奇", intro: "凡人修仙，风云再起；时空穿梭，轮回逆转；金仙太乙，大罗道祖；三千大道，法则至尊。韩立飞升真仙界后的全新篇章！"),
        RecommendedBook(title: "赤心巡天", author: "情何以甚", category: .xianxia, rating: "9.6分", tagline: "上古时代，妖族绝迹；近古时代，龙族消失", intro: "山河千里写伏尸，乾坤百年描恶虎。天地至公如无情，我有赤心一颗，以巡天！姜望执剑行走诸国。"),
        RecommendedBook(title: "没钱修什么仙？", author: "熊狼狗", category: .xianxia, rating: "9.4分", tagline: "赛博修仙 · 仙道工业化金融化", intro: "老者：“你想报仇？”少年：“我被强者反复侮辱，被师尊视为垃圾，我怎么可能不想报仇？”老者：“好孩子，把你手机给我，这天庭备用功力借你……”"),
        
        // 玄幻奇幻
        RecommendedBook(title: "完美世界", author: "辰东", category: "玄幻奇幻" == "玄幻奇幻" ? .xuanhuan : .xuanhuan, rating: "9.6分", tagline: "一粒尘可填海，一根草斩尽日月星辰", intro: "一粒尘可填海，一根草斩尽日月星辰，弹指间天翻地覆。群雄并起，万族林立，诸圣争霸，乱天动地。问苍茫大地，谁主沉浮？！"),
        RecommendedBook(title: "斗破苍穹", author: "天蚕土豆", category: .xuanhuan, rating: "9.5分", tagline: "三十年河东，三十年河西，莫欺少年穷！", intro: "这里是属于斗气的世界，没有花俏艳丽的魔法，有的，仅仅是繁衍到巅峰的斗气！萧炎开启退婚逆袭之路。"),
        RecommendedBook(title: "牧神记", author: "宅猪", category: .xuanhuan, rating: "9.6分", tagline: "大墟的祖训说，天黑，别出门", intro: "大墟的祖训说，天黑，别出门。大墟残老村的老弱病残们从江边捡到了一个婴儿，取名秦牧，含辛茹苦将他养大。"),
        RecommendedBook(title: "圣墟", author: "辰东", category: .xuanhuan, rating: "9.2分", tagline: "在破败中崛起，在寂灭中复苏", intro: "在破败中崛起，在寂灭中复苏。沧海成尘，雷电枯竭，那一缕幽雾又一次临近大地，世间的枷锁被打开了。"),
        RecommendedBook(title: "盘龙", author: "我吃西红柿", category: .xuanhuan, rating: "9.6分", tagline: "西方奇幻经典 · 盘龙戒指的传说", intro: "大小的血睛鬃毛狮，力大无穷的紫睛金毛猿，毁天灭地的九头蛇皇……林雷在乌山镇偶得一枚神秘的盘龙戒指。"),
        RecommendedBook(title: "武动乾坤", author: "天蚕土豆", category: .xuanhuan, rating: "9.3分", tagline: "修炼一途，乃窃阴阳，夺造化", intro: "修炼一途，乃窃阴阳，夺造化，转涅盘，握生死，掌轮回。武之极，破苍穹，动乾坤！"),
        RecommendedBook(title: "万相之王", author: "天蚕土豆", category: .xuanhuan, rating: "9.3分", tagline: "天地间有万相，而我李洛，终将成为这万相之王", intro: "天地间，有万相。而我李洛，终将成为这万相之王。"),
        RecommendedBook(title: "神墓", author: "辰东", category: .xuanhuan, rating: "9.5分", tagline: "待到阴阳逆乱时，以我魔血染青天", intro: "一个死去万载岁月的平凡青年从远古神墓中复活而出，如林的神魔墓碑令他感到异常震撼。"),
        
        // 悬疑诡秘
        RecommendedBook(title: "十日终焉", author: "杀虫队队员", category: .mystery, rating: "9.8分", tagline: "智斗悬疑无限流天花板", intro: "当我以为这只是寻常的一天时，却发现自己被捉到了终焉之地。当我认为只需要不断地参加死亡游戏就可以逃脱时，却发现众人开始觉醒超自然之力……"),
        RecommendedBook(title: "惊悚乐园", author: "三天两觉", category: .mystery, rating: "9.7分", tagline: "超越维度的游戏 · 封不觉的疯狂剧场", intro: "这是超越维度的游戏，亦是追寻真理的竞逐。欢迎来到，惊悚乐园！觉哥带你体验毫无恐惧的推理秀。"),
        RecommendedBook(title: "我有一座冒险屋", author: "我会修空调", category: .mystery, rating: "9.6分", tagline: "半夜千万不要看 · 治愈系鬼屋老板陈歌", intro: "陈歌继承了失踪父母留下的冒险屋，无奈生意萧条，直到整理冒险屋时意外发现一部黑色手机，改变了这一切。"),
        RecommendedBook(title: "神秘复苏", author: "佛前献花", category: .mystery, rating: "9.5分", tagline: "五浊恶世，地狱已空，厉鬼复苏，人间如狱", intro: "五浊恶世，地狱已空，厉鬼复苏，人间如狱。这个世界鬼出现了……那么神又在哪里？求神救世，可世上已无神，只有鬼。"),
        RecommendedBook(title: "盗墓笔记", author: "南派三叔", category: .mystery, rating: "9.6分", tagline: "用我一生，换你十年天真无邪", intro: "五十年前，一群长沙土夫子挖到一部战国帛书，残篇中记载了一座奇特的战国古墓的位置，但那群土夫子在地下碰上了诡异事件……"),
        RecommendedBook(title: "鬼吹灯", author: "天下霸唱", category: .mystery, rating: "9.7分", tagline: "人点烛，鬼吹灯 · 摸金校尉开山之作", intro: "远古的文明，失落的宝藏，神秘莫测的古墓。胡八一、王胖子与Shirley杨组成的摸金铁三角探秘千年遗迹。"),
        
        // 都市百态
        RecommendedBook(title: "全职高手", author: "蝴蝶蓝", category: .urban, rating: "9.7分", tagline: "如果喜欢，就把这一切当作是荣耀，而不是炫耀", intro: "网游荣耀中被誉为教科书级别的顶尖高手叶修，因为种种原因遭到俱乐部的驱逐，离开职业圈的他寄身于一家网吧成了一个小小的网管……"),
        RecommendedBook(title: "大医凌然", author: "志鸟村", category: .urban, rating: "9.4分", tagline: "医学院学生凌然的硬核外科逆袭之路", intro: "医学院学生凌然有一个小目标，要成为世界上最伟大的医生，结果不小心实现了。"),
        RecommendedBook(title: "重生之都市修仙", author: "十里剑神", category: .urban, rating: "9.3分", tagline: "渡劫期大修士陈北玄重回地球少年时代", intro: "渡劫期大修士陈凡陨落在天劫中，却一梦五百年重回地球的年少时代。上一世我登临宇宙之巅，俯瞰万界，却无人相伴；这一世只愿不负前尘不负卿。"),
        RecommendedBook(title: "黄金瞳", author: "打眼", category: .urban, rating: "9.4分", tagline: "古玩鉴宝都市经典神作", intro: "典当行工作的小职员庄睿，在一次意外中眼睛发生异变。美轮美奂的陶瓷，古拙大方的青铜器，惊心动魄的赌石接踵而来。"),
        RecommendedBook(title: "隐杀", author: "愤怒的香蕉", category: .urban, rating: "9.5分", tagline: "世界顶级杀手重生温馨青春日常", intro: "哪怕是杀手，也有他的日常生活。厌倦了黑暗世界的顶尖杀手家明重生回到青春时代，体验平淡却又暗流涌动的岁月。"),
        RecommendedBook(title: "深空彼岸", author: "辰东", category: .urban, rating: "9.3分", tagline: "浩瀚的宇宙中，一片星系的生灭，也不过是刹那的斑驳流光", intro: "浩瀚的宇宙中，一片星系的生灭，也不过是刹那的斑驳流光。王煊在旧术与新术交替的时代踏上超凡之路。"),
        
        // 历史科幻
        RecommendedBook(title: "三体", author: "刘慈欣", category: .historySciFi, rating: "9.9分", tagline: "给岁月以文明，而不是给文明以岁月", intro: "文化大革命如火如荼进行的同时，军方探寻外星文明的绝秘计划“红岸工程”取得了突破性进展。地球文明向宇宙发出的第一声啼鸣，彻底改变了人类的命运。"),
        RecommendedBook(title: "吞噬星空", author: "我吃西红柿", category: .historySciFi, rating: "9.6分", tagline: "未来大涅槃时期 · 罗峰浩瀚宇宙征途", intro: "继《九鼎记》《盘龙》《星辰变》之后，番茄打造的宏大未来科幻进化世界。少年罗峰自地球崛起，纵横亿万星系。"),
        RecommendedBook(title: "赘婿", author: "愤怒的香蕉", category: .historySciFi, rating: "9.6分", tagline: "家国天下 · 半部武林半部朝堂", intro: "武朝末年，岁月峥嵘，天下纷乱，金辽相抗，局势动荡。金融界巨头宁毅穿越为苏氏布行的小小赘婿，从微末商贾直到搅动天下风云。"),
        RecommendedBook(title: "庆余年", author: "猫腻", category: .historySciFi, rating: "9.6分", tagline: "积善之家，必有余庆 · 范闲的庙堂江湖路", intro: "积善之家，必有余庆，留余庆，留余庆，忽遇恩人；幸娘亲，幸娘亲，积得阴功。少年范闲自澹州入京都，揭开神庙与叶轻眉的千年秘密。"),
        RecommendedBook(title: "超神机械师", author: "齐佩甲", category: .historySciFi, rating: "9.5分", tagline: "星际科幻网游巅峰 · 黑星军团韩萧", intro: "韩萧，《星海》骨灰级代练，被来自东方的神秘力量扔进穿越大军，携带玩家面板变成NPC，回到《星海》公测之前，毅然选择难度最高的机械系。"),
        RecommendedBook(title: "黎明之剑", author: "远瞳", category: .historySciFi, rating: "9.7分", tagline: "高文爵士穿越千年后的领主种田与纪元揭秘", intro: "高文穿越了，但穿越的时候稍微出了点问题。在某个异界大陆上空飘了十几万年之后，他觉得自己可能需要一具身体才算成为一个完整的穿越者。")
    ]
    
    private init() {}
    
    public func books(for category: NovelCategory) -> [RecommendedBook] {
        return curatedBooks.filter { $0.category == category }
    }
    
    // MARK: - Hybrid Instant Local + Online Live Autocomplete
    public func fetchSuggestions(for query: String) async -> [SearchSuggestion] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        
        var results: [SearchSuggestion] = []
        var seenTitles = Set<String>()
        
        // 1. Instant Curated Local Match (Title, Author, Tagline)
        for book in curatedBooks {
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
