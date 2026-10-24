# 风读 (LegadoReader-iOS) 📚

原生 **Swift + SwiftUI** 开发的 iOS 小说阅读器，兼容**开源阅读（Legado 3.0）**标准书源规则（支持笔趣阁等全网千万级书源）。

---

## ✨ 核心特性

- 📱 **纯原生 SwiftUI**：针对 iOS 16/17+ 优化，丝滑流畅，非网页套壳。
- 🔍 **多书源并发检索**：基于 Swift async/await 并发向全网书源检索小说，快速去重合并。
- 🔄 **智能换源**：随时比对不同站点目录，一键无缝换源阅读。
- 📖 **沉浸式阅读器**：
  - 羊皮纸 / 护眼绿 / 纯黑夜间 / 极简白等多种色板。
  - 字号、行距、边距自适应调节。
  - 翻页进度条、章节目录直达、重试刷新。
- 💾 **离线章节缓存**：自动缓存已读与预读章节到本地沙盒，断网无忧。
- 🌐 **网络导入 3000+ 书源**：支持直接粘贴远程 JSON 直链，一键导入。
- 🚀 **GitHub Actions 云端自动构建**：无需 Mac 电脑，推送代码至 GitHub 即可自动编译并输出未签名 `.ipa` 安装包。

---

## 🛠️ 项目结构

```text
LegadoReader-iOS/
├── .github/workflows/build.yml   # GitHub Actions 自动化编译打包工作流
├── project.yml                   # XcodeGen 规范配置文件（自动生成 Xcode 工程）
├── Resources/
│   ├── Info.plist                # 应用配置与网络权限 (允许任意网络请求)
│   ├── default_sources.json      # 内置精选笔趣阁等可用书源
│   └── Assets.xcassets/          # 图标与静态资产
└── Sources/
    ├── App/                      # 应用入口与主 Tab 页面
    ├── Engine/                   # Legado 规则解析引擎、网络请求与持久化
    ├── Models/                   # 数据模型 (Book, Chapter, BookSource 等)
    └── Views/                    # 书架、搜索、详情、阅读器、书源管理视图
```

---

## 🚀 部署与云端编译指南 (在 Windows 上即可完成)

### 第一步：在 GitHub 上创建新仓库
1. 访问你的 GitHub 主页：[https://github.com/qunquanrui-coder](https://github.com/qunquanrui-coder)
2. 点击右上角 **New**（新建仓库）。
3. 仓库名称填写：`LegadoReader-iOS`（设为 Public 或 Private 均可）。
4. **不要勾选** "Add a README file"，点击 **Create repository**。

---

### 第二步：推送本地代码到 GitHub
在当前 Windows 电脑上打开 PowerShell，依次运行以下命令：

```powershell
# 1. 进入项目根目录
cd C:\Users\qunqun\.gemini\antigravity\scratch\LegadoReader-iOS

# 2. 初始化 Git 仓库
git init

# 3. 添加所有文件并提交
git add .
git commit -m "feat: initial release of LegadoReader iOS"

# 4. 关联到你的 GitHub 仓库 (若未设置分支名则切换到 main)
git branch -M main
git remote add origin https://github.com/qunquanrui-coder/LegadoReader-iOS.git

# 5. 推送到 GitHub
git push -u origin main
```

---

### 第三步：等待 GitHub 自动编译生成 IPA
1. 推送完成后，打开网页上的仓库页面，点击上方的 **Actions** 标签栏。
2. 你会看到名为 **"Build iOS IPA"** 的工作流正在由 GitHub 免费的 macOS 服务器自动运行。
3. 等待约 3~4 分钟构建完成（显示绿色的对勾 ✅）。
4. 点击该次构建记录，在页面下方的 **Artifacts** 区域即可找到并下载 **`LegadoReader-unsigned-ipa`** 压缩包！
5. 解压后即可得到 `LegadoReader-unsigned.ipa` 安装包。

---

### 第四步：安装到 iPhone

由于 iOS 系统的安全限制，未签名的 `.ipa` 安装到真机有以下常见方案：

1. **巨魔商店（TrollStore）**：如果你的 iPhone 系统支持巨魔，直接将 `.ipa` 传输到手机隔空投送或用微云/百度网盘打开，选择“TrollStore”安装，永久可用。
2. **Sideloadly / 爱思助手 / AltStore**（推荐，任何正常 iPhone 均可）：
   - 在电脑上下载免费的 [Sideloadly](https://sideloadly.io/)。
   - iPhone 连接电脑，打开 Sideloadly。
   - 将 `LegadoReader-unsigned.ipa` 拖入，输入你的 Apple ID 即可自动免费自签名并直接装入 iPhone（无需越狱，可用 7 天，到期电脑自动连网刷新）。
3. **企业证书 / 签名码工具**：使用国内常见的个人签名或签名助手安装。

---

## 📖 在应用内导入 3000+ 书源

安装打开 App 后：
1. 切换到 **“书源”** 标签页。
2. 点击右上角 **“网络导入”**。
3. 预置按钮中已内置 **“3000+ 综合校验源”** 与 **“XIU2 精品书源”**，点击即可一键载入！
4. 导入后回到 **“搜索”** 栏，输入任何你想看的小说，即可享受极速纯净阅读！
