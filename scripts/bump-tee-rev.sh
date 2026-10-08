#!/usr/bin/env bash
# Bump the trailing "-tee-rN" fork revision of this repo's module.prop.
#
# This fork stamps the revision into both the module name and the version:
#   name=AlwaysStrong-v1.0.5-tee-r1
#   version=v1.0.5-tee-r1
#   versionCode=10501
#
# This script increments N (r1 -> r2 ...) and recomputes versionCode with the
# fork's scheme: (major*100 + minor*10 + patch) * 100 + revision, so
# v1.0.4-tee-r11 = 10411 and v1.0.5-tee-r1 = 10501. The base version (v1.0.5)
# is left untouched; change that by hand when the upstream base moves.
#
# Reads/writes: module/module.prop
# Prints: the new version (e.g. v1.0.5-tee-r2). In CI, also appends
#         new_ver / new_code to $GITHUB_OUTPUT.
#
# Usage: scripts/bump-tee-rev.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROP="$ROOT/module/module.prop"

ver=$(sed -n 's/^version=//p' "$PROP" | head -1)
[[ -n "$ver" ]] || { echo "cannot read version= from $PROP" >&2; exit 1; }

base="${ver%-tee-r*}"
[[ "$base" != "$ver" ]] || { echo "version '$ver' has no -tee-rN suffix" >&2; exit 1; }
rev="${ver##*-tee-r}"
[[ "$rev" =~ ^[0-9]+$ ]] || { echo "unparseable revision in '$ver'" >&2; exit 1; }

new_ver="${base}-tee-r$((rev + 1))"

b="${base#v}"
IFS=. read -r MA MI PA <<<"$b"
[[ "$MA" =~ ^[0-9]+$ && "$MI" =~ ^[0-9]+$ && "$PA" =~ ^[0-9]+$ ]] \
    || { echo "unparseable base version '$base'" >&2; exit 1; }
new_code=$(( (MA * 100 + MI * 10 + PA) * 100 + (rev + 1) ))

sed -i.bak \
    -e "s|^name=.*|name=AlwaysStrong-${new_ver}|" \
    -e "s|^version=.*|version=${new_ver}|" \
    -e "s|^versionCode=.*|versionCode=${new_code}|" \
    "$PROP" && rm -f "$PROP.bak"

echo "$new_ver"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "new_ver=$new_ver"   >> "$GITHUB_OUTPUT"
    echo "new_code=$new_code" >> "$GITHUB_OUTPUT"
fi
