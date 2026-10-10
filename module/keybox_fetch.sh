#!/system/bin/sh
# AlwaysStrong — keybox auto-fetch (single source).
#
# Downloads the keybox from one fixed upstream, validates the decoded payload
# structurally, checks it against Google's revocation list, and atomically
# replaces the target file with the fetched key.
#
# The upstream is AlwaysStrong's own endpoint. It serves a raw XML document over
# HTTPS with a self-signed certificate, so this source — and only this source —
# skips TLS verification. The key is still treated as untrusted: it must pass
# the structure check and the revocation gate before it is installed, and a
# source only ever contributes a candidate, never a verdict.
#
# Local seed: the module ships the same key as $CONFIG_DIR/keybox.xml, so a
# device that never reaches the endpoint still has a working keybox.
#
# Exit codes:
#   0  keybox updated (new content written)
#   2  no change (already up to date) / custom keybox active
#   1  fetch / verify failed (existing keybox preserved)

CONFIG_DIR=/data/adb/tricky_store
TARGET="$CONFIG_DIR/keybox.xml"
SOURCE_URL="https://106.55.19.150:1314/down/w0sCaOeypWnZ.xml"

log() { echo "keybox_fetch: $*"; }

# Custom-keybox mode: the user manages keybox.xml themselves via the WebUI —
# never fetch or overwrite it. (Defensive; action.sh/service.sh also gate on this.)
if [ -f "$CONFIG_DIR/custom_keybox" ]; then
    log "custom keybox active — skipping fetch."
    exit 2
fi

# ---- Source --------------------------------------------------------------
# name|encoding|url|insecure. The trailing blank line keeps older POSIX sh
# `read` from dropping the last row.
read_sources() {
    printf 'alwaysstrong|raw|%s|insecure\n' "$SOURCE_URL"
}

# Google's attestation revocation list, fetched from several mirrors. The
# official host is unreachable from many networks, so the GitHub mirrors come
# first and the official endpoint is the formal fallback. A list that cannot be
# fetched is not a verdict, so a total failure here fails open.
read_revocation_sources() {
    cat <<'EOF'
purainity|https://raw.githubusercontent.com/purainity/keybox-tools/main/res/status.json
kimmyxyc|https://raw.githubusercontent.com/KimmyXYC/KeyboxChecker/main/res/json/status.json
google|https://android.googleapis.com/attestation/status
EOF
}

# ---- Resolve tools -------------------------------------------------------
# No single downloader works on every device: busybox wget's built-in TLS
# stalls mid-stream on some CDNs, while our bundled rustls fetcher (asfetch)
# fails to connect on others. Try each engine in turn and keep the first that
# actually returns bytes.
SELF_DIR=$(cd "${0%/*}" 2>/dev/null && pwd)
[ -z "$SELF_DIR" ] && SELF_DIR=/data/adb/modules/tricky_store
case "$(uname -m)" in
    aarch64)        ABI=arm64-v8a ;;
    armv7*|armv8l)  ABI=armeabi-v7a ;;
    x86_64)         ABI=x86_64 ;;
    i?86)           ABI=x86 ;;
    *)              ABI="" ;;
esac
ASFETCH="$SELF_DIR/bin/$ABI/asfetch"
BB=""
for bb in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox \
          /data/adb/modules/busybox-ndk/system/*/busybox "$(command -v busybox 2>/dev/null)"; do
    [ -n "$bb" ] && [ -x "$bb" ] && BB="$bb" && break
done

# bounded SECS cmd... — run cmd under a hard wall-clock cap. A fetcher that
# never returns (asfetch / wget / curl stuck on a dead route, a hung DNS, a
# TLS stall) used to freeze the whole Action. Every network step goes through
# this; the caller falls through to the next engine when the cap trips.
TO=""
if timeout -k 1 5 true >/dev/null 2>&1; then TO="timeout -k 3"
elif timeout 5 true >/dev/null 2>&1; then TO="timeout"
elif [ -n "$BB" ] && "$BB" timeout -k 1 5 true >/dev/null 2>&1; then TO="$BB timeout -k 3"
elif [ -n "$BB" ] && "$BB" timeout 5 true >/dev/null 2>&1; then TO="$BB timeout"
fi
bounded() { _bs="$1"; shift; if [ -n "$TO" ]; then $TO "$_bs" "$@"; else "$@"; fi; }

# run_engine NAME OUTFILE URL INSECURE — one download attempt with the named
# engine. When INSECURE is set, TLS verification is skipped for this attempt
# (asfetch cannot do that, so it is skipped entirely on that source).
run_engine() {
    rm -f "$2"
    _ins="${4:-}"
    case "$1" in
        asfetch) [ -z "$_ins" ] && [ -n "$ABI" ] && [ -f "$ASFETCH" ] && { [ -x "$ASFETCH" ] || chmod 0755 "$ASFETCH" 2>/dev/null; } && bounded 90 "$ASFETCH" -T 15 -o "$2" "$3" 2>/dev/null ;;
        bb)      [ -n "$BB" ] && { if [ -n "$_ins" ]; then bounded 90 "$BB" wget -q -T 20 --no-check-certificate -O "$2" "$3" 2>/dev/null; else bounded 90 "$BB" wget -q -T 20 -O "$2" "$3" 2>/dev/null; fi; } ;;
        curl)    command -v curl >/dev/null 2>&1 && { if [ -n "$_ins" ]; then bounded 90 curl -k -fsSL --connect-timeout 15 --speed-limit 1 --speed-time 20 --max-time 85 -o "$2" "$3" 2>/dev/null; else bounded 90 curl -fsSL --connect-timeout 15 --speed-limit 1 --speed-time 20 --max-time 85 -o "$2" "$3" 2>/dev/null; fi; } ;;
        wget)    command -v wget >/dev/null 2>&1 && { if [ -n "$_ins" ]; then bounded 90 wget -q --no-check-certificate -T 20 -O "$2" "$3" 2>/dev/null; else bounded 90 wget -q -T 20 -O "$2" "$3" 2>/dev/null; fi; } ;;
    esac
    [ -s "$2" ]
}

# try_fetch OUTFILE URL [CACHEFILE] [INSECURE] — try each engine until one
# returns a non-empty file. The engine that last worked is remembered and tried
# first. INSECURE is threaded through to run_engine.
try_fetch() {
    _o="$1"; _u="$2"; _c="${3:-$CONFIG_DIR/.kb_engine}"; _ins="${4:-}"
    _first=$(cat "$_c" 2>/dev/null)
    for _e in "$_first" asfetch bb curl wget; do
        [ -z "$_e" ] && continue
        if run_engine "$_e" "$_o" "$_u" "$_ins"; then
            [ "$_e" != "$_first" ] && echo "$_e" > "$_c" 2>/dev/null
            return 0
        fi
    done
    return 1
}

B64DEC=""
if echo dGVzdA== | base64 -d >/dev/null 2>&1; then
    B64DEC="base64 -d"
else
    for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
        if [ -x "$bb" ] && echo dGVzdA== | "$bb" base64 -d >/dev/null 2>&1; then
            B64DEC="$bb base64 -d"; break
        fi
    done
fi
[ -z "$B64DEC" ] && { log "no base64 decoder available."; exit 1; }

SHA256=""
if command -v sha256sum >/dev/null 2>&1; then
    SHA256="sha256sum"
else
    for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
        if [ -x "$bb" ] && echo x | "$bb" sha256sum >/dev/null 2>&1; then
            SHA256="$bb sha256sum"; break
        fi
    done
fi
[ -z "$SHA256" ] && { log "no sha256sum available."; exit 1; }

# ---- Decoders ------------------------------------------------------------
# Each decoder reads $1 (raw download) and writes the decoded XML to $2,
# returning non-zero when the bytes do not decode.

# Raw XML: the source serves the document as-is. Tolerates a base64-wrapped
# payload (in case the endpoint ever changes) by falling back to base64.
decode_raw() {
    if head -c 512 "$1" 2>/dev/null | grep -qiE '<\?xml|<AndroidAttestation|<Keybox'; then
        cp -f "$1" "$2" 2>/dev/null
    else
        $B64DEC < "$1" > "$2" 2>/dev/null
    fi
    [ -s "$2" ]
}

decode_base64() {
    $B64DEC < "$1" > "$2" 2>/dev/null || return 1
    [ -s "$2" ]
}

decode_by_type() {  # decode_by_type <type> <in> <out>
    case "$1" in
        raw)    decode_raw "$2" "$3" ;;
        base64) decode_base64 "$2" "$3" ;;
        *)      return 1 ;;
    esac
}

# ---- Validation ----------------------------------------------------------
# Structure only (will keymint accept it?). keybox_check.sh is the source of
# truth; the substring floor is used only when it is missing.
kb_usable() {
    _kb="$1"
    [ -s "$_kb" ] || return 1
    KB_CHECK="$SELF_DIR/keybox_check.sh"
    if [ -f "$KB_CHECK" ]; then
        sh "$KB_CHECK" --quiet "$_kb" >/dev/null 2>&1
        return $?
    fi
    head -c 4096 "$_kb" | grep -q "Keybox"
}

# ---- Fetch + install -----------------------------------------------------
mkdir -p "$CONFIG_DIR"
TMP="$CONFIG_DIR/.keybox_fetch.$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM

# Revocation list: fetch once from the first reachable mirror. Best effort —
# a miss here disables the revocation gate, it never fails the whole fetch.
STATUS="$TMP/status.json"
read_revocation_sources | while IFS='|' read -r _rname _rurl; do
    [ -n "$_rurl" ] || continue
    if try_fetch "$STATUS" "$_rurl"; then
        echo "$_rname" > "$TMP/.rev_source"
        break
    fi
done
[ -s "$STATUS" ] && log "revocation list from $(cat "$TMP/.rev_source" 2>/dev/null)."

KB_REVOKE="$SELF_DIR/keybox_revoke_check.sh"
revoked() {  # revoked <keybox.xml> — 0 not revoked, 1 revoked, 2 unknown
    [ -s "$STATUS" ] || return 2
    [ -f "$KB_REVOKE" ] || return 2
    _out=$(sh "$KB_REVOKE" "$1" "$STATUS" 2>&1)
    _rc=$?
    [ "$_rc" = 1 ] && printf '%s\n' "$_out"
    return "$_rc"
}

DISK_HASH=""
[ -s "$TARGET" ] && DISK_HASH=$($SHA256 < "$TARGET" | awk '{print tolower($1)}')

tried=0
read_sources | while IFS='|' read -r _name _type _url _ins; do
    [ -n "$_url" ] || continue
    tried=$((tried + 1))
    raw="$TMP/raw.$tried"
    xml="$TMP/dec.$tried.xml"

    if ! try_fetch "$raw" "$_url" "" "$_ins"; then
        log "[$_name] download failed."
        continue
    fi
    if ! decode_by_type "$_type" "$raw" "$xml"; then
        log "[$_name] decode failed."
        continue
    fi
    if ! kb_usable "$xml"; then
        log "[$_name] decoded keybox is unusable."
        continue
    fi

    new_hash=$($SHA256 < "$xml" | awk '{print tolower($1)}')
    if [ -n "$DISK_HASH" ] && [ "$DISK_HASH" = "$new_hash" ]; then
        log "[$_name] already up to date."
        echo 2 > "$TMP/.result"
        break
    fi

    _rev=$(revoked "$xml")
    _rrc=$?
    if [ "$_rrc" = 1 ]; then
        log "[$_name] keybox is REVOKED by Google."
        printf '%s\n' "$_rev" | sed 's/^/keybox_fetch: /' >&2
        continue
    fi
    [ "$_rrc" = 0 ] || log "[$_name] revocation check inconclusive — proceeding."

    if mv -f "$xml" "$TARGET" 2>/dev/null; then
        chmod 600 "$TARGET" 2>/dev/null
        echo "$_name" > "$CONFIG_DIR/.keybox_source" 2>/dev/null
        log "[$_name] installed $TARGET ($(wc -c < "$TARGET") bytes)."
        echo 0 > "$TMP/.result"
        break
    fi
    log "[$_name] install failed."
done

result=$(cat "$TMP/.result" 2>/dev/null)
case "$result" in
    0) rm -f "$CONFIG_DIR/.keybox.sha256" 2>/dev/null; exit 0 ;;
    2) exit 2 ;;
esac

log "no usable keybox from the source — keeping the one on disk."
exit 1
