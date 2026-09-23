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
- a three-pane local Workspace / Editor / DSH workbench;
- release-boundary checks for forbidden cloud/account surfaces.

Run the validation:

```bash
cargo test --workspace
python3 scripts/verify_release_boundary.py .
./scripts/test_muse_packages.sh
cd app/openmuse_host
flutter analyze
flutter test
flutter build macos --debug
```

Architecture: [`docs/PLUGIN-HOST-DSH-ARCHITECTURE.zh-CN.md`](docs/PLUGIN-HOST-DSH-ARCHITECTURE.zh-CN.md).
Workbench parity specification: [`docs/WORKBENCH-PARITY-SPEC.zh-CN.md`](docs/WORKBENCH-PARITY-SPEC.zh-CN.md).
Code reuse and provenance: [`docs/CODE-REUSE-PROVENANCE.zh-CN.md`](docs/CODE-REUSE-PROVENANCE.zh-CN.md).

The repository currently has no assigned top-level license. Do not publish a
binary or source release until the project license and third-party notice
policy are explicitly approved.
