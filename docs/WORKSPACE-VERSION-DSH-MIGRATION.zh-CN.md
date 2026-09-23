# Workspace、版本 Diff 与 DSH 功能域迁移

状态：第二阶段 Host/插件接缝已实施；DSH 对话流端到端待验收（2026-09-23）。

## 1. 评审结论

旧仓库中的 Workspace Platform、Resource Surface、Version Diff 和 DSH Host Plane 不是上游基座自带能力，而是 fork 基线之后增加的独立功能域。关键提交包括：

| 功能域 | 代表提交 | 可复用内容 | 不直接迁入内容 |
|---|---|---|---|
| Workspace Platform | `96b1efd4` | mount、entry、provider、路径约束、懒加载和 watch 语义 | 引用旧产品组件的 presentation |
| Resource Surface | `f9a7cc1a`、`4579dfef`、`865b934a` | engine registry、open-with、tab action 与路由语义 | 旧 Tab/Popover/主题实现 |
| Version Diff | `2a1c4e67`、`1fd9e869`、`99c97b59` | 内容寻址 blob、append-only 元数据、文本 diff、diff-as-tab | 旧 design system 和产品基座 import |
| DSH Host Plane | `e873b311`、`e268b8fc`、`68a67f01` | sidecar placement、launch URL、Workspace binding、resource open | 旧产品专用 binding 与装配名 |

迁移原则是“保留自研领域语义，重建 OpenMuse 适配和界面”。旧截图仅作为黑盒验收基线。旧产品 UI 组件、主题、品牌资产和上游业务模型不进入新运行时。独立提交与作者记录仍不能替代正式的著作权/重新许可确认，发布门禁见代码来源审计。

## 2. 功能清单

### 2.1 Workspace Resource Authority

- 多本地目录 mount；macOS 使用原生目录选择器。
- 目录优先排序、按需展开、拒绝跟随符号链接枚举。
- 打开资源、搜索、新建 Markdown、重命名、删除、Reveal、复制绝对/相对路径。
- 同一资源只保留一个主标签；标签支持关闭、关闭其他和 Pin。
- `Open With` 来自 Plugin Registry，不在 Host 中判断 Helix 或 Viewer。
- mount 列表保存到 Application Support；新产品不扫描或迁移旧 Workspace 数据。
- Project Workspace 区块、每个 mount、每个子目录分别折叠；刷新时保留已展开节点身份与状态。
- 目录菜单提供新建文件/文件夹、刷新、复制路径和移除挂载；`.sh`/`.bash`/`.zsh` 由 Helix contribution 接收。

### 2.2 版本与 Diff

- “保存当前版本”对当前 bytes 计算 SHA-256。
- blob 以内容寻址方式保存在 Application Support，不污染项目目录。
- index 采用 append-only 版本语义，原子替换元数据文件。
- 历史对话框显示时间、hash 和大小，可与磁盘当前内容比较。
- Diff 以独立标签打开，支持统一和并排视图、增加/删除统计。
- 当前实现为 Host Resource Authority 的本地服务和 Workbench Surface；下一阶段把 diff provider contribution 接到 `muse_surface_orchestrator`，Host 只保留版本授权与存储。

### 2.3 DSH

- DSH 仍是独立插件，Host 不 import sidecar 或 WebView 实现。
- 插件按需启动 DSH CLI，解析唯一的 `dsh web:` loopback launch URL。
- macOS 用插件自有 WKWebView 加载该 URL；只允许 `http://127.0.0.1` 或 `localhost`。
- Sidecar 未安装或缺少凭据时只降级右栏，不阻塞 Workspace 和编辑器。
- 已用真实 DeepSeek Harness closure 验证：sidecar 动态端口启动、token URL、WKWebView 对话/轨迹 UI 均正常。
- 发布包仍需构建最小 curated closure，不能依赖开发机旧安装目录。
- DSH 插件从 Host `workspace.snapshot` 取得挂载，写入 `muse.workspace/binding/v1` 文档和 `materialized/*.path` locator；挂载变化自动重新发布。文档不含设备路径。
- macOS WKWebView 仅接受当前 DSH loopback 主 frame、当前端口、16 KiB 以下的 `resource.open` 消息；Host 再做真实路径解析和挂载边界校验。`.diff.open` 不静默降级成普通文件打开。
- 仍需在新的、无旧产品装配名的 DSH curated closure 中接入对话 UI 的消息发射/消费，并以真实对话点击验证。当前自动同步证明的是 Host → binding 文件发布，不能宣称 DSH 运行时已经应用该文件。

## 3. 已落地的数据流

```text
NSOpenPanel
  -> Host WorkspaceMount
  -> lazy WorkspaceEntry tree
  -> OpenMuseResource
  -> Plugin Registry editorCandidates
  -> Helix PTY / PNG-PDF Viewer

resource bytes
  -> SHA-256 snapshot
  -> Application Support blob + index
  -> WorkspaceDiff tab
  -> unified / side-by-side surface

DSH Plugin
  -> Host workspace.snapshot + change notification
  -> binding v1 + private path locator
  -> spawn curated CLI
  -> parse loopback token URL
  -> readiness probe
  -> plugin-owned WKWebView
```

高频编辑、PTY 字节和 WebView 绘制不经过 Host Broker。`resource.open` 入站已经校验主 frame、loopback origin、端口、payload 大小、规范路径和 Workspace containment。`resource.diff.open` 暂拒绝，直到有可信 comparison/change 映射及独立审计。

## 4. 当前工程位置

| 能力 | 位置 |
|---|---|
| mount、tree、tab、version store | `app/openmuse_host/lib/src/host/workspace_controller.dart` |
| Workbench、上下文菜单、history、Diff | `app/openmuse_host/lib/src/host/workbench_shell.dart` |
| macOS folder picker / reveal | `app/openmuse_host/macos/Runner/MainFlutterWindow.swift` |
| editor candidates / explicit open-with | `packages/openmuse_plugin_sdk/lib/openmuse_plugin_sdk.dart` |
| DSH sidecar | `plugins/dsh-agent/lib/src/dsh_sidecar.dart` |
| DSH embedded view | `plugins/dsh-agent/lib/src/dsh_web_view.dart` 与 `plugins/dsh-agent/macos/` |
| DSH binding publisher | `plugins/dsh-agent/lib/src/dsh_workspace_binding.dart` |
| Host Workspace command authority | `app/openmuse_host/lib/main.dart` 与 `workspace_controller.dart` |

## 5. 阶段门禁

### 已通过

- Host analyze 无错误；21 项 Flutter 测试及 2 项 DSH 插件测试通过。
- macOS Debug 构建通过，原生目录选择器和两个 Native View 插件注册成功。
- 真实 Helix PTY 打开文件；切换资源复用 runtime，不再每个文件显示一次启动过程。
- macOS 安装包带 Helix 所需的 grammar/query/language runtime 与浅色 `onelight` 配置；不打包无关主题。已在桌面打开 `.sh` 并目测白色编辑画布、三栏比例、菜单卡片与顶层折叠。
- Workspace 文件/标签上下文菜单可见且路由可执行。
- 真实版本快照、修改文件、历史选择、统一/并排 Diff 端到端通过。
- PNG 和 PDF 由 open-file-viewer 正常打开，不再走 JavaScript evaluate。
- 真实 DSH sidecar 和带 token 的 Web UI 已嵌入右栏。

### 发布前仍必须通过

1. 把 DSH 最小 closure、Node runtime、OpenMuse Cordis patch 和 licenses 装入新发行包；禁止从旧 `.app` 或开发目录解析。
2. 构建 OpenMuse 专属 DSH binding consumer 与对话 UI 消息发射器；用真实 sidecar 验证挂载增删/激活同步与点击文件在 Host 打开。补 `resource.diff.open` 的可信 comparison/change 映射、TTL 与审计。
3. 将 mount persistence 补充 schema/version/损坏恢复，并添加文件系统 watch 与 debounce。
4. 将版本服务接入 authoritative `MuseResourceDescriptorV1`，补二进制/image diff provider 与大文件流式算法。
5. Windows 实现 Folder Picker、Reveal、WebView2 DSH、HWND 焦点/IME，并在真机上过等价门禁。
6. 完成签名、notarization、安装/升级、SBOM、第三方 notices 与权属确认。

## 6. 长期演进

- Workspace Provider 保持 Host 核心域；本地目录只是第一个 provider，未来 Git、只读挂载或远端投影实现同一 Resource contract。
- 版本 Diff 作为 provider/surface 插件扩展；版本写授权仍由 Host Resource Authority 控制。
- Editor、Viewer、DSH 均通过 manifest contribution 发现。Flutter 内置插件支持运行时启停；第三方真正热升级走独立进程 + Native View/WebView。
- DSH 只消费 Workspace projection 和短期 capability，不获得全盘路径或长期通用文件权限。
- 所有新菜单项由 command/contribution 声明生成，避免再次形成 Host 对具体插件名称的条件分支。
