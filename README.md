# 风读 (LegadoReader-iOS) 📚

![Platform](https://img.shields.io/badge/Platform-iOS%2016.0%2B-indigo)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20CoreText-purple)
![Edition](https://img.shields.io/badge/Edition-iPhone%20%26%20iPhone%20Duo-blue)
![Release](https://img.shields.io/badge/Release-v3.4.1-brightgreen)

**风读 (LegadoReader-iOS)** 是一款使用纯原生 **Swift + SwiftUI** 打造的 iOS 纯净小说阅读器，深度兼容 **开源阅读（Legado 3.0）** 书源规则体系（内置 20 个实测高速纯净书源 + 原生 `JavaScriptCore` 脚本引擎支持 `@js:` / `<js>` 规则），同时提供 **标准 iPhone 通用版** 与 **iPhone Duo 折叠双屏专享版** 两个独立安装包。

---

## 📦 最新版本下载 (`v3.4.1` 目录与听书状态修复版)

直接前往 [**GitHub Releases (v3.4.1)**](https://github.com/qunquanrui-coder/LegadoReader-iOS/releases/tag/v3.4.1) 或点击下方直链下载：

| 版本类型 | 适用设备 | 安装包直链 | 核心特性差异 |
| :--- | :--- | :--- | :--- |
| 📱 **iPhone 标准通用版** | 所有常规单屏 iPhone (`iOS 16.0+`) | [**`LegadoReader-unsigned.ipa`**](https://github.com/qunquanrui-coder/LegadoReader-iOS/releases/download/v3.4.1/LegadoReader-unsigned.ipa) | 桌面名称 **`风读小说`**，针对单手竖屏握持优化，默认全屏沉浸模式 |
| 📖 **iPhone Duo 折叠双屏专享版** | **iPhone Duo**（5.4" 外屏 + 7.6" 书本式折叠内屏）及宽屏设备 | [**`LegadoReader-iPhoneDuo-unsigned.ipa`**](https://github.com/qunquanrui-coder/LegadoReader-iOS/releases/download/v3.4.1/LegadoReader-iPhoneDuo-unsigned.ipa) | 桌面名称 **`风读小说 Duo`**，支持内外屏 0 黑边动态窗口切换、**展开 7.6" 内屏自动双页书本对开（带中轴 3D 书脊折痕光影）**、**左屏常驻目录+右屏阅读分屏模式**、内外屏自适应 3 列/5 列书架 |

---

## ✨ 核心功能全景

### 1. 📖 沉浸式排版与 CoreText 像素级测量分页
- **6 款东方美学背景主题**：`羊皮卷`、`宣纸白`、`竹林绿`、`樱花粉`、`暮光灰`、`曜石黑`。
- **3 种字体排版与自由字号行距**：支持 `书宋衬线`、`系统黑体`、`温润圆体`，字号（`14pt ~ 30pt`）与行距（`4pt ~ 20pt`）实时无级调节。
- **3 种翻页模式**：
  - `上下滚动`：丝滑长卷阅读，段落级可视锚点实时追踪。
  - `左右翻页`：基于 `GeometryReader` 真实可视尺寸 + `NSString.boundingRect` (CoreText) 像素级测量每一段高度，每一页严丝合缝贴合屏幕。
  - `Duo 双页书本`：左右双页对开（左页 $2k+1$ + 中轴书脊 + 右页 $2k+2$），翻一次翻两页。
- **智能段落重排与文本净化**：
  - 自动识别 HTML `<br>`、`</p>`、`&nbsp;`、双全角空格 `\u{3000}\u{3000}`，并对无换行粘连长章节按句末标点与对话引号智能分段，每段自动首行缩进两字符。
  - 支持 **原文 / 繁转简 / 简转繁** 实时转换，支持自定义去广告净化词条。

### 2. 📱 iPhone Duo 折叠双屏深度适配
- **5.4" 外屏 & 7.6" 折叠内屏满血无黑边**：启用 `UIRequiresFullScreen = false` 与多场景 `UIApplicationSceneManifest`，合上外屏单手精华阅读、展开内屏瞬间切换为宽幅视野，0 兼容黑边、不断流不丢进度。
- **精装实体书双页对开**：展开内屏自动切换为左右双页书本排版，正中央对齐物理钛合金铰链渲染仿真 **3D 书脊凹槽光影**，支持左右滑动或点击左右侧边缘一次翻过两页。
- **左屏常驻目录 + 右屏沉浸阅读**：展开内屏时，顶部导航栏提供 **「左屏目录 / 双页」** 一键切换按钮，支持左半屏固定章节目录抽屉、右半屏独立阅读。

### 3. 🎧 真人情感神经网络语音听书 & 锁屏后台无损续航
- **5 位微软 Edge Neural 真人情感主播**：
  - `云希 · 阳光少年音 (荐)`、`晓晓 · 温柔知性女声`、`云健 · 浑厚武侠评书`、`晓伊 · 灵动甜美女声`、`云扬 · 沉稳播音男声`。
  - 内置 `Sec-MS-GEC v2` (`CS64-SHA256`) 动态安全令牌生成与服务端 `Date` 时钟偏移自动校准，搭配 **百度在线神经网络语音** 与 **iOS 本地高音质 Siri 语音** 三级自动容灾降级。
- **双段超前预合成队列**：朗读当前段落时，后台自动并发预合成后续 **2 个段落** 的 MP3 音频流，段落切换零等待。
- **锁屏后台连续朗读 + 灵动岛/锁屏控制中心 + 书架底部迷你播放条**：
  - 声明系统级 `UIBackgroundModes: [audio, fetch, processing]` 权限，配合内存级静音 PCM 循环保活引擎与 `UIBackgroundTask` 双重守护，手机息屏锁屏后可通宵连续朗读并自动跨章节续播。
  - 接入 `MPNowPlayingInfoCenter` 与 `MPRemoteCommandCenter`，锁屏界面与灵动岛实时显示书名、章节与段落进度，支持锁屏或 AirPods 耳机直接控制暂停/继续/上一段/下一段。
  - 听书时退回书架，语音引擎自动接管跨章续读，并在书架底部浮现 **「迷你听书播放条」**。
- **听书与阅读状态强一致**：切书、切章、目录跳章前会先停止旧播放，再在新正文上重新开始；段落回调带「当前书 + 当前章」校验，避免把 A 书的朗读进度写进 B 书，也避免切章后音频与页面错位。

### 4. 📍 精确到「第几章·第几段」的续读记忆与智能目录
- **章节 + 段落双层持久化定位**：基于 `LazyVStack` 实时追踪屏幕顶部可见段落序号，退出小说或重启 App 后再次打开，自动跳回上次退出的 **精确章节与精确段落**（带顶部定位提示胶囊）。
- **书架「最近阅读」实时动态置顶**：点开任意小说或翻页阅读时，自动将其置顶并实时刷新书架顶部的「最近阅读」大卡片。
- **目录弹窗秒跳当前章节**：在阅读器内点击「目录」，弹窗打开瞬间自动滚动并居中高亮当前正在阅读的章节，提供 **「当前」一键定位**、**「正序/倒序」一键切换**、章节关键词检索及 **`已缓存`** 绿标提示。

### 5. 🔍 多源并发搜书、相关度智能排序与无感换源对齐
- **6 路并发检索 + 6 级相关度评分排序**：结果按 `书名完全一致 (1000分)` -> `作者完全一致 (850分)` -> `书名前缀匹配 (700分)` -> `书名包含关键词 (500分)` -> `作者包含关键词` 实时重排，最符合搜索要求的小说永远排在第一位。
- **首字实时联想 + 热门分类榜单**：输入首字即刻触发全网书名/作者自动补全建议，探索页内置热搜风云榜、玄幻仙侠、都市言情、科幻悬疑、历史武侠五大榜单。
- **换源自动清旧缓存 + 按章节标题智能对齐**：切换书源时自动清理旧站点缓存，并通过章节标题归一化匹配算法在新目录中自动对齐到同名章节，解决不同网站因「请假条/感言」导致目录序号偏移串章的问题。

### 6. 💾 四档高速并发缓存、JS 书源引擎与全量数据备份恢复
- **四档 6 路并发离线缓存**：阅读器顶部与书籍详情页支持 **「缓存后 30 章」**、**「缓存后 100 章」**、**「缓存后续全部章节」** 与 **「全本完整缓存」**，缓存存储在 `Library/Application Support/NovelCache_v4_complete` 并自动标记 `isExcludedFromBackup = true`，不占 iCloud 空间。
- **分页目录完整抓取**：兼容 Legado `ruleToc.nextTocUrl`（选择器 / `@js:` / `text.下一页` 等）及 `rel=next` / 分页容器「下一页」启发式，跨页按规范化 URL 去重、防 URL 环、限制最大页数并统一重建章节序号；只有跟完全部可发现的下一页才标记为完整目录，否则保存可用部分并提示「目录可能不完整」。
- **目录持久化 + 断网打开**：章节目录（标题 / 正文 URL / 完整性标记）与正文缓存一并保存，断网重开已缓存书籍无需再联网拉目录；目录记录绑定 `bookId + 书源 URL + 书籍 URL`，换源或换书自动失效，旧站点的章节不会串进来。
- **目录刷新保护**：后台刷新若未完整抓取，保留原完整目录，绝不用残缺结果覆盖（避免 1000 章被 100 章替换、进度被回退）；详情页换源会取消旧请求并按书源身份丢弃过期结果，旧书源目录不会污染新书源缓存。
- **备份恢复不回退进度**：书架、位置表与章节标题采用统一的「较新者胜」恢复规则（时间优先，同时间比章节号），旧备份不会把已读到的新章节覆盖回旧位置。
- **内置原生 `JavaScriptCore` (`LegadoJSEngine`)**：支持解析含 `@js:`、` <js>...</js> ` 及 `{{...}}` 动态脚本的 Legado 书源（内置 `java.encodeURI`、`java.base64Encode/Decode`、`java.md5Encode`、`java.put/get` 等桥接函数）。
- **全量数据备份与恢复（防丢失）**：在「我的 -> 数据备份与恢复」中支持 **导出完整备份 `.json` 文件**、**复制备份到剪贴板**、**从剪贴板恢复**、**从文件导入恢复**，一次性备份全部书架藏书、章节+段落阅读进度、书源与阅读设置。

---

## 🛠️ 项目结构

```text
LegadoReader-iOS/
├── .github/workflows/build.yml          # GitHub Actions 云端自动构建双版本 IPA 工作流
├── project.yml                          # XcodeGen 工程配置文件 (v3.4.1)
├── Resources/
│   ├── Info.plist                       # 后台音频权限、多窗口 Scene Manifest、动态版本号配置
│   ├── default_sources.json             # 内置 20 个实测高速纯净 Legado 书源
│   └── Assets.xcassets/                 # 东方水墨书卷 AppIcon 与应用静态资源
└── Sources/
    ├── App/
    │   ├── LegadoReaderApp.swift        # App 入口
    │   └── ContentView.swift            # 主 Tab 导航、阅读偏好设置、全量数据备份与恢复、缓存管理
    ├── Models/
    │   ├── Book.swift                   # 书籍与章节+段落阅读进度模型
    │   ├── Chapter.swift                # 章节目录模型
    │   ├── BookSource.swift             # Legado 3.0 书源规则模型与容错解码器
    │   └── ReaderTheme.swift            # 主题色板、翻页模式 (含 Duo 双页)、简繁转换、3D 书封组件
    ├── Engine/
    │   ├── LegadoParser.swift           # CSS/XPath/Regex 规则解析器、正文智能分段与去广告引擎
    │   ├── LegadoJSEngine.swift         # 基于 JavaScriptCore 的 @js: / <js> 书源脚本执行引擎
    │   ├── ChapterTextFormatter.swift   # 公共正文分段器与换源章节标题智能匹配算法
    │   ├── TocCache.swift               # 章节目录持久化（断网打开、完整性标记、换源自动失效）
    │   ├── NetworkManager.swift         # UTF-8/GB18030 自动解码网络层与搜索模板渲染
    │   ├── EdgeNeuralTTS.swift          # 微软 Edge 神经网络语音 WebSocket 引擎 (Sec-MS-GEC v2) + 百度兜底
    │   ├── SpeechSynthesizerManager.swift # 语音听书控制器、静音流锁屏保活、灵动岛/锁屏控制、后台脱离续读
    │   └── StorageManager.swift         # 书架最近阅读追踪、段落坐标映射、离线缓存/目录、备份恢复合并规则
    └── Views/
        ├── Bookshelf/
        │   └── BookshelfView.swift      # 书架主页、最近阅读动态卡片、内外屏自适应网格、底部迷你听书吧
        ├── Search/
        │   ├── SearchView.swift         # 多源并发搜索、6 级相关性排序、首字实时联想、热门分类榜单
        │   └── BookDetailView.swift     # 书籍详情、一键全本离线缓存、目录预览与换源
        ├── Reader/
        │   ├── ReaderView.swift         # 核心阅读器 (上下滚动 / CoreText 测量左右翻页 / Duo 双页对开 & 左屏目录)
        │   ├── ChapterListView.swift    # 目录弹窗 (打开秒跳当前章节、正序/倒序切换、缓存状态标记)
        │   ├── ReaderSettingsSheet.swift # 字体/行距/主题/简繁/净化/Duo 双页开关面板
        │   └── ChangeSourceSheet.swift  # 多书源并发比对与一键换源面板
        └── Sources/
            └── SourceManagerView.swift  # 书源管理、一键网络导入 (XIU2 / 3000+ 书源) 与剪贴板导入
```

---

## 📲 安装到 iPhone / iPhone Duo 指南

由于未签名 `.ipa` 安装包需签名后装入 iOS 设备，推荐以下任一方式：

1. **TrollStore（巨魔商店，永久免签）**：
   - 将下载的 `LegadoReader-unsigned.ipa`（或 `LegadoReader-iPhoneDuo-unsigned.ipa`）发送至手机，使用 TrollStore 打开即可一键永久安装。
2. **Sideloadly / AltStore / 爱思助手（无需越狱，支持所有 iOS 版本）**：
   - 在电脑端打开 [Sideloadly](https://sideloadly.io/)，连接手机，拖入 `.ipa` 文件并输入 Apple ID 即可自动签名安装。
3. **个人证书 / 轻松签 (ESign) / 全能签**：
   - 导入 `.ipa` 后使用自有证书签名安装。

---

## 🗓️ 版本演进记录

- **`v3.4.1`**：修复 4 个审查遗漏——后台目录刷新不完整时不再覆盖原完整目录（避免 1000 章被 100 章的残缺结果替换并回退进度）；详情页换源时取消旧目录请求并校验请求身份，旧书源结果不再污染新书源缓存；听书切章加载期间点停止后不再自动复播；自动进入下一章时不再取消睡眠定时（区分「停止当前音频」与「结束听书会话」）。
- **`v3.4.0`**：修复听书切书/切章时旧音频继续播放并把段落进度写到新章节的问题（统一先停旧播放、回调增加上下文校验）；章节目录持久化，已缓存书籍断网可打开并静默刷新；支持 Legado 分页目录 `nextTocUrl` 与跨页去重、完整性标记；备份恢复统一「较新者胜」规则，旧备份不再回退阅读位置。
- **`v3.3.0`**：新增真实屏幕尺寸 CoreText (`NSString.boundingRect`) 像素级测量分页、全量数据备份与恢复系统（导出/导入 `.json` 及剪贴板恢复）、原生 `JavaScriptCore` (`LegadoJSEngine`) 支持 `@js:` / `<js>` 书源规则、统一工程版本号管理。
- **`v3.2.1`**：修复换源后沿用旧缓存导致章节错位问题（换源自动清缓存并按章节标题智能对齐新目录）、分段结果缓存与 1.2 秒节流保存进度、支持退出阅读器后后台自动续章听书 + 书架底部迷你播放条、离线缓存迁移至 `Application Support` 并排除 iCloud 备份。
- **`v3.2.0`**：修复书架「最近阅读」卡片动态追踪与置顶、新增锁屏后台连续听书保活引擎 + 锁屏/灵动岛媒体控制中心、修复目录弹窗打开自动居中跳转到当前阅读章节。
- **`v3.1.0`**：升级微软 Edge Neural 真人情感语音听书（云希/晓晓/云健等 5 位主播 + 双段预取）、新增全本完整缓存等四档并发缓存、新增精确到章节内「第几段」的退出续读定位，并推出 **iPhone Duo 折叠双屏专享版**。
- **`v3.0.0` ~ `v1.0.0`**：构建纯原生 SwiftUI 阅读器架构、内置 20 个高速纯净书源、多源并发搜索与相关性排序、仿真翻页、简繁转换与去广告净化。
