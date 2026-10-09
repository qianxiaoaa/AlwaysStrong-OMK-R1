#!/usr/bin/env bash
# Bump the trailing "-omk-rN.M" fork revision of this repo's module.prop.
#
#   name=AlwaysStrong-v1.0.5-omk-r3.1
#   version=v1.0.5-omk-r3.1
#   versionCode=105031
#
# Sequence: r3.1 .. r3.9, then r4.0, r4.1 .. r4.9, then r5.0.
# A legacy integer suffix (r3) is treated as r3.0, so the next bump is r3.1.
#
# versionCode: (major*100 + minor*10 + patch) * 1000 + N*10 + M
#   v1.0.5-omk-r3.1 = 105031, v1.0.5-omk-r4.0 = 105040
#
# Reads/writes: module/module.prop
# Prints: the new version. In CI, also appends new_ver / new_code to $GITHUB_OUTPUT.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROP="$ROOT/module/module.prop"

ver=$(sed -n 's/^version=//p' "$PROP" | head -1)
[[ -n "$ver" ]] || { echo "cannot read version= from $PROP" >&2; exit 1; }

base="${ver%-omk-r*}"
[[ "$base" != "$ver" ]] || { echo "version '$ver' has no -omk-r suffix" >&2; exit 1; }
suffix="${ver##*-omk-r}"
[[ "$suffix" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "unparseable revision in '$ver'" >&2; exit 1; }

maj="${suffix%%.*}"
if [[ "$suffix" == *.* ]]; then
    min="${suffix##*.}"
else
    min=0
fi
[[ "$maj" =~ ^[0-9]+$ && "$min" =~ ^[0-9]+$ ]] || { echo "unparseable revision in '$ver'" >&2; exit 1; }

if [[ "$min" -ge 9 ]]; then
    maj=$((maj + 1))
    min=0
else
    min=$((min + 1))
fi
new_ver="${base}-omk-r${maj}.${min}"

b="${base#v}"
IFS=. read -r MA MI PA <<<"$b"
[[ "$MA" =~ ^[0-9]+$ && "$MI" =~ ^[0-9]+$ && "$PA" =~ ^[0-9]+$ ]] \
    || { echo "unparseable base version '$base'" >&2; exit 1; }
new_code=$(( (MA * 100 + MI * 10 + PA) * 1000 + maj * 10 + min ))

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
