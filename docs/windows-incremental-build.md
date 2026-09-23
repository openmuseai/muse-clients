# Windows CI 增量构建方案（按域复用上次产物）

目标：把 Windows 出包从"每次全量"改成"只有真正改动的域才重编，其余复用上次成功构建的产物"。
约束不变：**构建逻辑留在 `scripts/ci/*` 里，workflow 只做工具链准备、缓存搬运和产物上传**
（`actions/cache` 的 restore/save 属于搬运，不属于构建逻辑）。

> **状态：已实现**。落地文件：`scripts/ci/lib/domains.ps1`（指纹 + 复用判定 + 标记）、
> `scripts/ci/lib/domain-plan.ps1`（域定义）、`scripts/ci/domain-fingerprints.ps1`（导出
> workflow 用的 cache key）、`scripts/ci/build-windows.ps1 -DomainCacheDir/-ForceRebuild`
> （跳过与记录）、`.github/workflows/windows-build.yml`（每域 restore/save）。
> 实测数据见最后一节。

## 1. 域划分与依赖图

```
rust   ──┐
dart   ──┼─> flutter ──> pack（zip + SHA256SUMS + build-info）──> artifacts
         │
         └─（dart 的 analyze/test 是门禁，不是 flutter 的输入，见下）
```

| 域 | 名称 | 输入（决定是否重建） | 产物 |
| --- | --- | --- | --- |
| `rust` | Rust crates 测试/构建 | `Cargo.toml`、`Cargo.lock`、`crates/**` 的提交、`rustc -V`、`cargo -V`、MSVC 工具集、Windows SDK | `target/` |
| `dart` | Dart 包与 host 的分析和测试 | `app/**`、`packages/**`、`plugins/**`、`distribution/**`、`contracts/**`、`schemas/**` 的提交、Flutter/Dart 版本 | 无（纯门禁） |
| `flutter` | Flutter Windows 宿主构建 | 同 `dart`（源码身份一致），加 Flutter/Dart 版本、MSVC/SDK/CMake/Ninja | `app/openmuse_host/build/windows/**` |
| `pack` | 归档、校验和、构建信息 | 前三个域的指纹 + `scripts/package_windows.ps1`、`scripts/ci/build-windows.ps1`、`scripts/ci/lib/**` 的提交 | `dist/OpenMuse-windows-x64.zip` 等 |

两个刻意的设计选择：

1. **`dart` 永不复用**。它是测试门禁：跳过它等于跳过验证，省下来的几分钟不值得拿"测试没跑"
   去换。它的指纹仍然计算并写进 `build-info.txt`，便于定位"这次到底跑了什么"。
2. **`pack` 永不复用**。避免把"输出"当"输入"缓存，从而掩盖打包回归；`pack` 的指纹由上游三个域的
   指纹组合而成，所以只要有任何上游变了，它就一定不会误命中。它很快（<1 min），不值得缓存。

`flutter` 与 `dart` 用同一组源码路径，但 `parameters.domain` 不同，因此指纹不会互相碰撞。

## 2. 指纹（key）怎么算

`scripts/ci/domain-fingerprints.ps1` 只算 key，不做构建，把结果写到 `$GITHUB_OUTPUT`：

```powershell
pwsh scripts/ci/domain-fingerprints.ps1 -Profile release -RustTarget x86_64-pc-windows-msvc
# rust=3efb957908c2...
# dart=877eaa23f7b5...
# flutter=0b45189bc113...
# pack=7a60269c3dc7...
```

每个 key 都是 `sha256(规范化后的清单)`，清单由三类组成：

1. **源码身份**：`git ls-tree -r HEAD -- <该域的路径>` 的输出排序后哈希。用 git 对象而不是读文件
   内容，快且不受行尾设置影响，也不会因为未跟踪的构建产物而漂移。路径不存在时贡献空集，
   所以"某个域还没产出"也能算出指纹。
2. **工具链身份**：`rustc -V`、`cargo -V`、`python -V`、`vswhere` 的安装版本、
   `VC\Tools\MSVC\<ver>`、`Windows Kits\10\Include\<ver>`、`cmake --version`、`ninja --version`，
   `flutter`/`dart` 版本（只有 Flutter 相关的域才带）。runner 镜像每月更新 VS，漏了这一项就会
   复用上个月编译的产物。
3. **参数身份**：`profile`（release/debug）、`rust_target`，以及域本身的名字。

工具链里没有的东西一律不算输入；因此**改工具链版本必然导致全量重建**，这是刻意保留的。

## 3. 缓存布局与 YAML 接线

| 域 | 缓存路径 | key | 命中后的行为 |
| --- | --- | --- | --- |
| `rust` | `target`、`.muse-domain-cache/rust.json` | `win-rust-<fp>` | `build-windows.ps1` 跳过 rust 域 |
| `flutter` | `app/openmuse_host/build/windows`、`.muse-domain-cache/flutter.json` | `win-flutter-<fp>` | 跳过 `flutter build windows`；`pack` 直接用已有 Release 目录 |

YAML 里不出现任何构建命令（除 `build-windows.ps1` 的调用）。恢复用
`actions/cache/restore@v4`，保存用 `actions/cache/save@v4`，并且**只在对应步骤没有命中时保存**：
一步失败会中止 job，因此半成品永远不会进缓存。

标记文件 `<domain>.json` 与它的产物放在同一个缓存条目里，两者永远一起走：

```json
{ "domain": "flutter", "fingerprint": "0b45189b...", "builtAt": "...", "toolchain": { ... } }
```

`build-windows.ps1` 只有在**指纹一致**且**产物仍然存在**时才跳过；任何一条不满足就重建，
并且只在成功后写回标记。

## 4. 指纹必须在 Bootstrap 之后计算

Flutter SDK、Rust 工具链和 MSVC 工具集本身都是域的输入。在它们上 PATH 之前算指纹会得到
`flutter=absent` 这类假值：workflow 用假值当 key 去 save，下一次运行算出真值去 restore，
两边永远对不上，缓存也就永远不命中。`.github/workflows/windows-build.yml` 因而把
"Domain fingerprints" 放在 Bootstrap **之后**。

## 5. 正确性护栏（比速度更重要）

1. **指纹必须覆盖全部输入**；漏项的后果是"看起来成功、其实陈旧"的包。为此每次构建都会在
   `build-info.txt` 里写 `domains: rust=cache,dart=build,flutter=build,pack=build`，
   job summary 也会显示同一行——出问题第一眼就能看出这包是不是复用出来的。
2. **工具链必须在指纹里**（见第 2 节）。
3. **不做"猜测式"部分复用**：域要么整体命中、要么整体重建；不把某个中间目录单独拷回来。
4. **缓存命中也要过验证**：`verify` 阶段每次都跑（检查归档里的 `OpenMuse.exe`、
   `flutter_windows.dll`、`data/app.so` 并核对 SHA-256），因为它很便宜。
5. **发布强制全量**：`push` tag `v*` 时 workflow 会加 `-ForceRebuild`，正式包不复用缓存。

## 6. 为什么不用 `Swatinem/rust-cache`

参考实现在旧的三棵树工程里踩过这个坑：该 action 被放在 Bootstrap **之前**，而它要缓存的
`vendors/helix` 是 Bootstrap 才还原的，于是 action 中途抛
`Error: The cwd: ...\vendors\helix does not exist`，只恢复了 `~/.cargo` 的 registry，
`target/` 从未进过缓存——缓存"恢复了但没起作用"。本仓库改成显式缓存 `target`，
并且把 key 绑在域指纹上，命中与否由构建脚本自己判定，YAML 只负责搬运。

## 7. 实测

在本机（Windows，Flutter 3.44.2，PowerShell 5.1）跑
`pwsh scripts/ci/build-windows.ps1 -DomainCacheDir .muse-domain-cache`：

| 场景 | rust | dart | flutter | pack |
| --- | --- | --- | --- | --- |
| 第一次（冷） | build | build | build | build |
| 第二次（同 commit、同工具链） | cache | build | cache | build |
| 改一个 Dart 文件后 | cache | build | build | build |
| 改 `Cargo.toml` 后 | build | build | build | build |
| `-ForceRebuild` | build | build | build | build |

`build-info.txt` 的 `domains:` 行是这些状态的权威记录；CI 上同一 commit 连续两次运行可以对照
（第一次 build、第二次 cache）。
