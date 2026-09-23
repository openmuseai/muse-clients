# OpenMuse 架构评审结论

日期：2026-09-23

## 结论

Host + Plugin + DSH 的方向可以满足本地 Workspace、异构编辑器和长期插件生态，但需要坚持三个边界：

1. Host 只做 Workspace/Resource Authority、Workbench、PluginSlot、Broker、权限和生命周期，不包含 Helix、Viewer 或 DSH 实现。
2. Flutter built-in 插件只能运行时启停，无法动态加载新的 AOT Dart；第三方“真热插拔”必须走独立进程 Runtime。
3. OpenMuse 是独立新工程，不继承旧数据库，不提供旧 Workspace 迁移；UI 只按黑盒规格 clean-room 重建。

DSH 应做成插件。它贡献右侧面板并管理自己的 sidecar、Workspace binding 与 Agent adapter；Host 只暴露受控资源、凭据、打开资源和审计服务。无 DSH、无 Key 或 sidecar 失败都不能影响本地 Workspace。

完整组件、协议、性能、安全、UI 与发布分析见 [PLUGIN-HOST-DSH-ARCHITECTURE.zh-CN.md](PLUGIN-HOST-DSH-ARCHITECTURE.zh-CN.md)。

## 体验判断

- 三区工作台能够保持左侧 Workspace、中间编辑区、右侧 DSH 的交互模型。
- Helix runtime 属于插件单例/池，后续文件只建立 document/session，不应再次显示全局“正在启动”。
- Viewer 直接读取 Host 授权资源，不通过 JavaScript 拼接本地路径，可消除当前 PNG 的求值错误路径。
- Native View 可获得原生输入与 IME，但 NSView/HWND 的 focus、overlay、DPI 和无障碍仍需各平台真机门禁。

## 长期演进建议

- V1 保留 built-in plugins 交付首发能力；V2 引入签名的 external runtime bundle。
- Manifest、SDK 与 wire protocol 分离，插件不得互相 import。
- ResourceRef/lease 代替任意路径；大数据走 stream/handle，控制消息保持小而稳定。
- 插件市场必须包含签名、权限、TCK、兼容矩阵、崩溃熔断、升级回滚与安全响应流程。
- 发布前必须完成 SBOM、第三方 notices、macOS 公证与 Windows 签名。
