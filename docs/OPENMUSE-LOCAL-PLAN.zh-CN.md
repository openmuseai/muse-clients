# OpenMuse Local 工程计划

状态：已按“全新独立工程”重置（2026-09-23）。

## 1. 产品边界

OpenMuse 只提供本地 Project Workspace、可扩展编辑/查看插件和可选 DSH Agent。应用无需账号即可启动；首发版本不包含云 Workspace、在线协作、分享/成员、计费或旧产品 AI。

本仓库不从旧应用派生，不继承旧数据库格式，也不提供旧 Workspace 迁移。此前基于“裁剪旧应用并重命名”的计划已经作废。

允许复用权属清晰的自研 DSH、领域中立 Muse packages 和许可证兼容的 vendor 组件。复用清单、固定提交、隔离项和发布条件见 [CODE-REUSE-PROVENANCE.zh-CN.md](CODE-REUSE-PROVENANCE.zh-CN.md)；允许复用不等于可以复制旧产品 UI 或忽略原许可证。

## 2. 架构边界

- Host：窗口、Workbench、Workspace、Resource Authority、PluginSlot、Broker、权限、审计和打包。
- Plugin：Helix、open-file-viewer、DSH、未来 Markdown/Office 引擎。
- Distribution：选择随某个产品发行版内置的插件集合。
- External Runtime：第三方生态的长期热插拔路径。

完整设计见 [PLUGIN-HOST-DSH-ARCHITECTURE.zh-CN.md](PLUGIN-HOST-DSH-ARCHITECTURE.zh-CN.md)。
Workbench 的 clean-room 高保真规格和功能对齐矩阵见 [WORKBENCH-PARITY-SPEC.zh-CN.md](WORKBENCH-PARITY-SPEC.zh-CN.md)。
Workspace、版本 Diff 与真实 DSH 的代码评审、迁移矩阵和阶段门禁见 [WORKSPACE-VERSION-DSH-MIGRATION.zh-CN.md](WORKSPACE-VERSION-DSH-MIGRATION.zh-CN.md)。
逐功能的旧代码定位、真实逻辑、新架构落点、当前差距及门禁见 [FUNCTION-PARITY-MATRIX.zh-CN.md](FUNCTION-PARITY-MATRIX.zh-CN.md)。

## 3. 首发功能

1. 免登录打开本地 Project Workspace。
2. 左侧 Workspace、中心编辑器、右侧可选 DSH 的三区布局。
3. Helix 插件打开文本/代码资源，并复用真实 PTY runtime。
4. open-file-viewer 插件查看本地 PNG/PDF。
5. 插件 Manifest、Contribution、生命周期、权限和 Host services。
6. macOS 与 Windows 安装包；未通过对应真机门禁的能力不进入发布说明。

## 4. 明确不做

- 旧 Workspace 扫描、转换或迁移。
- 登录、账号、云同步、协作、分享和成员管理。
- 把模型 Key 放进 Host 配置或日志。
- 在 Host 中硬编码 Helix、Viewer 或 DSH 页面。
- 通过改名、拆仓或移除归属声明规避第三方许可证。

## 5. 实施顺序

1. 固化协议、Manifest schema 和插件 SDK。
2. 将 Helix、Viewer、Native View、DSH 从 Host 移到独立插件包。
3. 完成三区 clean-room UI 和 Workspace 资源路由。
4. 完成 macOS NSView/WKWebView、Windows HWND/Viewer 门禁。
5. 完成 DSH curated sidecar、Workspace binding、Resource open 与 credential capability。
6. 完成外部插件进程、签名安装、热更新与回滚。
7. 完成两平台签名、安装、升级、SBOM 与第三方 notices。

## 6. 当前状态

插件包拆分、运行时注册/启停、macOS Native View、Universal Helix 真实 PTY、Viewer PNG/PDF 和 DSH 无配置降级已完成。Workbench 已接入多 mount Workspace、原生目录选择、分层折叠的资源树、`.sh` 编辑路由、文件夹菜单、内容寻址版本历史及统一/并排 Diff。版本页现在可选两个不同的已保存版本并禁止自比；打开方式由插件声明格式，扩展名默认引擎本地持久化。Helix 改为每文件 PTY/已开 Tab 会话复用，避免 `:open` 路径补全闪烁。左右面板可拖动、宽度本地持久化；设置页提供系统/浅色/深色外观，Helix 插件自己的主题、字体、字号、Keymap、LSP 开关及本地 LS 路径覆盖，Agent 插件自己的运行时状态页。右侧 DSH 面板默认展示，仅设置控制可见性；新版 DSH 不需模型 Key 即可启动，当前 macOS 中间包已提供 CLI/Node 运行时。首次安装默认 Workspace 位于应用支持目录；外部 mount 延迟扫描，不阻塞首屏。macOS 包已包含 Helix runtime 的浅色/自研深色主题与 7 个语法库，并通过临时签名及本机启动冒烟。DSH 插件已实现 Workspace binding v1 文件发布与受限的 Host 文件打开入口；新产品不读取旧产品数据库。

最新 macOS 中间包已把产品中立 DSH closure 与 Universal Node 随包嵌入，实际无 Key HTTP 启动成功；Host Mount 已通过 DSH 正式 RPC 自动登记到 workspace catalog，真实 CLI 集成测试通过。七类 LS 的本地路径/PATH 状态也已接入设置页。尚未完成：tree-sitter/LS 自动安装与更新、完整深色主题跨 WebView 像素验收、DSH 当前工作区双向选择与 binding receipt、对话流文件打开端到端、closure 缩减与完整许可/SBOM 审核、Windows 真机、正式签名/公证及像素/无障碍验收。这些仍是独立工程门禁，不能把 HTTP 200 或临时签名包等同于发布验收。
