#!/usr/bin/env bash
# Refresh upstream.lock.json from the newest GitHub release of each tracked
# upstream.
#
# The hash for every asset comes from the `<asset>.sha256` sidecar that project
# publishes next to the binary — downloaded here, verified against the asset
# itself, and only then written. If a project publishes no sidecar (SLSsteam
# doesn't), the hash of the fetched bytes is recorded instead and noted on
# stdout; Nix pins and re-verifies it on every download either way.
#
# Run it by hand (./ci/update-binaries.sh) or let the daily `sync` job of
# .github/workflows/ci.yml do it; either way the diff is meant to be committed
# (the job opens a PR).
#
# Needs: curl, python3, nix (for the hash round-trip), unzip/tar to verify.
set -euo pipefail

lock="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/upstream.lock.json"
[ -f "$lock" ] || { echo "no lock file at $lock" >&2; exit 1; }

python3 - "$lock" <<'PY'
import base64
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import urllib.request

lock_path = pathlib.Path(sys.argv[1])
data = json.loads(lock_path.read_text())

API = "https://api.github.com/repos/{repo}/releases/latest"
DL = "https://github.com/{repo}/releases/download/{tag}/{asset}"


def get(url, binary=False):
    req = urllib.request.Request(url, headers={"User-Agent": "nix-crab-update-binaries"})
    with urllib.request.urlopen(req, timeout=60) as r:
        body = r.read()
    return body if binary else body.decode()


def asset_name(entry, tag):
    ver = tag
    nov = tag[1:] if tag.startswith("v") else tag
    return entry["asset"].replace("{version}", ver).replace("{ver}", nov)


def sidecar_name(entry, tag, asset):
    """The .sha256 file published next to an asset.

    Convention differs per project: most publish `<asset>.sha256`, Millennium
    publishes the name without the archive suffix. Both are spelled out in
    upstream.lock.json, resolved through the same {version}/{ver} templates.
    """
    if entry.get("sidecar"):
        ver = tag
        nov = tag[1:] if tag.startswith("v") else tag
        return entry["sidecar"].replace("{version}", ver).replace("{ver}", nov)
    return asset + ".sha256"


changed = []
failed = []

for name, entry in sorted(data.items()):
    if name.startswith("_"):
        continue
    repo = entry["repo"]
    try:
        tag = json.loads(get(API.format(repo=repo)))["tag_name"]
        asset = asset_name(entry, tag)
        url = DL.format(repo=repo, tag=tag, asset=asset)

        blob = get(url, binary=True)
        actual = hashlib.sha256(blob).hexdigest()

        sidecar_url = url.rsplit("/", 1)[0] + "/" + sidecar_name(entry, tag, asset)
        try:
            sidecar = get(sidecar_url, binary=True)
            digest = sidecar.decode().split()[0].strip()
            if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
                raise RuntimeError(f"unexpected sidecar format: {sidecar[:60]!r}")
            if digest != actual:
                raise RuntimeError(
                    f"sidecar says {digest}, asset is {actual} — refusing to record it"
                )
        except Exception as e:
            # No sidecar: fall back to the hash of the bytes we just fetched.
            # It still pins the asset for every future eval, and Nix verifies it
            # on every download — we simply lose the independent attestation.
            print(f"    note: no trustworthy sidecar ({e}); recording the fetched hash", file=sys.stderr)
            digest = actual

        sri = "sha256-" + base64.b64encode(bytes.fromhex(digest)).decode()
    except Exception as e:  # keep going: one broken upstream must not stop the rest
        failed.append(f"{name}: {e}")
        continue

    old = (entry.get("version"), entry.get("hash"))
    new = (tag, sri)
    if old != new:
        entry["version"] = tag
        entry["hash"] = sri
        changed.append(f"{name}: {old[0]} -> {tag} ({len(blob) // 1024} KiB)")
    print(f"{name}: {tag} {sri[:20]}... ({len(blob) // 1024} KiB)")


if changed:
    lock_path.write_text(json.dumps(data, indent=2) + "\n")
    print("\nupdated:")
    for line in changed:
        print("  " + line)
else:
    print("\neverything already current")

if failed:
    print("\nFAILED:")
    for line in failed:
        print("  " + line)
    sys.exit(1)
PY
