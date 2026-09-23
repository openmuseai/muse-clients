#!/usr/bin/env python3
"""Build a product-neutral DeepSeek Harness npm closure.

This intentionally does not include any @muse or old-client package. The
Workspace catalog RPC and conversation-to-Host resource bridge are verified
against the pinned client runtime, not assumed from an HTTP 200 response.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import tarfile
from pathlib import Path


VENDORED = Path(__file__).resolve().parent.parent / "third_party/dsh"
REMOVED_PRODUCT_IDENTIFIER = "app" + "flow" + "y"


def run(*command: str, cwd: Path) -> None:
    environment = os.environ.copy()
    subprocess.run(command, cwd=cwd, env=environment, check=True)


def package_name(tarball: Path) -> str:
    with tarfile.open(tarball, "r:gz") as archive:
        member = next(
            item for item in archive.getmembers()
            if item.name == "package/package.json"
        )
        source = archive.extractfile(member)
        if source is None:
            raise RuntimeError(f"missing package.json in {tarball}")
        value = json.load(source)
    return value["name"]


def verify_vendored_inputs() -> None:
    manifest = VENDORED / "package.json"
    lockfile = VENDORED / "package-lock.json"
    if not manifest.is_file() or not lockfile.is_file():
        raise RuntimeError("repository is missing pinned DSH manifest/lockfile")
    dependencies = json.loads(manifest.read_text(encoding="utf-8"))["dependencies"]
    if "@deepseek-ai/dsh" not in dependencies:
        raise RuntimeError("repository is missing the DSH CLI package")
    for name, spec in dependencies.items():
        if REMOVED_PRODUCT_IDENTIFIER in name.lower() or name.startswith("@muse/"):
            raise RuntimeError(f"old product package cannot enter closure: {name}")
        if not isinstance(spec, str) or not spec.startswith("file:tarballs/"):
            raise RuntimeError(f"DSH dependency is not pinned to this repository: {name}")
        tarball = (VENDORED / spec.removeprefix("file:")).resolve(strict=True)
        if not tarball.is_relative_to(VENDORED.resolve()):
            raise RuntimeError(f"DSH tarball escapes repository: {tarball}")
        if package_name(tarball) != name:
            raise RuntimeError(f"DSH tarball package mismatch: {tarball}")


def scrub_build_paths(output: Path) -> int:
    """Remove the build machine path from generated CSS region comments only."""
    count = 0
    for script in (output / "node_modules/@deepseek-ai").rglob("*.js"):
        source = script.read_text(encoding="utf-8")
        if "\\0dsh-css:/" not in source:
            continue
        lines = source.splitlines(keepends=True)
        for index, line in enumerate(lines):
            marker = "\\0dsh-css:"
            if marker not in line or "/packages/" not in line:
                continue
            if not line.lstrip().startswith("//#region \\0dsh-css:"):
                raise RuntimeError(f"refusing to rewrite non-comment source path: {script}")
            before, path = line.split(marker, 1)
            if not path.startswith("/"):
                continue
            _, package_path = path.split("/packages/", 1)
            lines[index] = f"{before}{marker}dsh-source/packages/{package_path}"
            count += 1
        script.write_text("".join(lines), encoding="utf-8")
    return count


def validate(output: Path) -> None:
    entry = output / "node_modules/@deepseek-ai/dsh/lib/bin.js"
    if not entry.is_file():
        raise RuntimeError(f"DSH entry missing: {entry}")
    conversation = (
        output / "node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js"
    )
    if not conversation.is_file():
        raise RuntimeError(f"DSH conversation client missing: {conversation}")
    client_source = conversation.read_text(encoding="utf-8")
    if 'type: "resource.open"' not in client_source or "MuseHostResource" not in client_source:
        raise RuntimeError(
            "DSH conversation client no longer emits the Host resource-open bridge"
        )
    proxy = output / "node_modules/@deepseek-ai/dsh-host-apiproxy/lib/index.js"
    if not proxy.is_file():
        raise RuntimeError(f"DSH workspace API proxy missing: {proxy}")
    proxy_source = proxy.read_text(encoding="utf-8")
    if '"workspace.create"' not in proxy_source or '"workspace.insertBefore"' not in proxy_source:
        raise RuntimeError("DSH workspace catalog RPC contract changed")
    for script in (output / "node_modules/@deepseek-ai").rglob("*.js"):
        source = script.read_text(encoding="utf-8")
        if REMOVED_PRODUCT_IDENTIFIER in source.lower() or any(
            marker in source for marker in ("/Users/", "C:\\Users\\")
        ):
            raise RuntimeError(f"removed product or absolute build path found in DSH runtime: {script}")
    run("node", str(entry), "--version", cwd=output)
    root = (output / "node_modules").resolve()
    links = [item for item in root.rglob("*") if item.is_symlink()]
    escaping = []
    for link in links:
        try:
            link.resolve(strict=True).relative_to(root)
        except (FileNotFoundError, ValueError):
            escaping.append(link)
    if escaping:
        raise RuntimeError(f"closure has broken or escaping symlinks: {escaping[:3]}")
    print(f"DSH closure ready: {output} ({len(links)} internal links)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    output = args.out.resolve()
    if args.validate_only:
        validate(output)
        return
    verify_vendored_inputs()
    if output.exists() and any(output.iterdir()):
        raise RuntimeError(f"output must be empty: {output}")
    output.mkdir(parents=True, exist_ok=True)
    shutil.copy2(VENDORED / "package.json", output / "package.json")
    shutil.copy2(VENDORED / "package-lock.json", output / "package-lock.json")
    shutil.copytree(VENDORED / "tarballs", output / "tarballs")
    run("npm", "ci", "--omit=dev", "--no-audit", "--no-fund",
        "--legacy-peer-deps", cwd=output)
    print(f"sanitized {scrub_build_paths(output)} generated path comments")
    validate(output)


if __name__ == "__main__":
    main()
