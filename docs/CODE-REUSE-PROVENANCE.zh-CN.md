# 代码复用与来源审计

状态：第一批迁入完成（2026-09-23）

仓库独立化补记：产品负责人确认新工程根许可证仍为 AGPL-3.0；这不改变第三方组件各自的许可证。旧工程只保留为本文件中的历史来源证据，不再是构建输入。固定的 Helix runtime、DSH tarballs/lockfile 与 Node 双架构官方归档现位于 `Muse-Client` 内，见 `third_party/README.md`。新包仍须完成独立的 notices/SBOM 与平台门禁。

## 1. 新边界

OpenMuse 不再把历史客户端中的全部代码视为不可复用。产品负责人已明确允许复用自研 DSH、`middlewares`、历史客户端 `packages` 下的 Muse 代码和 vendor 仓库；实施时仍必须做文件级来源与许可证检查，不能只凭目录名或改名判断。

这条规则与 clean-room UI 不冲突：旧产品的 UI 源码、主题、图标、插画和品牌资产仍不复制；自研且与旧产品无关的协议、Resource/Engine/Surface 状态机、DSH runtime 和适配器可以迁入。

## 2. 已直接迁入并验证

下列包都由 OpenMuseAI 在旧 fork 基线之后的独立提交新增，代码中没有旧产品 import；源提交固定在 [reuse-manifest.json](../compliance/reuse-manifest.json)：

- `muse_resource_contract`
- `muse_engine_adapter`
- `muse_engine_tck`
- `muse_resource_bridge`
- `muse_surface_orchestrator`
- `muse_helix_surface`
- `muse_ioffice_adapter`
- `muse_web_viewer_surface`

它们已迁到本仓库 `packages/`，权威 Resource/Presentation/Engine Session fixtures 已迁到 `contracts/muse/`。迁入后逐包执行 `flutter analyze` 与测试，共 40 项测试通过。后续应让当前轻量 `openmuse_plugin_sdk` 逐步适配这些合同，而不是再造第二套 Resource/Engine/Surface 状态机。

## 3. Helix 设置

Helix 设置中的导航按键语义参考旧 fork 自研的 `helix_commands.dart`（F12、Shift-F12、F2、后退/前进），在新插件中重写为独立的 TOML 生成逻辑；没有迁入旧设置页的产品 UI 依赖。发布前仍须把这部分来源和新自研 `openmuse_dark` 主题纳入文件级审计。

## 4. DSH middlewares

`middlewares/dsh/core` 是领域中立的自研核心。首轮原地验证结果：

| 包 | 测试 |
|---|---:|
| `@muse/contract-resource` | 13 通过 |
| `@muse/contract-presentation` | 14 通过 |
| `@muse/contract-engine-session` | 15 通过 |
| `@muse/resource-host` | 25 通过 |

这些包可以迁入 OpenMuse 的 DSH runtime closure，但当前 `package.json` 没有 `license` 字段，根目录也没有独立许可证文件。发布前必须补齐权属/许可证记录；在此之前允许工程内迁移和验证，不得将“自研”当成已完成发布授权。

`dsh-client-ui-resource-open`、`dsh-resource-presentation-host`、`dsh-tool-resource-present`、Workspace binding 等独立能力可以复用，但需要把旧装配名、旧路径变量和旧 Workspace binding 改为 OpenMuse Host capability。旧的 stage 脚本与 `cordis.patch.yml` 不能原样使用，因为它们仍会装入旧产品专用插件和旧品牌文案。

## 5. 隔离清单

以下代码不进入 OpenMuse runtime：

1. 旧 fork 基线提交首次带入的产品专用 facets 包、`muse_table_surface`、`muse_word_surface`、`muse_document_contract`、`muse_plugin_facets`、`muse_remote_session`、`muse_ui_surface_runtime`；它们没有可证明的独立引入提交，且部分直接依赖旧产品类型。
2. `middlewares/dsh/plugins` 下所有绑定旧产品的 package 与产品专用 DSH 装配包。
3. 旧客户端中来自上游或权属不明的 UI、主题、资源和数据库；Workspace/Version Diff/Resource Surface 中可证明为自研独立提交的领域语义可以迁移，但 presentation 必须去除旧产品 UI 依赖后在 OpenMuse 组件上重建。
4. 未明确许可证的 vendor 代码；“位于 vendors”本身不等于可以发布。

如果未来能提供这些文件的独立著作权证明和书面重新许可，必须以新的来源记录重新审查，不能沿用当前结论。

## 6. Vendor 处理

| 组件 | 许可证 | 集成方式 |
|---|---|---|
| DeepSeek Harness | MIT | DSH sidecar 独立进程，固定 commit，随包保留 LICENSE |
| DSH Desktop | MIT | 仅复用需要的 runtime/client 模块 |
| dsh-model-capabilities | MIT | DSH 插件 closure |
| flutter_pty | MIT | Helix 插件依赖与 notices |
| open-file-viewer | MIT | Viewer 插件；禁止网络与脚本能力默认开启 |
| Helix | MPL-2.0 | 独立 Universal 二进制；保留 MPL、版本、源码获取与修改文件义务 |

`ioffice` 和 IntelliJ 等目录尚未完成组件级许可证与分发边界确认，当前不进入发布包。

## 7. 迁移顺序

1. 以已迁入的 `muse_resource_contract` 取代临时资源 DTO，保留 SDK 兼容层。
2. 以 `muse_engine_adapter` + `muse_engine_tck` 统一 Helix、Viewer、Office adapter 门禁。
3. 以 `muse_surface_orchestrator` 管理重复打开、取消、fallback、generation 与资源回收。
4. 迁入 DSH core 和不绑定旧产品的插件，生成新的 OpenMuse Cordis patch 和最小 closure。
5. 将 DSH Workspace binding 改接 Host Resource Authority；不复制旧 Workspace 数据模型。
6. 生成 SBOM、第三方 notices、源码/修改文件交付材料，并由律师批准发布边界。
