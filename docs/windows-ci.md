# Windows CI（GitHub Actions）

本仓库是**单仓库**：Host（`app/openmuse_host`）、插件（`plugins/`）、Dart 包（`packages/`）、
Rust crates（`crates/`）和打包脚本（`scripts/`）都在同一个 checkout 里，没有 submodule。
因此 Windows 流水线不需要像旧的三棵树工程那样先校验 submodule，也没有"client 提交没推上来"
这一类前置条件。

## 文件清单

| 文件 | 职责 |
| --- | --- |
| `.github/workflows/windows-build.yml` | 出包流水线：装工具链 → 算指纹 → 搬缓存 → 调 `build-windows.ps1` → 上传产物 |
| `.github/workflows/diagnose-windows.yml` | 只跑工具链探针，几分钟出结果，用来回答"为什么看不到 Visual Studio" |
| `.github/workflows/desktop-gates.yml` | push/PR 门禁；Windows job 调的是同一个 `build-windows.ps1`，macOS job 见"已知缺口" |
| `scripts/ci/bootstrap-windows.ps1` | 装 rustup target、开 Windows desktop、precache Flutter 产物，并报告工具链身份 |
| `scripts/ci/build-windows.ps1` | **唯一的构建入口**：rust / dart / flutter / pack / verify 五个阶段 |
| `scripts/ci/lib/domains.ps1` | 指纹、工具链身份、域标记的读写 |
| `scripts/ci/lib/domain-plan.ps1` | 域的定义（输入、产物、是否可缓存），指纹脚本和构建脚本共用 |
| `scripts/ci/domain-fingerprints.ps1` | 只算 key，导出给 workflow 的 `actions/cache` |
| `scripts/ci/diagnose-windows-vs.ps1` | vswhere / MSVC / SDK / CMake / Ninja / `flutter doctor`，可选 scratch 构建 |
| `scripts/ci/remote-build-windows.ps1` | 把 GitHub Windows runner 当远程编译机：dispatch + 跟踪 + 拉失败日志 |
| `scripts/package_windows.ps1` | 历史入口，转发到 `scripts/ci/build-windows.ps1` |

设计约束（与参考实现一致）：**构建逻辑全部在 `scripts/ci/*` 里，workflow 只做工具链准备、
缓存搬运和产物上传**。`actions/cache` 的 restore/save 属于"搬运"，不属于构建逻辑。

## 前置条件

- 仓库里不需要任何 vendored 二进制才能出 Windows 包：`package_windows.ps1` 只依赖 Flutter 与
  Rust 工具链，Helix 引擎资产（`hx.exe`）尚未纳入本仓库，插件在缺少引擎时会走"引擎未内置"路径。
- `workflow_dispatch` 要求 workflow 文件已经在该仓库的**默认分支**上。第一次添加
  `windows-build.yml` 后必须先 push 到 `main`，才能用 `remote-build-windows.ps1` 触发。

### 推送权限

`scripts/ci/*` 按 `-Token` → `OPENMUSE_TOKEN`（先进程、再用户环境变量）→ `GH_TOKEN` /
`GITHUB_TOKEN` → `gh auth token` → git 已存凭据的顺序取用，所以推送和触发 workflow 都不需要再登录。
换 token 时：

```powershell
setx OPENMUSE_TOKEN "<新的 classic PAT，需 repo + workflow>"
```

只对新开的进程生效；脚本另外会读用户级环境变量，所以不重开终端也能生效。

> ⚠️ 不要用 `cmdkey /generic:"git:https://github.com" /pass:"<PAT>"` 写凭据：Git Credential
> Manager 存的是自己序列化过的 blob，读不懂这种纯文本条目，实测结果是 push 挂住后报
> `fatal: Cannot prompt because user interactivity has been disabled`。

## 触发方式

```powershell
# GitHub UI: Actions -> "Windows build" -> Run workflow
```

| 输入 | 默认 | 说明 |
| --- | --- | --- |
| `profile` | `release` | `release` / `debug` |
| `rust_targets` | `x86_64-pc-windows-msvc` | 逗号分隔的 rustup target；第一个是被打包的目标 |
| `skip_tests` | `false` | 跳过 Dart / Rust 测试（`cargo test` 降级为 `cargo build`） |
| `force_rebuild` | `false` | 忽略所有域缓存，全量重建 |
| `retention_days` | `14` | 产物保留天数 |

另外 push tag `v*` 也会触发一次出包，并且**强制全量**：正式包不复用缓存。

本地触发（不需要 gh CLI）：

```powershell
cd D:\agentic\src\openmuse-io\muse-clients
pwsh scripts/ci/remote-build-windows.ps1 -Push
pwsh scripts/ci/remote-build-windows.ps1 -Inputs @{ skip_tests = 'true'; force_rebuild = 'true' }
pwsh scripts/ci/remote-build-windows.ps1 -RunId 123456789 -DownloadLogs
```

## 产物

上传 `dist/` 下的：

- `OpenMuse-windows-x64.zip`（便携目录，解包即为可运行目录）
- `SHA256SUMS.txt`（归档的 SHA-256）
- `build-info.txt`（commit、profile、构建时间、工具链版本、**各域是 cache 还是 build**）

`build-windows.ps1` 的 `verify` 阶段会自己校验归档里存在 `OpenMuse.exe`、`flutter_windows.dll`
和 `data/app.so`，并核对 `SHA256SUMS.txt`，所以上传的产物不可能是半成品。

## 本地复现（和 CI 完全一致）

```powershell
cd D:\agentic\src\openmuse-io\muse-clients

# 1. 环境：rustup target + Windows desktop + Flutter windows 产物
pwsh scripts\ci\bootstrap-windows.ps1

# 2. 先看要做什么（-DryRun 保证不改任何文件）
pwsh scripts\ci\build-windows.ps1 -DryRun

# 3. 完整构建（含测试、打包和校验）
pwsh scripts\ci\build-windows.ps1

# 4. 按域复用：命中就跳过，没命中就正常构建
pwsh scripts\ci\build-windows.ps1 -DomainCacheDir .muse-domain-cache
```

`build-windows.ps1` 的开关：`-SkipPreflight -SkipRust -SkipDart -SkipFlutterBuild -SkipTests
-SkipZip -SkipVerify -DryRun -ForceRebuild -DomainCacheDir <dir> -Profile debug
-RustTargets a,b`。

历史入口 `scripts\package_windows.ps1` 等价于 `build-windows.ps1`（默认参数）。

> **PowerShell 版本**：CI 用 `shell: pwsh`（PowerShell 7）。脚本同时兼容 Windows 自带的
> Windows PowerShell 5.1，所以本机可以直接 `pwsh` 或 `powershell` 跑；`$IsWindows` 只存在于
> PS 6+，脚本里统一用 `Test-OpenMuseWindowsHost`。

## Runner 要求与时间预算

`windows-2022` 自带 VS 2022 C++ 工具链、Python、Git、`tar`、Node；workflow 再补 Rust
（`dtolnay/rust-toolchain@stable`）和 Flutter 3.44.2（`subosito/flutter-action`）。
`build-windows.ps1` 在本机也可以用同样的步骤跑，只有工具链来源不同。

| 阶段 | 大致耗时 |
| --- | --- |
| checkout + 工具链 | 2-4 min |
| `flutter precache --windows`（首次） | 1-2 min |
| rust 域（`cargo test --workspace --locked`） | <1 min（命中后 0） |
| dart 域（14 个包 + host 的 pub get/analyze/test） | 4-8 min |
| flutter 域（`flutter build windows --release`） | 2-5 min（命中后 0） |
| pack + verify | <1 min |

job `timeout-minutes: 120`；缓存策略见 [`windows-incremental-build.md`](windows-incremental-build.md)。

## 排障

| 症状 | 原因 / 处理 |
| --- | --- |
| `Visual Studio with the C++ desktop workload was not found` | 跑 `scripts/ci/diagnose-windows-vs.ps1 -CheckBuild`，用 scratch 工程区分"工具链坏了"和"本仓库坏了" |
| `error C2220: the following warning is treated as an error` | Flutter 的 `apply_standard_settings` 给插件加了 `/W4 /WX`，插件里任何 warning 都会变成 error。**在 Windows 上必须真的编过一遍**，无法用 macOS 的编译结果代替 |
| `error C2589: '(': illegal token on right side of '::'` | `<windows.h>` 的 `min`/`max` 宏和 `std::min`/`std::max` 冲突。runner 目标自己定义了 `NOMINMAX`，**插件目标没有**，插件里要么显式比较、要么避免 `std::min/max` |
| Dart 测试只在 Windows 失败 | 检查是不是 `/` 分隔符假设（`path.split('/')`）或者对 Windows 路径做 `contains()`——TOML 里的反斜杠是被转义的 |
| `flutter pub get` 重新解析了依赖 | `pubspec.lock` 里记的是 `https://pub.flutter-io.cn`，runner 上默认是 `pub.dev`，pub 会重新解析并重写 lock。不影响构建正确性，但会让 lock 与仓库里的版本出现 diff；要固定就跑一次然后提交 |
| 产物被判定为"复用"但其实过期 | 域指纹漏了输入。检查 `scripts/ci/lib/domain-plan.ps1` 的 `paths` 和 `toolchain`，并用 `-ForceRebuild` 做对照 |

拉失败日志：

```powershell
pwsh scripts/ci/remote-build-windows.ps1 -RunId <id> -DownloadLogs
# 解压到 tmp/ci-logs/run-<id>/
```

## 已验证 / 未验证

- **已验证**：Windows x64 上 `cargo test --workspace --locked`、14 个 Dart 包的
  `pub get`/`analyze`/`test`、host 的 `analyze`/`test`、`flutter build windows --release`
  和 `dist/OpenMuse-windows-x64.zip` 全部通过；CI 上同一条路径通过。
- **未验证**：Windows 安装器（Inno Setup / MSIX）、代码签名、SBOM 与完整第三方 notices；
  Windows 上的 PNG/PDF Viewer 原生渲染、Helix `hx.exe` 的 Windows 引擎资产。

## 已知缺口（macOS）

`desktop-gates.yml` 的 macOS job 目前**跑不起来**，而且无法从 Windows 机器上修：它第一步就是
`scripts/stage_helix.sh`，要求仓库里有固定的 Universal `hx`、`runtime/languages.toml`、
`runtime/grammars/`、`runtime/queries/` 和 `third_party/node/v22.19.0/node-v22.19.0-darwin-*.tar.gz`；
这些大二进制输入按 `.gitignore` 的约定**没有入库**。因此该 job 标了 `continue-on-error: true`：
它保留在 UI 里让缺口可见，但不会掩盖 Windows 的结果。补齐这些输入后应当去掉该标记。
