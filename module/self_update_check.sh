#!/system/bin/sh
# Check this fork's GitHub update.json and notify when a newer zip is out.
#
# service.sh polls every few minutes; this script only does work at 02:00
# Beijing time, once per calendar day. Opt out with
# /data/adb/tricky_store/no_auto_self_update
#
# Exit:
#   0  newer version found (notification posted)
#   2  already current / not 02:00 / already checked today
#   1  fetch failed

MODPATH="${MODPATH:-${0%/*}}"
[ "$MODPATH" = "$0" ] && MODPATH=/data/adb/modules/tricky_store
CONFIG_DIR=/data/adb/tricky_store
PROP="$MODPATH/module.prop"
UPDATE_JSON_URL="${UPDATE_JSON_URL:-https://raw.githubusercontent.com/qianxiaoaa/AlwaysStrong-OMK-R1/main/update.json}"
UPDATE_JSON_MIRROR="${UPDATE_JSON_MIRROR:-https://cdn.jsdelivr.net/gh/qianxiaoaa/AlwaysStrong-OMK-R1@main/update.json}"
STAMP="$CONFIG_DIR/.self_update_day"
FLAG="$CONFIG_DIR/.update_available"
NO_AUTO="$CONFIG_DIR/no_auto_self_update"

log() {
    echo "self_update: $*"
    /system/bin/log -t "AlwaysStrong-update" "self_update: $*" 2>/dev/null || true
}

[ -f "$NO_AUTO" ] && exit 2
[ -f "$PROP" ] || exit 1

DAY=$(TZ=Asia/Shanghai date +%Y-%m-%d 2>/dev/null)
[ -z "$DAY" ] && DAY=$(date +%Y-%m-%d 2>/dev/null)
HOUR=$(TZ=Asia/Shanghai date +%H 2>/dev/null)
[ -z "$HOUR" ] && HOUR=$(date +%H 2>/dev/null)

[ "$HOUR" = "02" ] || exit 2
[ "$(cat "$STAMP" 2>/dev/null)" = "$DAY" ] && exit 2

mkdir -p "$CONFIG_DIR" 2>/dev/null

BB=""
for bb in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox \
          /data/adb/modules/busybox-ndk/system/*/busybox "$(command -v busybox 2>/dev/null)"; do
    [ -n "$bb" ] && [ -x "$bb" ] && BB="$bb" && break
done

case "$(uname -m)" in
    aarch64)        ABI=arm64-v8a ;;
    armv7*|armv8l)  ABI=armeabi-v7a ;;
    x86_64)         ABI=x86_64 ;;
    i?86)           ABI=x86 ;;
    *)              ABI="" ;;
esac
ASFETCH="$MODPATH/bin/$ABI/asfetch"

TO=""
if timeout -k 1 5 true >/dev/null 2>&1; then TO="timeout -k 3"
elif timeout 5 true >/dev/null 2>&1; then TO="timeout"
elif [ -n "$BB" ] && "$BB" timeout -k 1 5 true >/dev/null 2>&1; then TO="$BB timeout -k 3"
elif [ -n "$BB" ] && "$BB" timeout 5 true >/dev/null 2>&1; then TO="$BB timeout"
fi
bounded() { _bs="$1"; shift; if [ -n "$TO" ]; then $TO "$_bs" "$@"; else "$@"; fi; }

fetch_url() {
    _u="$1"
    if [ -n "$ABI" ] && [ -f "$ASFETCH" ]; then
        [ -x "$ASFETCH" ] || chmod 0755 "$ASFETCH" 2>/dev/null
        _b=$(bounded 45 "$ASFETCH" -T 15 "$_u" 2>/dev/null)
        [ -n "$_b" ] && { printf '%s' "$_b"; return 0; }
    fi
    if [ -n "$BB" ]; then
        _b=$(bounded 45 "$BB" wget -q -T 20 -O - "$_u" 2>/dev/null)
        [ -n "$_b" ] && { printf '%s' "$_b"; return 0; }
    fi
    if command -v curl >/dev/null 2>&1; then
        _b=$(bounded 45 curl -fsSL --connect-timeout 15 --max-time 40 "$_u" 2>/dev/null)
        [ -n "$_b" ] && { printf '%s' "$_b"; return 0; }
    fi
    if command -v wget >/dev/null 2>&1; then
        _b=$(bounded 45 wget -q -T 20 -O - "$_u" 2>/dev/null)
        [ -n "$_b" ] && { printf '%s' "$_b"; return 0; }
    fi
    return 1
}

body=$(fetch_url "$UPDATE_JSON_URL")
[ -n "$body" ] || body=$(fetch_url "$UPDATE_JSON_MIRROR")
[ -n "$body" ] || { log "update.json fetch failed"; exit 1; }

flat=$(printf '%s' "$body" | tr -d '\n')
case "$flat" in *'<'*) log "update.json was not JSON"; exit 1 ;; esac

remote_ver=$(printf '%s' "$flat" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
remote_code=$(printf '%s' "$flat" | sed -n 's/.*"versionCode"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)
zip_url=$(printf '%s' "$flat" | sed -n 's/.*"zipUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

local_code=$(grep -m1 '^versionCode=' "$PROP" | cut -d= -f2-)
local_ver=$(grep -m1 '^version=' "$PROP" | cut -d= -f2-)

echo "$DAY" > "$STAMP"

[ -n "$remote_code" ] || { log "update.json missing versionCode"; exit 1; }
[ -n "$local_code" ] || exit 1

if [ "$remote_code" -le "$local_code" ] 2>/dev/null; then
    rm -f "$FLAG" 2>/dev/null
    log "current $local_ver ($local_code), remote $remote_ver ($remote_code) — up to date"
    exit 2
fi

printf 'version=%s\nversionCode=%s\nzipUrl=%s\n' "$remote_ver" "$remote_code" "$zip_url" > "$FLAG"
msg="AlwaysStrong ${remote_ver} 已发布，打开 GitHub 下载更新"
log "update available: $local_ver -> $remote_ver"

cmd notification post -t "AlwaysStrong" as_mod_update "$msg" >/dev/null 2>&1 || true
if command -v su >/dev/null 2>&1; then
    su -lp 2000 -c "cmd notification post -t AlwaysStrong as_mod_update '$msg'" >/dev/null 2>&1 || true
fi
exit 0
