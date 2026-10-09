#!/usr/bin/env bash
set -euo pipefail

## Checks that each per-version manifest describes exactly the component files
## staged for upload, by name and by digest. A manifest is only useful to a
## client if the bytes it vouches for are the bytes the release serves, so this
## runs on every packaging run rather than only in the self-test.

if [[ $# -lt 2 ]]; then
  echo "usage: $0 ASSETS_DIR VERSION [VERSION...]" >&2
  exit 2
fi

assets_dir="$1"
shift

status=0
fail() {
  echo "$*" >&2
  status=1
}

for version in "$@"; do
  manifest="$assets_dir/jre${version}-multiarch.json"
  if [[ ! -s "$manifest" ]]; then
    fail "missing or empty: $manifest"
    continue
  fi

  python3 - "$manifest" "$assets_dir" <<'PY' || status=1
import hashlib, json, os, sys

manifest_path, assets_dir = sys.argv[1], sys.argv[2]
with open(manifest_path) as handle:
    manifest = json.load(handle)

problems = []

if manifest.get("schema_version") != 1:
    problems.append("unexpected schema_version: %r" % manifest.get("schema_version"))

components = [manifest.get("universal") or {}] + list(manifest.get("architectures") or [])
if not components:
    problems.append("manifest lists no components")

seen = set()
for component in components:
    for key in ("name", "sha256", "size"):
        if key not in component:
            problems.append("component missing %r: %r" % (key, component))
    if problems and "name" not in component:
        continue

    name = component["name"]
    if name in seen:
        problems.append("duplicate component: %s" % name)
    seen.add(name)

    path = os.path.join(assets_dir, name)
    if not os.path.isfile(path):
        problems.append("manifest names an asset that is not published: %s" % name)
        continue

    with open(path, "rb") as handle:
        payload = handle.read()
    digest = hashlib.sha256(payload).hexdigest()
    if digest != component["sha256"]:
        problems.append(
            "digest mismatch for %s: manifest %s, file %s"
            % (name, component["sha256"], digest)
        )
    if len(payload) != component["size"]:
        problems.append(
            "size mismatch for %s: manifest %s, file %d"
            % (name, component["size"], len(payload))
        )

if problems:
    for problem in problems:
        print(problem, file=sys.stderr)
    sys.exit(1)
PY

  if [[ $status -eq 0 ]]; then
    echo "Java $version manifest verified against staged assets"
  fi
done

exit $status