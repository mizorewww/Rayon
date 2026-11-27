# Rayon 架构全面审查与去轮子演进规划

> 对照基准：`../FlowDown` 的依赖选型、基础设施划分与跨平台工程实践  
> 核心目标：卸下历史兼容包袱（允许 UI、数据格式与交互行为的 Breaking Change），系统性清除自造轮子，建立克制、现代、可演进的架构。

---

## 一、 核心演进逻辑与设计哲学

### 1.1 现状病灶：为什么 Rayon 会变得沉重且脆弱？

审视当前仓库，几乎所有复杂度都源于同一个反模式循环：

1. **排斥成熟垂直库，习惯性手搓底层基础设施**：全仓除 `GhosttyKit`、`DisplayLink` 和仅限 iOS 编译的 `Runestone` 外，从关系数据存储、增量云同步、双端表单/弹窗/通知组件、macOS 代码编辑器语法高亮，到 SSH 事件循环、SOCKS5、Protobuf、Gzip、RTP 视频组包乃至 WebRTC 宿主，全部选择了手写实现。
2. **用胶水与轮询掩盖手造轮子的缺陷**：因为手造的底层缺乏完备的状态机与系统集成能力，上层被迫引入大量脆弱补丁——例如用 `UserDefaults` 存全量加密 Blob 导致卡顿，于是再手搓 `1.5s` 防抖写队列和双份锁镜像；不用原生导航生命周期而把所有页面放进 `.opacity(0)` 巨型 `ZStack`，于是再造一套 `isActivePage` 环境变量去阻止隐藏页抢占 Toolbar；不引入原生 WebRTC 库，于是往窗口塞一个 `1×1` 隐藏 `WKWebView` 靠 Base64 字符串跨进程传 4K 视频帧。
3. **双端工程割裂与历史包袱叠加**：`Application/mRayon` 保留着未清理的 Mac Catalyst 配置，却又另起炉灶新建了 `Application/Rayon` 纯 macOS 工程，导致超过一万四千行高度同构的业务视图与状态逻辑被平行抄写两遍，并在演进中产生大量双端校验与安全行为分叉。

### 1.2 目标设计哲学（对齐 FlowDown 工程范式）

后续重构遵循以下五条核心原则：

1. **持续去轮子原则（Buy / Adopt over Hand-Roll）**
   - Rayon 的核心产品价值在于 **服务器连接工作流（终端、文件、监控、桌面）的无缝协同体验**，而非自己实现数据库、同步协议、富文本排版引擎或通用弹窗框架。
   - **全局推进准则**：不仅限于本文档已列出的模块，**在后续改动的任何环节，只要发现仓库内存在自造轮子（如自定义解析器、手写锁队列、自定义动画/布局容器、手搓协议封装、手写系统桥接胶水），且 Apple 原生框架、FlowDown 已有依赖库或社区已有成熟实现，一律停止维护旧轮子并直接迁移至成熟方案。**
2. **单一事实来源与单一跨端工程（Single Source of Truth）**
   - 终结两套 App Target 双轨维护。与 FlowDown 一致，用单一主工程配合极薄的平台适配层（Platform Support）承载全平台体验；用连续的窗口几何特征（宽度阈值、紧凑/宽松态）驱动自适应布局，而不是按 `#if os(macOS)` 复制整套业务页面。
3. **顺应平台原生语义，拒绝反原生自绘**
   - 归还系统级组件（侧边栏、可排序/可调列宽表格、菜单、选择器、工具栏搜索、菜单栏响应链快捷键、Dynamic Type 动态字号），废除为追求表面样式统一而动用未公开私有 SPI 或无滚动 Popover 的反原生封装。
4. **以结构化并发与强类型契约取代逃生舱与哨兵值**
   - 用关系型数据库表约束、强类型 `UUID?` 外键与标准 `Optional` 取代字符串拼接关联、`[String: String]` 杂物袋字典与每次构造随机 UUID 空对象的 `RDGroup` 哨兵模式。
   - 用 Swift 6 原生 `@MainActor`、`actor` 与事件驱动 I/O 取代常驻 `NSThread`、`usleep` 忙等以及全仓泛滥的 `@unchecked Sendable` / `nonisolated(unsafe)`。
5. **清晰的边界隔离与破坏性减负**
   - 明确切断复杂的第三方私有协议耦合：将 **UU 远程** 完整剥离至独立的全新 GitHub 仓库，作为纯正的外部 Swift Package 库维护和引入。
   - 充分利用 Breaking Change 窗口，彻底删除多代历史加密格式、旧 Bundle ID 跨沙盒硬编码迁移、旧 `attachment` 字段兼容解码等死重代码。

---

## 二、 架构重构规划：要怎么做

### 2.1 UU 远程独立建仓：拆分为独立 GitHub 仓库并彻底库化

UU 远程（当前位于 `Foundation/RayonModule/Sources/RayonModule/RemoteDesktop/UURemote/`，共 17 个文件近 7,800 行）本质上是一套独立的远程控制与流媒体客户端协议栈，不应寄生在 SSH 核心模块 `RayonModule` 中，也不应反向依赖 `RayonStore`、`RDMachine` 或宿主 UI。

- **边界拆分与职责定义**：
  - 新建独立 GitHub 仓库（例如 `UURemoteKit`），以标准 Swift Package 形式提供给 Rayon 引用。
  - 库内只负责纯粹的领域能力：账号认证与凭证生命周期管理（通过注入的 Keychain/Storage 协议持久化，不触碰宿主 `UserDefaults`）、设备列表与在线状态同步、房间信令连接、桌面音视频流与键鼠剪贴板控制、远端终端通道、TCP 端口映射流。
  - Rayon 主仓仅保留极薄的适配器：将 `UURemoteKit` 的设备映射为侧边栏数据源，将其桌面流接入统一的远程桌面画布，将其终端流与端口映射流接入终端和 SSH 传输层。
- **新仓库内部的同步去轮子**：
  - 独立建仓不是简单搬运旧代码，而是趁拆分消除其内部最恶劣的几个手造轮子：用原生 **WebRTC SDK** 取代“隐藏 `1×1 WKWebView` + JS Base64 字符串跨进程传视频帧与数据通道”的畸形架构，直接走原生 `RTCDataChannel` 与 `CVPixelBuffer` / Metal 硬件渲染；用 **`swift-protobuf`**（定义清晰的 `.proto` 文件生成代码）取代手写 `UURemoteProtobuf.swift` 及上千行魔法字段号拼装代码；用系统 `Compression` 框架取代手写裸指针 `zlib` Gzip 封装。

### 2.2 跨平台应用层收敛：终结 `Rayon` / `mRayon` 双工程

- **工程合一**：参考 FlowDown 单一工程结构（UIKit/SwiftUI + Mac Catalyst 配合 `FLDCatalystHelper` 注入 macOS 原生毛玻璃材质与窗口拖拽缩放，或单一 SwiftUI Multiplatform Target），废除双工程平行开发模式，消除 `TerminalManager`、`EditorWorkspace`、`UIBridge`、服务器编辑页、终端页、文件传输页、设置页在多处重复定义的现状。
- **状态与交互收拢**：服务器、凭据、端口转发、代码片段的编辑校验统一收敛为单一可观察领域模型，根除双端端口校验不一致、输入纠错不一致以及 macOS 查看明文密码缺少生物识别认证（Touch ID / LocalAuthentication）的安全缺口。
- **壳层生命周期正常化**：拔除 `MainView` 中把所有页面同时塞进 `ZStack` 靠 `.opacity(0)` 隐藏的做法及配套的 `isActivePage` 补丁。仅按需保活活跃终端渲染实例，其余功能页遵循系统标准导航挂载与销毁生命周期；全局快捷键统一收归系统菜单栏响应链，删除散落各页面的 `.opacity(0)` 隐形按钮。

### 2.3 存储、凭据与备份体系重构：迁入 `WCDBSwift` + 系统 Keychain + `ZIPFoundation`

直接借鉴 FlowDown `Frameworks/Storage` 的成熟设计，推翻现有的 `RayonStore`（`UserDefaults` 整包加密 Plist）：

- **关系型存储与版本化迁移**：引入 **`Lakr233/wcdb.xcframework` (`WCDBSwift`)**、**`BetterCodable`** 与 **`swift-collections` (`OrderedCollections`)**，为服务器、凭据元数据、文件夹、代码片段、端口转发、KnownHosts、最近连接建立独立数据表与索引，采用 SQLite `PRAGMA user_version` 单步迁移机制管理 Schema 演进。
- **数据模型规范化（Breaking Schema Cleanup）**：
  - 移除反直觉的 `RDGroup` 空哨兵对象协议，所有按 ID 查询统一返回标准 `Optional`；
  - 将文件夹从按名称字符串（`machine.group`）弱关联改为按强类型主键 `folderId: UUID?` 关联；
  - 将 `associatedIdentity`、`proxyJumpMachineID` 等外键统一为强类型 `UUID?`，并在模型层内置跳板链有向图环检测；
  - 将塞在 `attachment: [String: String]` 里的业务属性提升为显式强类型列，彻底移除 `attachment` 字典与两百余行历史兼容编解码代码。
- **敏感凭据与业务数据分离**：私钥、密码、Cloudflare Service Token 等机密材料统一存入开启 `kSecUseDataProtectionKeychain` 的系统钥匙串模块，数据库仅存元数据与引用 ID；彻底删除维护了三代加密格式和硬件序列号密钥的 `AES.swift`、独立的 `Foundation/Keychain` 旧包、防抖写队列 `DeferredStoreWrites` 以及双份内存锁镜像 `WorkerState`。
- **备份与恢复重构**：参考 FlowDown 的 `Storage+Export` 与 `SettingsBackup`，使用 **`ZIPFoundation`** 实现数据库快照压缩导出与临时目录预迁移校验导入（支持可选标准密码加密，杜绝当前默认导出明文私钥 JSON 的隐患），并将业务数据备份与应用偏好设置备份解耦。

### 2.4 云端同步重构：以 `CKSyncEngine` 取代 KVS 单键全量包

整体删除 `Foundation/RayonModule/Sources/RayonModule/Sync/` 下近两千行的手搓同步引擎，直接迁入 FlowDown 验证成熟的 **`CKSyncEngine`** 同步架构：

- **记录级增量同步**：基于 CloudKit 自定义 Zone、`UploadQueue` 与 `SyncMetadata`（持久化系统字段与 ETag）按单条记录增量上下行。记录 JSON 与密钥都以 `encryptedValues` 内联保存（`CKAsset` 不做端到端加密，故不使用）；超过单条 CloudKit 记录上限（约 768 KB 内联阈值）的记录拒绝上传并记录日志，彻底告别 `NSUbiquitousKeyValueStore` 1MB 总配额上限与整包覆盖丢更新问题。
- **原生免口令端到端加密**：直接使用 CloudKit `encryptedValues`（底层由系统托管于 iCloud Keychain 实现端到端加密），删除全部自定义信封（`SyncEnvelope`）、60 万轮 PBKDF2 口令派生、30 秒钥匙串轮询以及全套同步口令弹窗 UI（`PassphraseSheet`），交互简化为“一键开启 iCloud 同步 + 同步范围开关（Sync Scope）”。
- **隔离设备形态相关偏好**：停止在手机与桌面端之间同步终端字号、窗口内边距等强绑定屏幕尺寸的本地显示参数。

### 2.5 设置、设计系统、代码编辑器与终端配置器瘦身

- **设置体系迁入 `ConfigurableKit` 并反转控制权**：
  - 解除 `RayonTerminal` 中 `GhosttyConfigurationView` 对主应用设置页的反向劫持，由宿主应用主导顶层设置导航。
  - 引入 FlowDown 使用的 **`ConfigurableKit`** 单点管理应用偏好键、默认值、变更订阅与声明式设置行，消除 `@AppStorage`、`RayonStore.didSet` 与手动通知混用的乱象，修正 `disableConformation` 等历史拼写错误。
- **Ghostty 终端配置器重构（保留全部设置项）**：
  - 重写移植自第三方网页生成器的配置 UI 与 309 行内存假 Shell 模拟器（`ConfigSandbox.swift`），但**不删除任何设置项**：全部设置、分类、明暗主题、调色板、快捷键、搜索与重置均保留。
  - 改用原生表单控件与单一数据驱动模型，尽量使用 `libghostty-spm` 自带的主题、配置解析与校验能力；颜色选择统一使用 `Lakr233/BlossomColorPicker`；预览直接挂载真实的只读 `RayonTerminalView` 渲染固定 ANSI 样例（真实呈现连字与字体加粗效果）；配置以 `config.ghostty` 持久化。
  - 移除每次 SSH 收包持锁拷贝 256KB 字符串的 `TerminalOutputBuffer`，对接终端底层真实的离屏缓冲区搜索与视口跳转高亮。
- **统一 Tree-sitter 代码编辑器**：
  - 删除 `RayonEditor` 中 macOS 分支手写的 TextKit 1 行号尺与每次按键主线程跑 4 遍全文正则的 `MacSyntaxHighlighter`。
  - 对齐 FlowDown 直接采用预编译跨端 **`Lakr233/Runestone.xcframework`**（或在纯 AppKit 目标下采用成熟的 Tree-sitter 编辑器组件如 `CodeEditSourceEditor` / `STTextView`），实现双端一致的增量语法树高亮与大文件流畅滚动。
- **UI 组件库与系统原生控件归位**：
  - 引入 FlowDown 同款 **`Lakr233/AlertController`** 与 **`SPIndicator`**，彻底替换双端 `UIBridge`、`0.1s Timer` 弹窗轮询队列、40 字符错误截断与悬空 `UIHostingController`；不引入 `Lakr233/UIEffectKit`：它提供的是 Metal 碎玻璃/粒子爆散转场与点阵闪光装饰（FlowDown 仅在模型详情卡片用了 `ShimmerGridPointsView`，`Indicator.swift` 并不依赖它），与弹窗通知无关，Rayon 也没有它能替换的手写特效（窗口毛玻璃已是系统 `NSVisualEffectView`，Home 背景另有方案）；
  - Home 保留原有的光晕与漂浮光点背景（用户要求视觉不变；曾试用 `Lakr233/ColorfulX` 后撤回），由 `TimelineView` + 异步渲染的 `Canvas` 绘制，离屏、后台、减弱动态效果与低电量模式时暂停；
  - 用系统原生 **`Swift Charts`** 替换手绘 `Sparkline` / `UsageBar`；
  - 用原生 `Table`（支持列宽调整、表头排序、键盘导航与多选）、原生 `Picker`/`Menu`、语义化动态字号替换 `RayonDesign` 中的伪表格与无滚动 Popover，重写或替换损坏的 `SymbolPicker`；
  - 菜单栏监控必须复用 `MonitorCenter` 共享会话，消除对同一服务器的双倍 SSH 连接。

### 2.6 SSH 协议栈、本地终端、VNC 与服务器监控现代化

- **用现代纯 Swift 异步 SSH 栈替换 `NSRemoteShell` + `CSSH.xcframework`**：
  - 引入 **`swift-nio`（与 FlowDown 同生态）+ `swift-nio-ssh` / `Citadel` + `NIOTransportServices`（底层基于 Apple `Network.framework`）**，彻底淘汰 2021 年编译的 `libssh2 1.10.0` 静态库与近 4,500 行 Objective-C 轮询封装。
  - 所有交互式 Shell、SFTP、本地/远程端口转发、动态 SOCKS5、多跳 ProxyJump 以及 Cloudflare Access WebSocket 隧道统一运行在事件驱动的非阻塞 ChannelPipeline 与 Swift Concurrency 背压模型之上，消除每实例常驻 `NSThread`、`0.1s NSTimer`、`usleep(800)` 忙等、`socketpair` 中转线程以及 `NSActivityLatencyCritical` 功耗黑洞。
  - 补齐首次连接未知主机时的交互式主机密钥指纹确认流程，准确透传远端命令退出码，并为批量代码片段执行增加受控并发度（TaskGroup 限流）。
- **本地终端改为安全进程派生**：用 `openpty` + `posix_spawn` 替换在多线程 GUI 进程中极易死锁崩溃的 `forkpty()`。
- **VNC 客户端加固与去轮子**：用 `NWConnection` / `NWBrowser` 替换手写 BSD Socket（`VNCSocket`）与废弃的 `NetServiceBrowser`，用系统 `Compression` 框架并加上严格输出上限替换无边界的 `VNCZlibStream`，消除主线程阻塞 `send`；修复认证降级与 DH 公钥边界校验。
- **服务器监控采样与渲染减负**：
  - 将客户端改为缓存上一轮计数器快照并做跨轮次差分（废除每轮远端硬 `sleep 1` 与 macOS `top -l 2`），探明无 NVIDIA GPU 或 Darwin 系统后缓存能力标记不再每轮盲跑 `nvidia-smi`，统一注入 `LC_ALL=C`，用 `UInt64` 解析 `/proc/stat`；
  - `MonitorSession` 改为单轮采集完成后一次性发布不可变的 `MonitorSnapshot`，将每次刷新的视图重算从 8~10 次压缩为 1 次。

### 2.7 工程基建、日志、更新、国际化与 CI 门禁（全面复刻 FlowDown 基建）

- **统一构建入口与配置分层**：建立根目录 `Makefile` 与分层 `Configuration/*.xcconfig`，移除散装构建脚本对仓库内 `./DerivedData` 的污染，清理 `External/XTerminalUI` 空目录与失效的 `submodule.sh`，全仓统一升级至 Swift 6 工具链与语言模式，清除 `OnMainThread.swift` 等并发逃逸包装。
- **日志与自更新**：直接迁入 FlowDown 的 `Frameworks/Logger`（`os.Logger` + `LogStore` 滚动文件日志 + 日志查看器）替代 `LogRedirect.swift`；迁入 FlowDown 基于 **`DpkgVersion`** 的 `UpdateManager`（自动识别 App Store 与 GitHub 直发渠道）。
- **国际化与开源合规自动化**：建立 `Localizable.xcstrings` 多语言目录并引入 FlowDown `Resources/DevKit/scripts/` 下的翻译完整性检查与死键清理脚本；引入 `scan.license.sh` 从 `Package.resolved` 自动生成准确的开源许可证列表并拦截传染性协议。
- **建立真实 CI 门禁**：在 GitHub Actions 中补齐 macOS / iOS 构建与测试流水线，并将自动合并脚本强制绑定在真实 CI 通过状态之上。

---

## 三、 去轮子与成熟实现迁移对照总表

| 所属范围 | 当前手造轮子 / 不当实现 | 目标成熟依赖库 / 系统原生方案 | 参考来源 |
| :--- | :--- | :--- | :--- |
| **Rayon 存储层** | `RayonStore` `UserDefaults` 加密 Plist、`DeferredStoreWrites`、`WorkerState`、`RDGroup` | `WCDBSwift` (`Lakr233/wcdb.xcframework`) + `BetterCodable` + `OrderedCollections` | FlowDown `Frameworks/Storage` |
| **Rayon 凭据与加密** | `AES.swift`（含三代格式与硬件序列号密钥）、`Foundation/Keychain`、`SyncKeychain` | 系统 `Security` (`kSecUseDataProtectionKeychain`) + 原生 `CryptoKit` | Apple 原生框架 |
| **Rayon 备份归档** | 双端重复且默认明文导出私钥的 `BackupArchive` JSON | `ZIPFoundation` + 原子数据库导出/预迁移校验 + `SettingsBackup` | FlowDown `Storage+Export` |
| **Rayon 云端同步** | `Sync/*`（KVS 1MB 单键整包、自定义信封、PBKDF2 口令、30s 轮询） | `CKSyncEngine` + `CKRecord.encryptedValues`（内联加密，带大小上限；不用 `CKAsset`） | FlowDown `Storage/Sync` |
| **Rayon 设置管理** | 4 套 `UserDefaults` 混写 + 双端手写设置页 + `GhosttyConfigurationView` 劫持 | `ConfigurableKit` (`Lakr233/ConfigurableKit`) | FlowDown `Value+*.swift` & `SettingController` |
| **Rayon 代码编辑器** | macOS 手写 `LineNumberRulerView` + 主线程全文 4 遍正则 `MacSyntaxHighlighter` | `Lakr233/Runestone.xcframework`（或 AppKit 下 `STTextView` / `CodeEditSourceEditor`） | FlowDown `CodeEditorController` |
| **Rayon 弹窗与通知** | 双端 `UIBridge`、`DoubleConfirm`、`0.1s` 轮询 `PresentationQueue`、40 字截断 Toast | `Lakr233/AlertController` + `SPIndicator` | FlowDown `Indicator.swift` |
| **Rayon 通用控件与表格** | `RayonDesign`（私有 `_VariadicView`、无滚动 `RXPicker`/`RXMenuButton`、假表头 `FileTable`、旧 `SymbolPicker`） | 原生 `NavigationSplitView`、`Form(.grouped)`、`Table`、`Picker`、`Menu`、`ListViewKit` | Apple 原生框架 / FlowDown |
| **Rayon 图表与动效** | `Charts.swift` 手算折线 `Path`、`Welcome.swift` CPU 30fps `RXStarfield`、菜单栏 20Hz `Timer` | 原生 `Swift Charts` + `TimelineView`/`Canvas`（Home 背景保持原样）+ `Lakr233/DisplayLink` | Apple 原生框架 / FlowDown |
| **Rayon 终端配置预览** | 4,304 行网页移植配置器 + `ConfigSandbox.swift` 309 行内存假 Shell | 保留全部设置项的原生数据驱动配置器 + `BlossomColorPicker` + 真实只读 `RayonTerminalView` 预览 + `config.ghostty` | `libghostty-spm` 原生能力 |
| **Rayon SSH 网络栈** | `External/NSRemoteShell` (ObjC `NSThread` + `usleep(800)`) + 2021 年 `CSSH.xcframework` | `swift-nio` + `swift-nio-ssh` / `Citadel` + `NIOTransportServices` (`Network.framework`) | FlowDown 已用 `swift-nio` 生态 |
| **Rayon VNC 网络与压缩** | 手写 BSD `VNCSocket`、废弃 `NetServiceBrowser`、手写无上限 `VNCZlibStream` | `Network.framework` (`NWConnection` / `NWBrowser`) + 系统 `Compression` 框架 | Apple 原生框架 |
| **Rayon 日志与更新** | iOS 独占 `dup2` `LogRedirect.swift`、无自更新检查 | FlowDown `Frameworks/Logger` (`os.Logger` + `LogStore`) + `DpkgVersion` (`UpdateManager`) | FlowDown `Logger` & `UpdateManager` |
| **新仓 `UURemoteKit`** | 隐藏 `1×1 WKWebView` JS Base64 传视频与数据、手写 `UURemoteProtobuf`、裸 `zlib`、手写 RTP 组包 | 原生 `WebRTC.xcframework` + `apple/swift-protobuf` + 系统 `Compression` 框架 | 社区成熟标准库 |

---

## 四、 全仓已发现的 Bug、安全漏洞与并发隐患记录

以下问题均已在当前源码中核实，重构与替换轮子过程中需逐一确保根除或回归验证：

### 4.1 存储、数据模型与云同步 Bug

1. **新建动态 SOCKS5 (`-D`) 端口转发被静默丢弃**
   - `PortForwardView.swift` 在选择 `.dynamicSOCKS` 时隐藏目标地址与端口输入（`targetPort == 0`），`RDPortForward.isValid()` 返回 `true` 允许点击保存；但 `RDPortForwardGroup.accepts(_:)` 硬编码要求 `item.targetPort > 0`，导致保存操作被 `RDGroup.insert` 静默吞没。
2. **`ProxyJump` 环形跳板配置引发无限递归栈溢出崩溃**
   - `RDMachine.getCommand()` 在拼接跳板机命令时递归调用跳板机的 `getCommand()`，缺少 `visited` 集合环检测；若两台服务器互指对方为跳板机，UI 渲染命令预览时直接栈溢出 Crash。
3. **应用退出丢失最后 1.5 秒内的存储变更**
   - `RayonStore` 防抖写队列仅监听了 `willResignActiveNotification`，未监听 `willTerminateNotification`；当应用在后台或 macOS 菜单栏 `.accessory` 模式下退出时，尚未派发落盘的写入直接丢失。
4. **`RayonStore` Release 模式下存在无锁并发写字典崩溃风险**
   - `RayonStore` 标记为 `@unchecked Sendable`，但其主线程写断言 `storeWritePrecondition()` 仅在 `#if DEBUG` 下生效，Release 模式下若后台回调误触写入将直接并发读写 `DeferredStoreWrites.pending` 字典；且 `flush()` 遍历无序字典违背了注释承诺的按序落盘语义。
5. **新设备开启云同步盲等 3 秒可能导致云端数据被空库覆盖**
   - `CloudSync.switchOn()` 在本地未读到 KVS 数据时仅靠 `Task.sleep(3s)` 等待 `cloudd` 推送，弱网超时后会将云端视为空库并上传新快照覆写。
6. **云同步上传超限失败前已提前提交本地 `SyncState`**
   - `CloudSync.finish()` 先更新本地 `state = done.state` 再调用 `transport.write(upload)`；一旦触发 KVS 1MB `.tooLarge` 错误，本地同步水位线与删除记录已被污染，后续无法恢复一致。
7. **备份导出默认明文暴露全部 SSH 私钥与密码**
   - macOS 与 iOS 的备份 UI 均未接入导出密码参数，生成的 JSON 明文包含所有私钥与口令；而 `importBackupData` 在用户密码解密失败时还会错误回退尝试本机主密钥解密。

### 4.2 SSH、端口转发、本地终端与加密安全隐患

8. **静态内置 2021 年 `libssh2 1.10.0`，受 Terrapin 前缀截断攻击（CVE-2023-48795）影响**
   - `External/NSRemoteShell/External/CSSH` 二进制停留在 `1.10.0`，缺乏 `strict KEX` 修复。
9. **端口转发与跳板机通道在高吞吐/背压下必断流，且存在远端通道泄漏**
   - `NSRemoteChannelSocketPair.m` 在非阻塞 socket 上遇到发送缓冲区满返回 `-1 (EAGAIN)`，或遇到 `libssh2_channel_read == 0`（非 EOF 空包/窗口调整）时，均直接判定连接完成并强行断开转发；而本地对端正常关闭（`recv == 0`）时却漏判 EOF，导致远端 SSH `direct-tcpip` 通道一直挂死。
10. **端口转发不支持自动认证身份（Auto Auth），引发每 3 秒无限重连死循环**
    - `PortForwardContext.runRound()` 只读取机器绑定的单一 `associatedIdentity`，未像终端和 SFTP 那样回退尝试全局自动认证身份列表，导致依赖自动认证的服务器开启转发后永久死循环报错重连。
11. **`NSRemoteShell.beginExecute` 失败或超时默认返回退出码 `0`，导致公钥部署与批量脚本误报成功**
    - `exitCode` 初始值为 `0`，通道打开失败、命令超时中断或远端未发 `exit-status` 时均返回 `0`；`PublicKeyDeployment` 据此误判公钥写入成功并直接改绑服务器身份，批量代码片段执行更是完全忽略返回码一律显示成功。
12. **本地终端在多线程 GUI 进程中调用 `forkpty()` 后执行 ObjC 与非异步信号安全代码**
    - `TerminalContext+Local.swift` 在 `forkpty()` 子进程内调用了 `NSUserName()`、`NSString`、`setenv()`、`strdup()`，一旦父进程其他线程正持有 malloc / ObjC runtime / environ 锁，子进程将永久死锁或崩溃。
13. **每个 `NSRemoteShell` 无条件泄漏常驻线程与 10Hz 定时器，批量执行无并发上限**
    - `TerminalContext` 属性默认初始化 `NSRemoteShell()`，连本地终端与 UU 终端也会空跑一个 `NSThread` + `0.1s NSTimer`；批量脚本执行对所有目标服务器一次性全量创建连接并阻塞等待信号量，服务器较多时可耗尽 GCD 线程池。
14. **`KnownHosts` 首次连接静默信任（盲目 TOFU），macOS 查看明文密码缺少鉴权，DEBUG 下用硬件序列号做加密密钥**
    - 首次连接陌生主机无指纹确认交互；macOS `IdentitiesView` 无需 Touch ID 即可查看明文密码；`AES.swift` 在 macOS DEBUG 构建下直接用 `IOPlatformSerialNumber` 派生密钥。

### 4.3 远程桌面（VNC / UU 远程）漏洞与缺陷

15. **VNC 存在无条件认证降级高危漏洞（Authentication Downgrade）**
    - `VNCRFBClient.chooseSecurityType` 只要见到服务端列表包含 `SecurityType.none` 就无条件优先选用，哪怕用户已为该服务器配置了密码，中间人也可诱导客户端跳过认证直接连入。
16. **VNC ZRLE 解压存在无上限内存膨胀（Zip Bomb OOM）与主线程阻塞发送**
    - `VNCZlibStream.inflate` 未限制输出上限，恶意压缩帧可耗尽客户端内存；`VNCAppleAuth` 自写大整数模幂非恒定时间且未验证服务端 DH 公钥合法区间 `1 < Y < p - 1`；所有鼠标键盘事件在主线程同步调用阻塞 `send`；`VNCSocket` 释放锁后调用 `recv` 与 `close` 存在文件描述符重用竞态，`VNCSSHTunnel` 选端口存在 `bind(0)` 后先关闭再重绑的 TOCTOU 竞态。
17. **UU 远程 `WKWebView` 强引用泄漏隐患与端口映射流竞态**
    - `UURemoteDriver` 中 `WKUserContentController.add(self, name: "rtc")` 强持有委托，异常路径未调用 `detach()` 时将永久泄漏整个 WebKit 子进程；`UURemotePortMapping` 手工字符串插值拼 JSON 未做转义，且流关闭与读取线程间存在 fd 竞态。

### 4.4 服务器监控、UI 交互与 CI 缺陷

18. **服务器监控使用 32 位 `Float` 解析 `/proc/stat` jiffies，长运行服务器 CPU 读数失真归零**
    - 单精度 `Float` 仅能精确表示 $2^{24}$（约 1,677 万）以内整数，多核 Linux 服务器运行数十分钟至数天后，`idle` 累加值精度步长超过单秒增量，导致 CPU 使用率归零或剧烈跳变；且重复计入了 `guest` 时间。
19. **磁盘分区 100% 写满时从监控界面直接消失**
    - `ProcParsers.parseDfPk` 过滤条件写为 `guard mount.hasPrefix("/"), free > 0`，当生产服务器根分区真正写满（`free == 0`）时，该分区反而被解析器丢弃隐藏；此外采集脚本未注入 `LC_ALL=C`（非英语 Locale 下小数点解析失败），断连空输出还会写入历史曲线造成假归零尖峰。
20. **编辑器、终端搜索、菜单栏与弹窗组件交互 Bug**
    - `RayonEditor` macOS 版用大杂烩关键字正则把 Markdown/HTML 正文常见英文介词染成代码关键字，把 CSS `url(https://...)` 染成注释；
    - 终端页 `⌘F` 搜索栏仅统计纯文本缓冲匹配次数，不支持终端视口滚动定位与高亮；
    - `SymbolPicker` 在 macOS 点击图标立即写入外部绑定，点击 Cancel 按钮不回滚；
    - `mRayon` 错误提示被硬截断为 40 个字符，且局部变量创建的 `UIHostingController` 立即释放留下悬空孤儿视图；
    - macOS 菜单栏状态项未复用 `MonitorCenter` 会话，开启菜单栏监控会对同一台机器建立双份 SSH 轮询连接；
    - iOS 日志页分享诊断日志时将整个无大小上限的日志文件读入系统剪贴板。
21. **仓库完全没有编译与测试 CI，却开启了 AI 审批后自动 Merge**
    - `.github/workflows/` 下无任何编译或测试任务，但 `pr-review.yml` 提示评审模型“有 CI 兜底验证”，`pr-merge.yml` 则在审批通过后零验证直接自动合入默认分支；同时 `Resources/LICENSE` 漏声明实际分发的 `Runestone` 与 `TreeSitterLanguages` 许可证。
