#!/usr/bin/env bash
# Check (and optionally apply) the latest upstream releases this fork pins:
#   OhMyKeymint (ITxiao6666)  — OMK_TAG / OMK_ASSET in build.sh
#   PlayIntegrityFork         — PIF_TAG / PIF_ASSET in build.sh
#
# Usage:
#   scripts/update-upstream.sh            # dry-run; exit 10 if anything is newer
#   scripts/update-upstream.sh --apply    # rewrite the pins + README/NOTICE
#
# Set GH_TOKEN (or GITHUB_TOKEN) to authenticate GitHub API calls.
#
# Exit codes:
#   0   nothing to update
#   1   error
#  10   updates available (dry-run only)
#  11   updates applied
set -euo pipefail

APPLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply) APPLY=1; shift ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown flag: $1" >&2; exit 1 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SH="$ROOT/build.sh"
README="$ROOT/README.md"
NOTICE="$ROOT/NOTICE.md"
SUMMARY="${UPSTREAM_SUMMARY:-$ROOT/.upstream-changes.txt}"

[[ $APPLY -eq 1 ]] && : > "$SUMMARY"
note() { [[ $APPLY -eq 1 ]] && printf '%s\n' "$1" >> "$SUMMARY"; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need curl
if command -v python3 >/dev/null 2>&1; then PY=python3
elif command -v python >/dev/null 2>&1; then PY=python
else echo "missing: python3" >&2; exit 1
fi

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
CURL_AUTH=()
[[ -n "$TOKEN" ]] && CURL_AUTH=(-H "Authorization: Bearer $TOKEN")

# Newest non-draft release plus the first .zip whose name contains $2.
# $2 is a substring filter (e.g. "release.zip", "PlayIntegrityFork").
api_latest() {
    local repo="$1" prefer="$2"
    curl -sSL --retry 2 --max-time 30 "${CURL_AUTH[@]}" \
        -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/${repo}/releases?per_page=20" \
    | "$PY" -c "
import json, sys
raw = json.load(sys.stdin)
if isinstance(raw, dict):
    sys.exit('github api: ' + raw.get('message', 'unexpected response'))
prefer = '$prefer'
rels = [r for r in raw if not r.get('draft')]
def assets(r):
    a = sorted((x for x in r.get('assets', []) if x['name'].endswith('.zip')),
               key=lambda x: x.get('created_at', ''), reverse=True)
    n = [x['name'] for x in a]
    return [x for x in n if prefer in x] or n
rels = [r for r in rels if assets(r)]
if not rels:
    sys.exit('no release with a matching .zip asset in ${repo}')
rel = max(rels, key=lambda r: r['published_at'])
print(rel['tag_name'])
print(assets(rel)[0])
" | tr -d '\r'
}

read_kv() { sed -n "s/^$2=\"\{0,1\}//p" "$1" | head -1 | sed 's/"$//'; }

patch_kv() {
    local file="$1" key="$2" val="${3//$'\r'/}"
    grep -qE "^${key}=" "$file" || return 0
    sed -i.bak "s|^${key}=.*|${key}=\"${val}\"|" "$file" && rm -f "$file.bak"
}

CHANGED=0

# ---- OhMyKeymint (ITxiao6666) ----
OMK_CUR=$(read_kv "$BUILD_SH" OMK_TAG)
echo "==> OhMyKeymint pin: $OMK_CUR"
if OMK_OUT=$(api_latest "ITxiao6666/OhMyKeymint" "release.zip"); then
    OMK_TAG_NEW=$(printf '%s\n' "$OMK_OUT" | sed -n '1p')
    OMK_ASSET_NEW=$(printf '%s\n' "$OMK_OUT" | sed -n '2p')
    echo "    latest: $OMK_TAG_NEW  ($OMK_ASSET_NEW)"
    if [[ "$OMK_TAG_NEW" != "$OMK_CUR" ]]; then
        echo "    UPDATE  $OMK_CUR  ->  $OMK_TAG_NEW"
        CHANGED=1
        if [[ $APPLY -eq 1 ]]; then
            patch_kv "$BUILD_SH" OMK_TAG "$OMK_TAG_NEW"
            patch_kv "$BUILD_SH" OMK_ASSET "$OMK_ASSET_NEW"
            note "OhMyKeymint: \`${OMK_CUR#v}\` -> \`${OMK_TAG_NEW#v}\`"
            omk_disp="${OMK_TAG_NEW#v}"
            sed -i.bak "s/| OhMyKeymint | \`[^\\\`]*\` /| OhMyKeymint | \`${omk_disp}\` /" "$README" && rm -f "$README.bak"
            sed -i.bak "s/| OhMyKeymint | \`[^\\\`]*\` /| OhMyKeymint | \`${omk_disp}\` /" "$NOTICE" && rm -f "$NOTICE.bak"
        fi
    else
        echo "    up to date"
    fi
else
    echo "    lookup failed" >&2
    exit 1
fi

# ---- PlayIntegrityFork ----
PIF_CUR=$(read_kv "$BUILD_SH" PIF_TAG)
echo "==> PlayIntegrityFork pin: $PIF_CUR"
if PIF_OUT=$(api_latest "osm0sis/PlayIntegrityFork" "PlayIntegrityFork"); then
    PIF_TAG_NEW=$(printf '%s\n' "$PIF_OUT" | sed -n '1p')
    PIF_ASSET_NEW=$(printf '%s\n' "$PIF_OUT" | sed -n '2p')
    echo "    latest: $PIF_TAG_NEW  ($PIF_ASSET_NEW)"
    if [[ "$PIF_TAG_NEW" != "$PIF_CUR" ]]; then
        echo "    UPDATE  $PIF_CUR  ->  $PIF_TAG_NEW"
        CHANGED=1
        if [[ $APPLY -eq 1 ]]; then
            patch_kv "$BUILD_SH" PIF_TAG "$PIF_TAG_NEW"
            patch_kv "$BUILD_SH" PIF_ASSET "$PIF_ASSET_NEW"
            note "PlayIntegrityFork: \`${PIF_CUR}\` -> \`${PIF_TAG_NEW}\`"
            sed -i.bak "s/| PlayIntegrityFork | \`[^\\\`]*\` /| PlayIntegrityFork | \`${PIF_TAG_NEW}\` /" "$README" && rm -f "$README.bak"
            sed -i.bak "s/| PlayIntegrityFork | \`[^\\\`]*\` /| PlayIntegrityFork | \`${PIF_TAG_NEW}\` /" "$NOTICE" && rm -f "$NOTICE.bak"
        fi
    else
        echo "    up to date"
    fi
else
    echo "    lookup failed" >&2
    exit 1
fi

if [[ $CHANGED -eq 0 ]]; then
    echo "nothing to update"
    exit 0
fi
if [[ $APPLY -eq 0 ]]; then
    echo "dry-run: pass --apply to write the pins"
    exit 10
fi
echo "pins applied"
exit 11
