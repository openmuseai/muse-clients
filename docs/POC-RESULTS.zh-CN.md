# OpenMuse PoC 结果

日期：2026-09-23

## 已完成

- Rust transport-neutral plugin protocol 与 Platform Broker。
- Flutter 插件 SDK：install/activate/deactivate/uninstall、Editor/Panel contribution 与路由。
- 产品装配层与 Host 解耦；Host 不再直接依赖 Helix、Viewer 或 DSH 实现。
- Helix 独立插件：真实 PTY、同进程复用打开两个文件。
- open-file-viewer 独立插件：macOS WKWebView 直接打开本地 PNG/PDF，禁用 JavaScript。
- native-text-gate 独立插件：macOS NSView；Windows HWND 代码已移到插件包。
- DSH 独立插件：右侧 Panel contribution、按需 sidecar、无配置不阻塞 Host、真实 loopback Web UI 由插件 WKWebView 嵌入。
- clean-room 三区 Workbench：232px Workspace、弹性编辑区、354px DSH panel。
- 真实 Workspace 多 mount、懒加载目录树、标签/上下文菜单、版本历史与统一/并排 Diff。

## 已执行验证

```bash
cargo test --workspace --offline
cargo clippy --workspace --all-targets --offline -- -D warnings

cd packages/openmuse_plugin_sdk
flutter analyze
flutter test

cd app/openmuse_host
flutter analyze
flutter test
flutter build macos --debug
flutter test integration_test/runtime_gates_test.dart -d macos
```

macOS 集成测试覆盖插件注册的 NSView/WKWebView、真实 Helix PTY 复用和真实 DSH CLI probe。普通产品 Debug 构建的首帧已人工核对；注意 Flutter integration test 会临时覆盖 Debug app 的 Dart 入口，截图或手工测试前必须重新执行 `flutter build macos --debug`。

## 当前限制

- Windows 插件尚未在 Windows 主机编译和真机验证。
- DSH Web UI 展示链路已完成；最小 curated 发布 closure、credential handle 与 Workspace binding 尚未完成。
- Helix 已用同一上游 commit 的 arm64/x86_64 二进制合并为 Universal；Host 与 Helix 架构集合一致。
- macOS Developer ID、公证和 Windows 正式安装器尚未完成。
- UI 仍需 golden、键盘、缩放、暗色、IME、overlay 和无障碍验收。
- Flutter 3.44 提示 `flutter_pty` 和两个本地 macOS 插件尚未提供 Swift Package Manager 支持；当前 CocoaPods 构建通过，但应在 Flutter 将其升级为错误前补齐。

旧 Workspace 迁移已从工程范围移除，不再是产品或发布门禁。

## 发布构建人工核对

- Release Host 首帧为左 Workspace / 中间编辑器 / 右 DSH 的三区布局。
- PNG 打开不再出现 JavaScript `PlatformException`；PDF 可见并显示本地测试页。
- 首次打开 README 启动 Helix；切换到第二个 Markdown 后 PID 与 `runtime 1` 保持不变，内容切换成功。
- macOS Host 与打包 Helix 都是 `x86_64 arm64` Universal。
