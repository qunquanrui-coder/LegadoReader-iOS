# 风读 v4.1.0 · 全场景东方书房精修版（阅读器与弹窗全链路美化、分页容错加固与自定义请求头支持）

发布日期：2026-11-23

## 本版变化

1. **🛡️ 正文分页容错、自定义请求头与 GBK 动态模板修复**：
   - **正文分页脚本隔离 (`ChapterContentLoader`)**：当书源 `ruleContent.nextContentUrl` 含有受限脚本（如 `for`/`while` 循环）时，不再污染当前 JS 会话导致整章正文被丢弃，而是平滑降级至通用的「下一页」链接识别。
   - **书源安全请求头支持 (`NetworkManager.applyCustomHeaders`)**：自动解析并应用书源 `header` 字段中的安全 HTTP 请求头（`User-Agent`、`Accept`、`Accept-Language`、`X-Requested-With`），同时拦截不安全头字段。
   - **动态搜索模板 GBK 编码一致性 (`LegadoJSEngine.renderUrlTemplate`)**：当 `searchUrl` 同时包含 GBK/GB2312 声明与 `{{...}}` / `@js:` 动态表达式时，`{{key}}` 保持使用 GB18030 字节百分号编码。
   - **设置页无障碍节点刷新加固 (`SettingsView` & `SettingsSafetyUITests`)**：为书源概览行绑定显式动态 ID 与无障碍标签，并在 UI 测试中严格等待弹窗消散动画完成，彻底消除模拟器高负载下的无障碍缓存抖动。
2. **🎨 阅读器顶底栏与全弹窗「东方雅致书房」视觉统一**：
   - **阅读器顶底控制栏 (`ReaderView`)**：顶栏新增当前书源胶囊与章节副标题；底栏滑块上方新增实时「章节名 + 第 X/Y 章 · 进度百分比」指示条，上下章切换升级为圆角胶囊按钮。
   - **排版设置面板 (`ReaderSettingsSheet`)**：顶部新增**「东方雅致书房 · 实时排版预览」**卡片（实时联动当前背景主题、字体、字号与行距渲染《赤壁赋》名句），主题色卡新增选中角标。
   - **章节目录 (`ChapterListView`) & 书籍详情页 (`BookDetailView`)**：目录弹窗顶部新增「总章数 + 已缓存章数 + 阅读进度」状态栏；书籍详情页前 15 章预览列表新增实时 **`已缓存`** 翠绿徽章与 **`上次读到`** 靛蓝标识。
   - **换源 (`ChangeSourceSheet`) & 导入书源 (`ImportSourceSheet`)**：换源弹窗新增可视化搜索进度条；书源仓库预设项升级为渐变图标卡片。

## 测试与边界

- 新增并通过 `testUnsupportedNextContentUrlScriptFallsBackToGenericNextPageWithoutFailingSession`、自定义请求头白名单过滤测试、GBK 动态模板编码测试及全部 25 个内置书源规则校验。
- 在 GitHub Actions 的 iPhone Duo 与普通 iPhone 模拟器上分别运行完整单元测试与 UI 自动化测试套件，并构建校验两个未签名 IPA。

## 升级与下载

覆盖安装即可，保留书架、书源、阅读进度、缓存和原有偏好。

- `LegadoReader-unsigned.ipa`：标准 iPhone 版。
- `LegadoReader-iPhoneDuo-unsigned.ipa`：Duo 版。

两个包均未签名，按原有方式签名安装。
