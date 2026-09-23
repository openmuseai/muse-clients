# Pinned third-party build inputs

These files are source inputs of **this** repository. A macOS build does not
read another product's checkout.

| Component | Pinned input | License / integrity |
|---|---|---|
| Helix 25.07.1 (`079a789e`) | `plugins/helix/assets/engines/helix/hx` and `runtime/` | MPL-2.0 file in the same directory; Universal `hx` SHA-256 `e6c8c3d2ae3c70ee140ab182b353f80217c1de300a2b94c0eca97f919e64dbf7` |
| DeepSeek Harness 0.1.0-rc.7 | `dsh/tarballs/`, `dsh/package.json`, `dsh/package-lock.json` | MIT (`dsh/LICENSE`); local tarball and public npm dependencies pinned by the lockfile's integrity values |
| Node.js 22.19.0 | `node/v22.19.0/node-v22.19.0-darwin-{arm64,x64}.tar.gz` | Official `SHASUMS256.txt` retained here; Node's bundled `LICENSE` is extracted into the app |

The DSH tarballs were assembled from the pinned DeepSeek Harness source revision
`99f6f02fecdb7dff40c3fbc9470f5907c29f74ca` and contain no old-product
plugin dependency. The release script builds a local npm closure from these
tarballs and the committed lockfile. This requires network access to the
public npm registry on a fresh machine; it does **not** require another local
source repository. Generated `node_modules`, Flutter outputs and Universal
Node are kept under ignored `target/` or app build directories.

The macOS archive is ad-hoc signed for testing. Product release still requires
notarization, complete third-party notices/SBOM, and separate Windows checks.
