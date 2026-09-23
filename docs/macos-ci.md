# macOS CI（GitHub Actions）

本仓库是**单仓库**。macOS 出包和 Windows 一样：workflow 只负责 checkout、装工具链、调用
`scripts/ci/*.sh`、上传 `dist/`。构建逻辑在脚本里，开发机和 `macos-14` runner 跑同一条命令。

和旧的三棵树工程不同，这里没有 submodule，也没有 `vendors/` 要在 CI 里还原。Helix Universal
二进制、语法 runtime、DSH tarball 和官方 Node 22.19.0 darwin 归档都在本仓库里。

## 文件清单

| 文件 | 职责 |
| --- | --- |
| `.github/workflows/macos-build.yml` | 出包：装工具链 → `bootstrap-macos.sh` → `build-macos.sh` → 上传 `dist/` |
| `.github/workflows/diagnose-macos.yml` | 只跑工具链探针，几分钟出结果 |
| `.github/workflows/desktop-gates.yml` | push/PR 门禁；macOS job 调的是同一个 `build-macos.sh` |
| `scripts/ci/bootstrap-macos.sh` | rustup target、Flutter macOS desktop、检查 Helix/Node/DSH 输入在 checkout 里 |
| `scripts/ci/build-macos.sh` | **唯一的构建入口**：`cargo test` → `package_macos.sh` → `SHA256SUMS` / `build-info` |
| `scripts/ci/diagnose-macos.sh` | Xcode / Flutter / rust / node，以及可选的空项目 `flutter build macos` |
| `scripts/ci/remote-build-macos.sh` | 用 `OPENMUSE_TOKEN` 触发并跟踪 run（不依赖 `gh`） |
| `scripts/ci/download-artifacts.sh` | 下载成功 run 的产物并核对 `SHA256SUMS.txt` |
| `scripts/package_macos.sh` | 组装 DSH closure、编 Flutter、ad-hoc 签名、写 `dist/OpenMuse-macos.zip` |

## 前置条件

`workflow_dispatch` 要求 workflow 文件已经在默认分支 `main` 上。凭据走 `OPENMUSE_TOKEN`
（classic PAT，`repo` + `workflow`）。取值顺序是 `--token` → `OPENMUSE_TOKEN` →
`GH_TOKEN` / `GITHUB_TOKEN` → `gh auth token`。

```bash
export OPENMUSE_TOKEN='<PAT with repo + workflow>'
```

## 触发方式

```text
GitHub UI: Actions -> "macOS build" -> Run workflow
```

| 输入 | 默认 | 说明 |
| --- | --- | --- |
| `profile` | `release` | `release` / `debug` |
| `rust_targets` | `aarch64-apple-darwin` | 逗号分隔的 rustup target；打包目标是 runner 的 arch（`macos-14` = arm64） |
| `skip_tests` | `false` | 跳过 `cargo test` 和 `flutter test`（改为 `cargo build`） |
| `retention_days` | `14` | 产物保留天数 |

另外 push tag `v*` 也会触发一次出包。

本机触发：

```bash
cd /path/to/muse-clients
./scripts/ci/remote-build-macos.sh
./scripts/ci/remote-build-macos.sh --push
./scripts/ci/remote-build-macos.sh --ref main -f profile=debug
./scripts/ci/remote-build-macos.sh --run-id <id> --download-logs
```

分钟级诊断：

```bash
./scripts/ci/remote-build-macos.sh --workflow diagnose-macos.yml
```

## 产物

成功后 zip 在这次 run 的 **Artifacts** 栏，不在 job 日志 Summary 里：

- `OpenMuse-macos.zip`
- `SHA256SUMS.txt`
- `build-info.txt`（commit、profile、arch、构建时间）

这不是 GitHub Release。`workflow_dispatch` 只上传 Actions artifact，保留 `retention_days` 天。

## 本地复现

```bash
./scripts/ci/bootstrap-macos.sh
./scripts/ci/build-macos.sh --dry-run
./scripts/ci/build-macos.sh
```

`build-macos.sh` 的开关：`--profile debug`、`--skip-tests`、`--dry-run`、`--rust-targets a,b`。

## Runner

`macos-14` 自带 Xcode、Python 3、Git。workflow 再补 Rust（`dtolnay/rust-toolchain@stable`）、
Flutter 3.44.2（`subosito/flutter-action`）、Node 22.19.0。job `timeout-minutes: 180`。
Rust 用 `Swatinem/rust-cache`。

`hx` 约 54 MB，两个 Node 归档各约 46 MB，低于 GitHub 单文件 100 MB 限制，所以直接入库，
让 runner 的 checkout 就能打包，不必再从别的仓库拉。
