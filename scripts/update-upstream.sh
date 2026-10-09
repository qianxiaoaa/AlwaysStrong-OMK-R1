#!/usr/bin/env bash
# Check (and optionally apply) the latest upstream this fork pins:
#   OhMyKeymint (ITxiao6666)  — OMK_TAG / OMK_ASSET in build.sh
#   PlayIntegrityFork         — PIF_TAG / PIF_ASSET in build.sh
#   yypm keybox pool          — enabled URL sources in php-server/config.php,
#                               rewritten into module/keybox_fetch.sh
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
KEYBOX_SH="$ROOT/module/keybox_fetch.sh"
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

# ---- yypm keybox source list (yangyang8002/yypm) ----
# yypm is merged by source, not as a zip payload. Compare php-server/config.php
# against the marked blocks in keybox_fetch.sh; github_dir sources stay skipped
# because the device fetch path has no GitHub contents API.
YYPM_REPO="yangyang8002/yypm"
YYPM_CFG="https://raw.githubusercontent.com/${YYPM_REPO}/main/php-server/config.php"
echo "==> yypm keybox sources (from ${YYPM_REPO} php-server/config.php)"
YYPM_TMP=$(mktemp)
trap 'rm -f "$YYPM_TMP"' EXIT
if ! curl -fsSL --retry 2 --max-time 30 "${CURL_AUTH[@]}" -o "$YYPM_TMP" "$YYPM_CFG"; then
    echo "    lookup failed" >&2
    exit 1
fi
YYPM_DIFF=$("$PY" - "$YYPM_TMP" "$KEYBOX_SH" "$README" "$APPLY" <<'PY'
import re, sys, pathlib

cfg_path, kb_path, readme_path, apply = sys.argv[1:5]
apply = apply == "1"
cfg = pathlib.Path(cfg_path).read_text(encoding="utf-8")
kb = pathlib.Path(kb_path).read_text(encoding="utf-8")
readme = pathlib.Path(readme_path).read_text(encoding="utf-8")

TYPE_MAP = {
    "base64": "base64",
    "multi_base64_hex_rot13": "mbh",
    "hex_base64": "hb64",
}
TYPE_LABEL = {
    "base64": "单层 base64",
    "mbh": "10×base64 → hex → rot13",
    "hb64": "hex → (xml | base64)",
}

def extract_bracket(text, start_key):
    m = re.search(r"'" + re.escape(start_key) + r"'\s*=>\s*\[", text)
    if not m:
        sys.exit("yypm config.php: missing " + start_key)
    i = m.end() - 1
    depth = 0
    for j, ch in enumerate(text[i:], i):
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
    sys.exit("yypm config.php: unclosed " + start_key)

def php_scalar(raw):
    raw = raw.strip().rstrip(",")
    if raw.startswith(("'", '"')):
        return raw[1:-1]
    return raw

src_block = extract_bracket(cfg, "sources")
rev_block = extract_bracket(cfg, "revocation_sources")

want_src = []
skipped = []
for m in re.finditer(r"'([^']+)'\s*=>\s*\[(.*?)\]", src_block, re.S):
    name, body = m.group(1), m.group(2)
    fields = {k: php_scalar(v) for k, v in re.findall(r"'(\w+)'\s*=>\s*([^,\n]+)", body)}
    enabled = fields.get("enabled", "true").lower() == "true"
    typ = fields.get("type", "")
    if not enabled:
        skipped.append(name + " (disabled)")
        continue
    if typ == "github_dir":
        skipped.append(name + " (github_dir)")
        continue
    enc = TYPE_MAP.get(typ)
    url = fields.get("url", "")
    if not enc or not url:
        skipped.append(name + " (unsupported " + typ + ")")
        continue
    want_src.append((name, enc, url))

want_rev = []
for m in re.finditer(r"'([^']+)'\s*=>\s*'([^']+)'", rev_block):
    want_rev.append((m.group(1), m.group(2)))

def marked(text, begin, end):
    m = re.search(
        r"(# BEGIN " + re.escape(begin) + r"\n)(.*?)(# END " + re.escape(end) + r")",
        text, re.S)
    if not m:
        sys.exit("missing markers " + begin)
    return m

sm = marked(kb, "YYPM_SOURCES", "YYPM_SOURCES")
rm = marked(kb, "YYPM_REVOCATION", "YYPM_REVOCATION")
have_src = re.findall(r"^([^|\s#][^|]*)\|([^|]+)\|(.+)$", sm.group(2), re.M)
have_rev = re.findall(r"^([^|\s#][^|]*)\|(.+)$", rm.group(2), re.M)

src_changed = [(a, b, c) for a, b, c in have_src] != want_src
rev_changed = [(a, b) for a, b in have_rev] != want_rev

print("    sources: " + (", ".join(n for n, _, _ in want_src) or "(none)"))
if skipped:
    print("    skipped: " + ", ".join(skipped))
print("    revocation: " + ", ".join(n for n, _ in want_rev))

if not src_changed and not rev_changed:
    print("    up to date")
    sys.exit(0)

parts = []
if src_changed:
    have_n = [n for n, _, _ in have_src]
    want_n = [n for n, _, _ in want_src]
    parts.append("sources " + ",".join(have_n) + " -> " + ",".join(want_n))
    print("    UPDATE  sources  " + ",".join(have_n) + "  ->  " + ",".join(want_n))
if rev_changed:
    have_n = [n for n, _ in have_rev]
    want_n = [n for n, _ in want_rev]
    parts.append("revocation " + ",".join(have_n) + " -> " + ",".join(want_n))
    print("    UPDATE  revocation  " + ",".join(have_n) + "  ->  " + ",".join(want_n))

if not apply:
    print("YYPM_CHANGED")
    sys.exit(0)

src_eof = "\n".join(f"{n}|{e}|{u}" for n, e, u in want_src) + "\n"
rev_eof = "\n".join(f"{n}|{u}" for n, u in want_rev) + "\n"
kb = kb[:sm.start()] + sm.group(1) + "    cat <<'EOF'\n" + src_eof + "EOF\n    " + sm.group(3) + kb[sm.end():]
# re-find revocation after the first rewrite shifted offsets
rm = marked(kb, "YYPM_REVOCATION", "YYPM_REVOCATION")
kb = kb[:rm.start()] + rm.group(1) + "    cat <<'EOF'\n" + rev_eof + "EOF\n    " + rm.group(3) + kb[rm.end():]
pathlib.Path(kb_path).write_text(kb, encoding="utf-8")

rows = ["| 源 | 编码 | 地址 |", "|---|---|---|"]
for n, e, u in want_src:
    host = re.sub(r"^https?://", "", u)
    rows.append(f"| {n} | {TYPE_LABEL.get(e, e)} | `{host}` |")
table = "\n".join(rows)
new_readme, nsub = re.subn(
    r"<!-- YYPM_SOURCES_TABLE -->.*?<!-- /YYPM_SOURCES_TABLE -->",
    "<!-- YYPM_SOURCES_TABLE -->\n" + table + "\n<!-- /YYPM_SOURCES_TABLE -->",
    readme, count=1, flags=re.S)
if nsub != 1:
    sys.exit("README.md missing YYPM_SOURCES_TABLE markers")
pathlib.Path(readme_path).write_text(new_readme, encoding="utf-8")
print("YYPM_NOTE:" + "; ".join(parts))
PY
) || { echo "    parse failed" >&2; exit 1; }

if printf '%s\n' "$YYPM_DIFF" | grep -q 'YYPM_CHANGED\|YYPM_NOTE:'; then
    CHANGED=1
    if [[ $APPLY -eq 1 ]]; then
        YYPM_NOTE=$(printf '%s\n' "$YYPM_DIFF" | sed -n 's/^YYPM_NOTE://p' | head -1)
        [[ -n "$YYPM_NOTE" ]] && note "yypm: ${YYPM_NOTE}"
    fi
fi
printf '%s\n' "$YYPM_DIFF" | grep -vE '^(YYPM_CHANGED|YYPM_NOTE:)' || true

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
