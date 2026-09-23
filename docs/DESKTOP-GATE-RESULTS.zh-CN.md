# Desktop 独立工程门禁结果

日期：2026-09-23

| 门禁 | 状态 | 证据/限制 |
|---|---|---|
| Host/Plugin 代码边界 | 通过 PoC | Host 仅依赖 SDK + distribution；Helix、Viewer、DSH、Native View 均为独立 package |
| Flutter 插件运行时启停 | 通过 PoC | registry install/activate/deactivate/uninstall 单测通过；不是动态 Dart AOT 装载 |
| macOS NSView | 通过结构与集成测试 | 插件注册真实 NSTextView；手工中文 IME/overlay 长时矩阵仍待执行 |
| Windows HWND | 代码完成，未验证 | 已从 Runner 移到插件 C++；本机无法编译 Windows，必须由 windows-2022 CI/真机验证 |
| Helix PTY | 通过 macOS PoC | Release 人工确认两个文件同 PID、runtime=1；第二文件内容正确切换 |
| Helix Universal | 通过 | Host 与 hx 均为 `x86_64 arm64`，Helix `25.07.1 (079a789e)` |
| Viewer PNG | 通过 macOS PoC | Release 人工打开无异常；WKWebView 禁用 JavaScript并使用非持久化存储 |
| Viewer PDF | 通过 macOS PoC | Release 人工看到 PDF 页面；Windows renderer 尚未实现 |
| DSH 可选 sidecar | macOS 展示链路通过 | 真实 CLI 动态端口、token URL、readiness 与插件 WKWebView UI 已通过；curated 发布 closure/binding 未完成 |
| 旧 Workspace 迁移 | 已取消 | 新工程不继承旧格式，migrator crate 已从 workspace 删除 |
| clean-room UI | 通过交互 PoC | 多 mount 树、标签/右键菜单、版本历史、统一/并排 Diff 与三区布局已实现；golden/可访问性/完整键盘/暗色仍待验证 |
| macOS 构建与 zip | 工程包通过 | Bundle ID `com.openmuseai.office`，本地 codesign verify 通过；未做 Developer ID/公证 |
| Windows 安装包 | 未通过 | 只有 PowerShell/CI 骨架，无本机产物，不得宣称已发布 |

## macOS 产物

- App：`app/openmuse_host/build/macos/Build/Products/Release/OpenMuse.app`
- Zip：`dist/OpenMuse-macos.zip`
- Zip SHA-256：`9ae220b1d373033c3e1e36e93fc86ddb3134d167b448956b78154f0224607e53`
- Zip 大小：38,834,338 bytes
- Bundle ID：`com.openmuseai.office`
- 签名：本地/ad-hoc 可验证，不是 Developer ID 发布签名，未公证。

## 自动验证

- Rust：13 个测试通过；Clippy `-D warnings` 通过。
- Flutter Host：16 个单元/widget 测试通过；analyze 通过。
- Plugin SDK：1 个 lifecycle/router 测试通过；analyze 通过。
- 迁入的 Muse Resource/Engine/Bridge/Surface packages：8 个 package analyze 通过，共 40 项测试通过。
- 原 DSH middleware 核心合同与 Resource Host：4 个 package，共 67 项测试通过；尚待迁入并补齐 package 许可证元数据。
- macOS integration：3 个测试通过（Native View/Viewer、真实 Helix、真实 DSH CLI）。
- Xcode Runner：1 个 Host 边界测试通过；原生插件创建由 Flutter integration 覆盖。

## Release 手工交互验证

- 搜索面板可动态过滤本地资源并打开结果。
- 新建 Markdown 会写入本地 Workspace、加入资源列表并交给 Helix 打开。
- PNG 可打开且不再出现 JavaScript `PlatformException`；PDF 页面可见渲染。
- README 与 architecture 两个文档复用同一 Helix PID，状态保持 `runtime 1`。
- macOS 原生选择器可添加真实目录；目录树按需展开，文件/标签右键菜单和显式 Open With 可用。
- 已完成“保存版本 → 修改磁盘文件 → 历史审计 → 统一/并排 Diff”的桌面端端到端验证。
- 使用真实 DeepSeek Harness closure 启动 sidecar，右栏成功显示对话/轨迹 Web UI；该 closure 尚未进入发行 Zip。
- 设置只包含外观、Workspace、插件、助手、关于；未出现账号、云或协作入口。
- 插件面板能显示 Helix、Viewer、DSH 与 Native View 的安装/运行状态。
- 左侧 Workspace 与右侧 Assistant 均可折叠，并能从中心顶栏恢复。

## 明确阻断项

1. Windows C++ 编译、HWND 输入/DPI/overlay 和安装包真机验证。
2. Windows PNG/PDF Viewer。
3. DSH curated 发布 closure、credential capability、Workspace binding 和双向 resource open（真实 Agent panel 展示链路已通过）。
4. macOS Developer ID、Hardened Runtime、notarization、Gatekeeper。
5. 两平台 UI golden、中文 IME、键盘导航、无障碍和缩放矩阵。
6. 顶层项目许可证与第三方 notices/SBOM 审批。
