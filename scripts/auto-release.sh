#!/usr/bin/env bash
# Nightly / on-demand: if OhMyKeymint, PlayIntegrityFork, or yypm keybox
# sources moved, bump -omk-rN, rebuild the module zip, commit, push, and
# cut a GitHub Release.
#
# Used by .github/workflows/auto-upstream.yml. Safe to run locally:
#   GH_TOKEN=... scripts/auto-release.sh
#
# No-op (exit 0) when every pin and the yypm source list are already current.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

git config user.name  "${GIT_AUTHOR_NAME:-浅笑}"
git config user.email "${GIT_AUTHOR_EMAIL:-88584695+qianxiaoaa@users.noreply.github.com}"
git config --unset-all coauthor.0.name  2>/dev/null || true
git config --unset-all coauthor.0.email 2>/dev/null || true

set +e
"$ROOT/scripts/update-upstream.sh"
rc=$?
set -e
case "$rc" in
    0)  echo "upstream unchanged; nothing to release"; exit 0 ;;
    10) ;;
    *)  echo "update-upstream.sh failed (exit $rc)" >&2; exit "$rc" ;;
esac

set +e
"$ROOT/scripts/update-upstream.sh" --apply
arc=$?
set -e
[[ $arc -eq 11 ]] || { echo "apply failed (exit $arc)" >&2; exit 1; }

NEW_VER=$("$ROOT/scripts/bump-omk-rev.sh")
NEW_CODE=$(sed -n 's/^versionCode=//p' "$ROOT/module/module.prop" | head -1)
TODAY=$(TZ=Asia/Shanghai date +%Y-%m-%d)
SUMMARY="${UPSTREAM_SUMMARY:-$ROOT/.upstream-changes.txt}"
NOTES=$(sed 's/^/- /' "$SUMMARY")
[[ -n "$NOTES" ]] || NOTES="- Maintenance and upstream refresh."

python3 - "$ROOT/CHANGELOG.md" "$NEW_VER" "$TODAY" "$NOTES" "$NEW_CODE" <<'PY'
import sys
path, ver, today, notes, code = sys.argv[1:6]
text = open(path, encoding="utf-8").read()
section = (
    f"\n## {ver} — {today}\n\n"
    f"自动同步上游。\n\n{notes}\n\n"
    f"发行命名 `AlwaysStrong-{ver}`，`versionCode={code}`。\n"
)
idx = text.find("\n## ")
if idx < 0:
    text = text.rstrip() + "\n" + section
else:
    text = text[:idx] + "\n" + section + text[idx:]
open(path, "w", encoding="utf-8").write(text)
PY

bash "$ROOT/build.sh"

ZIP="$ROOT/out/AlwaysStrong-${NEW_VER}.zip"
[[ -f "$ZIP" ]] || { echo "missing $ZIP" >&2; exit 1; }

git add build.sh module/module.prop module/keybox_fetch.sh README.md NOTICE.md CHANGELOG.md
git commit -m "chore: 同步上游并发布 ${NEW_VER}

${NOTES}

自动构建，versionCode=${NEW_CODE}。"

if [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
    git push "https://x-access-token:${GH_TOKEN:-${GITHUB_TOKEN}}@github.com/qianxiaoaa/AlwaysStrong-OMK-R1.git" HEAD:main \
        2>&1 | sed -E 's#x-access-token:[^@]+@#x-access-token:***@#g'
else
    git push origin HEAD:main
fi

BODY=$(mktemp)
{
    printf '## AlwaysStrong-%s\n\n自动同步上游。\n\n%s\n\n### 安装\n\n1. 卸载其它证明引擎模块后重启一次。\n2. 刷入 \`AlwaysStrong-%s.zip\`。\n3. 重启后点击模块 **Action** 或打开 WebUI 查看状态。\n' \
        "$NEW_VER" "$NOTES" "$NEW_VER"
} > "$BODY"

if command -v gh >/dev/null 2>&1; then
    gh release create "$NEW_VER" "$ZIP" \
        --title "AlwaysStrong-${NEW_VER}" \
        --notes-file "$BODY"
else
    TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    [[ -n "$TOKEN" ]] || { echo "need GH_TOKEN or gh" >&2; exit 1; }
    RESP=$(mktemp)
    PAYLOAD=$(python3 -c 'import json,sys;print(json.dumps({"tag_name":sys.argv[1],"target_commitish":"main","name":"AlwaysStrong-"+sys.argv[1],"body":open(sys.argv[2]).read(),"draft":False,"prerelease":False}))' "$NEW_VER" "$BODY")
    curl -fsSL -X POST \
        -H "Authorization: token ${TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/qianxiaoaa/AlwaysStrong-OMK-R1/releases" \
        -d "$PAYLOAD" \
        -o "$RESP"
    UP=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["upload_url"].split("{")[0])' "$RESP")
    curl -fsSL -X POST \
        -H "Authorization: token ${TOKEN}" \
        -H "Content-Type: application/zip" \
        --data-binary @"$ZIP" \
        "${UP}?name=AlwaysStrong-${NEW_VER}.zip" \
        -o /dev/null
fi

echo "released $NEW_VER"
