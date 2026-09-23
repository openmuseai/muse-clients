# OpenMuse local desktop

This repository contains the clean-room OpenMuse desktop Host, plugin SDK,
platform broker and first-party plugins. It contains no web product and does
not inherit a legacy workspace format.

The current executable slice includes:

- RPC-friendly protocol envelopes and version negotiation;
- separate Helix, open-file-viewer, DSH and Native View plugin packages;
- capability/permission enforcement;
- deterministic command and service routing;
- lifecycle-bound cleanup;
- a three-pane local Workspace / Editor / DSH workbench.

Run the validation:

```bash
cargo test --workspace
./scripts/test_muse_packages.sh
cd app/openmuse_host
flutter analyze
flutter test
flutter build macos --debug
```

The macOS release build is self-contained with respect to other source
repositories: pinned Helix assets, DSH package tarballs/lockfile, and official
Node archives live under this repository. Run `./scripts/package_macos.sh` on
macOS; it assembles the DSH npm closure in `target/`, verifies checksums, builds
the Flutter app, and writes `dist/OpenMuse-macos.zip`. npm still downloads
third-party registry dependencies pinned by `third_party/dsh/package-lock.json`
unless they are already cached. No other product checkout is used.

Architecture: [`docs/PLUGIN-HOST-DSH-ARCHITECTURE.zh-CN.md`](docs/PLUGIN-HOST-DSH-ARCHITECTURE.zh-CN.md).
Workbench parity specification: [`docs/WORKBENCH-PARITY-SPEC.zh-CN.md`](docs/WORKBENCH-PARITY-SPEC.zh-CN.md).
Code reuse and provenance: [`docs/CODE-REUSE-PROVENANCE.zh-CN.md`](docs/CODE-REUSE-PROVENANCE.zh-CN.md).

OpenMuse source uses the repository's AGPL-3.0 `LICENSE`, as selected by the
project owner. Third-party components retain their own licenses; see
[`third_party/README.md`](third_party/README.md). A distributable release still
requires complete third-party notices and platform-specific verification.
