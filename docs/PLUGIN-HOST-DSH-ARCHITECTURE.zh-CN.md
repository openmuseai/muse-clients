# OpenMuse Host / Plugin / DSH 总体架构

状态：V1 架构基线与工程验证（2026-09-23）

## 1. 决策摘要

OpenMuse 是一个全新、独立的本地优先工程，不继承旧应用的数据模型、数据库或运行时代码。产品由一个稳定 Host 和若干自治插件组成：

- Host 只负责桌面窗口、三区 Workbench、Workspace 资源目录、插件发现与生命周期、Native View 容器、平台 Broker、权限与审计。
- Helix 是编辑器插件，拥有 PTY、进程池、终端 UI 和编辑会话。
- open-file-viewer 是 Viewer 插件，拥有文件类型路由和 WKWebView/未来 WebView2 适配器。
- DSH 是右侧面板插件，拥有 sidecar 生命周期、DSH UI、Workspace binding 和 Agent 上下文投影。
- NSView/HWND 是 Native View 插件门禁，不属于产品 Host 的业务页面。
- Host 与插件之间分离 View Plane、Control Plane 和 Data Plane；高频绘制/输入不走 Broker。
- V1 的 Flutter 插件是“编译期装配、运行时启停”；真正可安装、可升级、无需重启的第三方插件必须使用独立进程 Runtime。

`openmuse-workspace-migrator` 不属于本工程。新产品不扫描、不解释、不迁移旧产品 Workspace。

## 2. 法律与 clean-room 边界

新仓库和新包名本身不会消除第三方许可证义务。为了让新工程保持独立边界，实施规则是：

1. 不复制旧 fork 基线或无法证明独立权属的 Dart、Rust、Swift、C++、TypeScript 源码；允许迁入来源清单中权属清晰的自研 Muse/DSH 代码。
2. 不复制旧产品的图标、字体文件、插画、品牌文案和主题资源。
3. UI 对齐以运行中产品的黑盒观察、截图尺寸和交互验收表为输入，用新组件和新 design token 重建。
4. 自研协议、Resource/Engine/Surface 状态机可按固定提交直接复用；其他协议只复用思想和事实，不复制无法确认权属的表达性实现或注释。
5. 每个引入的第三方引擎单独保留许可证、固定版本、来源和 SBOM；Helix 按 MPL-2.0 管理。
6. 旧仓库顶层采用 AGPL；只有著作权人拥有并明确重新许可的独立贡献才能走非 AGPL 复用路径。若复用上游或其他 AGPL 源码，则应按 AGPL 路线合规发布，不可依赖“改名”或“拆仓”规避。

文件级来源、固定提交和隔离清单见 [CODE-REUSE-PROVENANCE.zh-CN.md](CODE-REUSE-PROVENANCE.zh-CN.md)。

本文件是工程边界说明，不代替法律意见。发布前仍应由法律顾问确认依赖清单与分发方式。

## 3. 目标系统

```text
┌──────────────────────────── OpenMuse Desktop ────────────────────────────┐
│                                                                         │
│  Host Shell                                                             │
│  ┌──────────────┬──────────────────────────────┬──────────────────────┐ │
│  │ Workspace    │ Editor PluginSlot            │ Right PanelSlot      │ │
│  │ Explorer     │                              │                      │ │
│  │              │ Helix / Viewer / future      │ DSH Agent Plugin     │ │
│  └──────────────┴──────────────────────────────┴──────────────────────┘ │
│          │                   │ Native View                     │          │
│          └───────────────────┴─────────────────────────────────┘          │
│                              │                                            │
│  Platform Broker: Command / Event / Service / Context / Capability       │
│  Resource Authority: resourceRef / permission / revision / lease         │
│  View Manager: attach / detach / bounds / visibility / focus             │
└──────────────────────────────┬────────────────────────────────────────────┘
                               │ IPC / PTY / loopback capability
          ┌────────────────────┼─────────────────────┐
          │                    │                     │
     Helix process        DSH sidecar          future plugin process
```

### 3.1 Host 的最小职责

Host 必须拥有：

- 应用窗口、菜单、三区布局、响应式尺寸和主题 token；
- Project Workspace 与 Mount 的抽象资源树；
- `resourceRef` 的解析、授权、revision、lease 与物化；
- Plugin Catalog、Contribution Registry、激活/停用/卸载；
- PluginSlot 与平台 Native View 的 attach、bounds、z-order、focus；
- Command、Event、Service、Context、Capability Broker；
- 用户可见权限、超时、取消、审计和崩溃隔离；
- 安装包装配、签名、第三方 notices 与完整性校验。

Host 不应拥有：

- Helix 的 PTY、终端、命令转义和进程池；
- PNG/PDF 的渲染器或格式判断实现；
- DSH CLI 参数、模型凭据、聊天 UI 和 sidecar 日志；
- DOCX、PDF、代码等格式内部模型；
- 插件逐帧绘制、IME 合成、Selection 和 Cursor 状态。

## 4. 仓库分层

```text
Muse-Client/
├── app/openmuse_host/                 # 纯 Host shell 与平台 Runner
│   └── lib/src/host/
├── packages/openmuse_plugin_sdk/      # Flutter-facing 插件兼容层
├── packages/muse_resource_contract/  # Resource/Presentation/Session wire contract
├── packages/muse_engine_adapter/      # Engine adapter registry/router
├── packages/muse_engine_tck/          # adapter conformance kit
├── packages/muse_resource_bridge/     # Host Bridge 与 materialization policy
├── packages/muse_surface_orchestrator/# Surface 生命周期与回滚
├── packages/muse_*_surface/           # Helix/Viewer/Office adapter 合同
├── crates/openmuse-plugin-protocol/   # 语言无关 wire contract
├── crates/openmuse-platform-runtime/  # Broker 与权限/生命周期
├── distribution/
│   └── openmuse_builtin_plugins/      # 产品装配层，唯一知道首发插件集合
├── plugins/
│   ├── helix/                         # PTY、Terminal UI、Helix 资产
│   ├── open-file-viewer/              # Viewer UI 与平台适配
│   ├── dsh-agent/                     # DSH panel、binding、sidecar
│   └── native-text-gate/              # NSView/HWND 工程门禁插件
├── schemas/                            # Manifest / protocol schema
└── scripts/                            # 构建、装配与发布门禁
```

`app/openmuse_host` 只依赖 SDK 和 `distribution/openmuse_builtin_plugins`。它不直接依赖 `flutter_pty`、`xterm` 或 DSH 实现包。产品装配层可以为 Community、Enterprise 或测试发行版选择不同插件集合，而不污染 Host。

### 4.1 合同收敛

迁入的 `muse_resource_contract`、`muse_engine_adapter`、`muse_resource_bridge` 和 `muse_surface_orchestrator` 是长期主合同。当前 `openmuse_plugin_sdk` 中的 `OpenMuseResource` 与简单 editor router 是 PoC 兼容层，后续按以下顺序收敛：

1. Host Resource Authority 输出 `MuseResourceDescriptorV1`，绝对路径只存在于受限 materialization 内。
2. 内置插件实现 `MuseEngineAdapter`，并通过 `muse_engine_tck` 后才能发布对应能力。
3. 资源打开进入 `MuseSurfaceOrchestrator`，统一处理 duplicate open、cancel、fallback、generation 和 dispose。
4. Flutter Plugin contribution 只负责把已选中的 engine session 映射到 `PluginSlot`，不再自己决定资源权威与路由。

迁移期禁止两套合同都成为真源：PoC SDK 只能适配主合同，不能继续扩展新的 Resource/Engine 语义。

## 5. 插件模型与热插拔语义

### 5.1 Manifest

每个插件必须有静态 Manifest，声明：

- `id / version / protocol / runtime`；
- activation events；
- permissions；
- editors、panels、commands、services 等 contributions；
- 支持的资源类型与优先级；
- 可执行文件、入口点、哈希和平台架构（发布版补齐）。

Host 只能基于 Manifest 构建菜单和路由，不针对 `helix`、`viewer` 或 `dsh` 写条件分支。

### 5.2 两级插件

| 类型 | 装配方式 | 可运行时启停 | 可替换代码/升级 | 隔离 |
|---|---|---:|---:|---|
| Built-in Flutter Plugin | 编译进产品 | 是 | 需重启/重新发版 | 同进程 |
| External Runtime Plugin | Manifest + 签名 bundle | 是 | 是 | 独立进程 |

Flutter AOT 不能安全地从任意磁盘包动态加载新的 Dart UI。因此“Built-in 插件热插拔”准确含义是贡献注册、激活、停用和资源释放，而不是动态装载新 Dart 代码。插件生态的长期主路径应是 External Runtime Plugin：插件拥有 Native View 或 WebView runtime，Host 只 attach view 并通过 IPC 控制。

### 5.3 生命周期

```text
discovered → installed → registered → activating → active
                                      ↘ failed
active ↔ background → suspended → deactivating → installed
installed → uninstalling → removed
```

要求：

- 相同插件的并发激活必须合并成一个 future；
- deactivate 自动注销命令、服务、订阅、Context 和 Native View；
- sidecar/PTY 必须由插件持有并在 deactivate 时停止；
- 插件崩溃不得结束 Host；
- 外部插件更新采用新进程健康检查成功后切换，失败回滚旧版本；
- 每个请求有 deadline、cancellation 和 request id。

## 6. 三个平面

### 6.1 View Plane

负责渲染、指针、键盘、IME、焦点和 resize：

```text
Flutter PluginSlot rect
  → Host ViewManager
  → NSView / child HWND / UIView / embedded runtime view
  → OS 直接分发输入给插件
```

鼠标移动、PTY 字节流、视频帧和 IME composition 不进入 Platform Broker。macOS 通过 NSView hierarchy，Windows 通过 child HWND；两端只统一上层 `attach/setBounds/show/hide/focus/detach` 语义。

### 6.2 Control Plane

统一六类语义：

- Command：请求执行动作，如 `workspace.openResource`；
- Event：事实通知，如 `resource.activeChanged`；
- Service：可复用能力，如 `resource.materialize@1`；
- Context：动态条件，如 `activeEditor == helix.editor`；
- Capability：某参与者可以提供的能力；
- Contribution：Manifest 声明的静态 UI/路由扩展。

插件不得直接 import 或调用另一插件。所有跨插件调用经过 Broker 做 provider 选择、权限、超时和审计。

### 6.3 Data Plane

大数据不进入 JSON envelope：

- Helix：PTY 双向 byte stream + 授权后的工作副本路径；
- Viewer：只读 file handle、短期 loopback URL 或 Blob stream；
- DSH：Workspace projection、Resource descriptor、上下文片段和带 TTL 的 capability；
- Office 引擎：只读 bytes、临时文件或 engine-owned memory。

Control Plane 只传 descriptor、handle、receipt 和短状态。

## 7. Resource Authority 与 Workspace

Host 是资源身份和授权真源。插件只接收：

```text
ResourceRef {
  workspaceRef,
  mountRef,
  resourceId,
  revision,
  mediaType,
  displayName
}
```

禁止把任意绝对路径当作通用协议。对本地可信 Mount，Host 可在 policy 允许后发放短期 materialization handle；对只读或远端 Mount，发放 projection/stream。插件提交写入时返回 expected revision，Host 做冲突检测和原子提交。

Workspace 是 Host 核心域，不是某个编辑器插件。左侧 Explorer 仅投影 Workspace Tree；中间打开何种编辑器由 Contribution Registry 决定。

## 8. Helix 插件

Helix 插件拥有：

- `flutter_pty` 与 `xterm` 依赖；
- Helix 可执行文件和 runtime grammar 资产；
- 一个可复用的进程池；
- 文档打开命令、路径转义、PTY resize 与退出状态；
- Terminal Surface 和状态条。

同一 Workspace/配置默认复用一个 Helix 进程，打开第二个文件发送编辑器命令，不再触发“正在启动”。Host 只看到一个 Editor contribution。后续多 Workspace 隔离可用 `{workspaceRef, profile}` 作为 pool key。

发布门槛：Host 和 Helix 二进制必须拥有一致架构集合。Universal macOS 包不能夹带 arm64-only Helix；Windows 包必须包含 `hx.exe` 与对应 runtime。

## 9. Viewer 插件

Viewer 插件拥有资源类型匹配和平台 renderer：

- macOS V1：WKWebView，禁用 JavaScript、非持久化 data store、扩展名白名单、本地只读 URL；
- Windows V1：WebView2 或专用 PDF/image native renderer，必须单独过门禁；
- 插件不得自行扩大文件系统访问范围；
- HTML/SVG 需要 CSP、脚本和外链策略；PNG/PDF 不通过 `evaluateJavaScript` 注入。

原 PNG 报错来自把本地资源送入 JavaScript 求值/桥接路径。新适配器直接加载经过验证的本地 URL，从架构上移除了该故障路径。

## 10. DSH 为什么是插件

结论：DSH 必须是插件，但 DSH 所需的资源授权仍由 Host 提供。

如果把 DSH 写进 Host，会造成四个问题：Host 启动依赖 Node/DSH、模型配置渗入全局设置、Agent UI 无法独立升级、插件生态被一个特定 Agent runtime 绑死。作为插件后：

- 未安装或未配置模型凭据时，Workspace 和编辑器不受影响；
- DSH panel 可以按需激活、停止、升级和崩溃恢复；
- 未来可并存其他 Agent panel；
- 权限可以按插件清单授权和审计。

### 10.1 DSH 插件内部结构

```text
DSH Plugin
├── Panel Contribution (right-sidebar / dsh.agent)
├── Sidecar Supervisor
│   ├── discover runtime
│   ├── spawn on 127.0.0.1:0
│   ├── readiness / restart / log redaction
│   └── stop on deactivate
├── Workspace Binding Adapter
├── Resource Open Adapter
├── Context Projection Adapter
└── Credential Capability Consumer
```

Host 不读取模型 API Key。Host 的 Credential Service 只在用户授权后向插件发放不可导出的 credential handle；V1 环境变量仅为 PoC，不是发布设计。

### 10.2 Workspace binding

关系是 `Mount ↔ DSH Workspace`，不是简单的项目名映射。一个 Project Workspace 可以有多个 Mount，每个 Mount 的 materialization 能力不同：

| Mount | DSH 投影 | 写权限 |
|---|---|---|
| local trusted | 授权后的 host path | 按 Workspace policy |
| local read-only | read-only projection | 禁止 |
| SSH agent | remote workspace agent | 远端 policy |
| cloud/virtual | snapshot 或 loopback stream | V1 禁止 |

binding 文档带 `workspaceRef / mountRef / revision / materialization kind`。重复应用同一 revision 必须幂等。DSH 返回 receipt，Host 保存绑定状态；DSH 不是资源身份真源。

### 10.3 双向资源联动

DSH → Host：

```text
DSH UI/tool → workspace.openResource(ResourceRef, anchor)
→ Broker permission/policy
→ Surface Orchestrator 选 editor
→ Host 激活/复用 surface
→ receipt 返回 DSH
```

Host → DSH：

```text
selection/resource changed
→ Host 生成最小 ContextProjection
→ 用户显式插入或策略允许的自动投影
→ DSH session 记录引用和 revision
```

DSH 不接收任意 path、engine id 或长期 token。Agent action 只调用窄工具：open/read/propose；写入必须经过 Host 的 proposal/commit 流程。

## 11. UI 架构与 clean-room 对齐

Host 只定义稳定 Workbench 区域，不包含格式插件 UI：

- 左栏：232px，Workspace、搜索、新建、资源树、插件/回收站入口；
- 中区：弹性宽度，42px 顶栏 + Editor PluginSlot；
- 右栏：354px，Right PanelSlot，当前由 DSH 插件贡献；
- 窗口建议初始 1280×760，最小 1100×650；
- 紧凑列表 32px，正文 13px，细分隔线，浅色 Workspace 与深色 Agent panel。

颜色、间距、字体和圆角集中在 Host design token。插件收到主题语义 token，而不是读取 Host 私有 Widget。视觉基线只使用 OpenMuse 自有截图，CI 做 golden diff；旧产品截图只用于一次性人工规格核对，不进入仓库资产。

## 12. 性能预算

| 指标 | 目标 |
|---|---:|
| Host 冷启动到首帧 p95 | ≤ 800 ms |
| Workspace 树恢复 p95 | ≤ 1.5 s |
| 已激活编辑器切换 p95 | ≤ 100 ms |
| Built-in 插件首次激活 p95 | ≤ 250 ms（不含外部引擎） |
| 复用 Helix 打开第二文件 p95 | ≤ 150 ms |
| Helix 首次 PTY ready p95 | ≤ 1.2 s |
| Viewer 首屏：本地 PNG p95 | ≤ 300 ms |
| DSH panel 不启动 sidecar 的首帧 | ≤ 100 ms |
| DSH sidecar ready p95 | ≤ 3 s（依赖打包 runtime） |
| PluginSlot resize → native bounds | ≤ 1 frame |

Host 启动阶段禁止启动 Helix 和 DSH。插件只在资源/面板首次可见时激活；进程启动合并并缓存。所有耗时门槛在 Release 构建、冷/热两组样本中测量。

## 13. 安全模型

- Manifest 权限默认拒绝，用户授权与组织 policy 取交集。
- 外部插件 bundle 必须签名、hash 固定、版本可回滚。
- Native Process 默认独立进程；崩溃、卡死和内存超额可终止而不影响 Host。
- loopback 服务绑定 `127.0.0.1:0`，使用随机 session token，不监听公网地址。
- 日志禁止输出凭据、完整用户文档和原始 prompt；凭据必须 redact。
- 文件访问通过 resource lease，拒绝 symlink 逃逸和越界路径。
- DSH 工具执行必须记录 actor、plugin、workspace、resource、revision、decision 和 result。

## 14. 打包边界

一个发布包由 Host + 选定插件 bundles 组成：

```text
OpenMuse.app
├── Host binary / Flutter assets
├── plugins.manifest.lock
├── plugin assets
│   ├── helix/hx + runtime + LICENSE
│   ├── viewer native adapter
│   └── dsh curated closure + node runtime（尚未进入发布包）
└── THIRD_PARTY_NOTICES / SBOM
```

CI 必须校验：

- Manifest schema 与协议版本；
- 未授权网络/文件权限；
- 所有插件产物的架构与 Host 匹配；
- 插件资产哈希；
- macOS Developer ID 签名、公证与 Gatekeeper；
- Windows 签名、安装/卸载和 WebView2/PTY 真机；
- runtime 源码中无旧品牌标识、旧云端点、登录和协作入口。

## 15. 当前工程验证与差距

已验证：

- Flutter Host 不直接依赖 Helix/DSH/viewer 实现包；
- 运行时 registry 可安装、激活、停用和卸载插件；
- macOS 插件自行注册 NSView 与 WKWebView；
- Helix 插件真实 PTY 复用同一进程打开两个文档；
- DSH 插件缺少模型配置时不阻塞 Host；
- DSH 插件已用真实 sidecar 动态 URL 在自有 WKWebView 中显示对话/轨迹 UI；
- Workspace 多 mount、标签/上下文菜单、内容寻址版本历史与统一/并排 Diff 已完成第一阶段实现；
- 三区 clean-room Workbench 首帧可见；
- Rust Broker 的权限、生命周期、服务选择、事件和 context namespace 测试通过。

尚未达到发布门槛：

- Flutter built-in 插件仍是编译期装配，不支持运行时加载新 Dart 代码；
- DSH curated 发布 closure、credential handle、Workspace binding 和双向 resource open 尚未接入；
- Windows HWND 插件代码尚未在 Windows CI/真机编译验证；
- Windows PNG/PDF renderer 尚未实现；
- Helix macOS 资产与 Host 均为 `x86_64 arm64` Universal；
- macOS 包尚无 Developer ID 签名和公证；
- UI 还缺 golden、键盘导航、缩放、暗色主题和可访问性验收。

## 16. 下一阶段独立工程门禁

1. G-Plugin：Manifest discovery、签名 bundle、外部进程 transport、热更新回滚。
2. G-View：NSView/HWND attach、focus、IME、overlay、resize、DPI 真机矩阵。
3. G-Helix：Universal/macOS + Windows 二进制、首次启动/复用性能、崩溃恢复。
4. G-Viewer：PNG/PDF/SVG 安全矩阵、Windows renderer、损坏文件与超大文件。
5. G-DSH：curated closure、credential capability、binding、双向 resource open、审计。
6. G-UI：三区布局 golden、字体/颜色/间距 token、键盘与无障碍。
7. G-Package：macOS 签名公证、Windows 安装/卸载/升级、SBOM 和 notices。

每个门禁必须有独立测试矩阵和可复现结果；未通过的能力不得在安装包或产品文案中宣称可用。
