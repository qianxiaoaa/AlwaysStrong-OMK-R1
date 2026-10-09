#!/system/bin/sh
# AlwaysStrong — keybox auto-fetch (multi-source pool).
#
# Downloads a keybox from a pool of public upstreams, tries each source's own
# encoding, validates the decoded payload structurally, checks it against
# Google's revocation list (itself fetched from several mirrors), and atomically
# replaces the target file with the first usable key.
#
# The multi-source pool and the "verified local pool + rollback" behaviour are
# merged from the yypm client (yangyang8002/yypm); the downloader-engine and
# atomic-replace skeleton is AlwaysStrong's. Every source is treated as
# untrusted: a source only ever contributes a candidate, never a verdict.
#
# Sources (name|encoding|url) are synced from yangyang8002/yypm
# php-server/config.php by scripts/update-upstream.sh. Encodings:
#   base64  single-layer base64
#   mbh     10x base64 -> hex -> rot13
#   hb64    hex -> (xml | base64)
# Directory-style yypm sources (github_dir) are not imported: the device
# fetch path has no GitHub contents API. An extra source can be prepended
# with KEYBOX_SOURCES; KEYBOX_BASE_URL is still honoured as a base64 source.
#
# Local pool: every key that passes both gates is copied to
# $CONFIG_DIR/keybox_pool/. When the whole upstream set is unreachable, every
# candidate is revoked, or nothing decodes, the newest pooled key is restored —
# so a bad upstream day never leaves the device without a key.
#
# Exit codes:
#   0  keybox updated (new content written)
#   2  no change (already up to date)
#   1  fetch / verify failed (existing keybox preserved)

CONFIG_DIR=/data/adb/tricky_store
TARGET="$CONFIG_DIR/keybox.xml"
POOL_DIR="$CONFIG_DIR/keybox_pool"
POOL_KEEP=5

log() { echo "keybox_fetch: $*"; }

# Custom-keybox mode: the user manages keybox.xml themselves via the WebUI —
# never fetch or overwrite it. (Defensive; action.sh/service.sh also gate on this.)
if [ -f "$CONFIG_DIR/custom_keybox" ]; then
    log "custom keybox active — skipping fetch."
    exit 2
fi

# ---- Source pool ---------------------------------------------------------
# name|encoding|url. Encodings: base64, mbh, hb64.
# The trailing blank line keeps older POSIX sh `read` from dropping the last row.
read_sources() {
    if [ -n "$KEYBOX_SOURCES" ]; then
        printf '%s\n' "$KEYBOX_SOURCES"
    fi
    if [ -n "$KEYBOX_BASE_URL" ]; then
        printf 'legacy|base64|%s/key\n' "$KEYBOX_BASE_URL"
    fi
    # BEGIN YYPM_SOURCES
    cat <<'EOF'
yurikey|base64|https://raw.githubusercontent.com/Yurii0307/yurikey/main/key
integritybox|mbh|https://raw.githubusercontent.com/MeowDump/MeowDump/refs/heads/main/NullVoid/OptimusPrime
megatron|mbh|https://raw.githubusercontent.com/MeowDump/MeowDump/main/Megatron
EOF
    # END YYPM_SOURCES
}

# Google's attestation revocation list, fetched from several mirrors. The
# official host is unreachable from many networks, so the GitHub mirrors come
# first and the official endpoint is the formal fallback. A list that cannot be
# fetched is not a verdict, so a total failure here fails open.
read_revocation_sources() {
    # BEGIN YYPM_REVOCATION
    cat <<'EOF'
purainity|https://raw.githubusercontent.com/purainity/keybox-tools/main/res/status.json
kimmyxyc|https://raw.githubusercontent.com/KimmyXYC/KeyboxChecker/main/res/json/status.json
google|https://android.googleapis.com/attestation/status
EOF
    # END YYPM_REVOCATION
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

# run_engine NAME OUTFILE URL — one download attempt with the named engine.
run_engine() {
    rm -f "$2"
    case "$1" in
        asfetch) [ -n "$ABI" ] && [ -f "$ASFETCH" ] && { [ -x "$ASFETCH" ] || chmod 0755 "$ASFETCH" 2>/dev/null; } && bounded 90 "$ASFETCH" -T 15 -o "$2" "$3" 2>/dev/null ;;
        bb)      [ -n "$BB" ] && bounded 90 "$BB" wget -q -T 20 -O "$2" "$3" 2>/dev/null ;;
        curl)    command -v curl >/dev/null 2>&1 && bounded 90 curl -fsSL --connect-timeout 15 --speed-limit 1 --speed-time 20 --max-time 85 -o "$2" "$3" 2>/dev/null ;;
        wget)    command -v wget >/dev/null 2>&1 && bounded 90 wget -q -T 20 -O "$2" "$3" 2>/dev/null ;;
    esac
    [ -s "$2" ]
}

# try_fetch OUTFILE URL [CACHEFILE] — try each engine until one returns a
# non-empty file. The engine that last worked is remembered and tried first.
try_fetch() {
    _o="$1"; _u="$2"; _c="${3:-$CONFIG_DIR/.kb_engine}"
    _first=$(cat "$_c" 2>/dev/null)
    for _e in "$_first" asfetch bb curl wget; do
        [ -z "$_e" ] && continue
        if run_engine "$_e" "$_o" "$_u"; then
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

# hex -> binary. Needed only for the mbh sources; without it those are skipped
# and the base64 source still carries the fetch.
HEX2BIN=""
if printf '4142' | xxd -r -p 2>/dev/null | grep -q 'AB'; then
    HEX2BIN="xxd -r -p"
elif [ -n "$BB" ] && printf '4142' | "$BB" xxd -r -p 2>/dev/null | grep -q 'AB'; then
    HEX2BIN="$BB xxd -r -p"
fi

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
# returning non-zero when the bytes do not decode at all.
decode_base64() {
    $B64DEC < "$1" > "$2" 2>/dev/null || return 1
    [ -s "$2" ]
}

# 10 nested base64 layers -> hex -> rot13, the encoding used by MeowDump's
# integritybox/megatron feeds. Whitespace is stripped before every layer: the
# last layer is a hex string, and leftover wrapping would make it odd-length.
decode_mbh() {
    [ -n "$HEX2BIN" ] || return 1
    _d="$TMP/.dec.$$"
    cp "$1" "$_d" || return 1
    _i=0
    while [ "$_i" -lt 10 ]; do
        tr -d ' \t\r\n' < "$_d" > "$_d.w" 2>/dev/null || { rm -f "$_d" "$_d.w" "$_d.x"; return 1; }
        $B64DEC < "$_d.w" > "$_d.x" 2>/dev/null || { rm -f "$_d" "$_d.w" "$_d.x"; return 1; }
        [ -s "$_d.x" ] || { rm -f "$_d" "$_d.w" "$_d.x"; return 1; }
        mv -f "$_d.x" "$_d" 2>/dev/null
        _i=$((_i + 1))
    done
    tr -d ' \t\r\n' < "$_d" > "$_d.w" 2>/dev/null
    $HEX2BIN < "$_d.w" > "$_d.x" 2>/dev/null
    tr 'A-Za-z' 'N-ZA-Mn-za-m' < "$_d.x" > "$2" 2>/dev/null
    rm -f "$_d" "$_d.w" "$_d.x"
    [ -s "$2" ]
}

# hex -> XML, or hex -> base64 -> XML. Used by yypm's hex_base64 feeds
# (currently tricky_addon, kept off upstream until the URL returns bytes).
decode_hb64() {
    [ -n "$HEX2BIN" ] || return 1
    _d="$TMP/.hb64.$$"
    tr -d ' \t\r\n' < "$1" > "$_d.hex" 2>/dev/null || return 1
    $HEX2BIN < "$_d.hex" > "$_d.bin" 2>/dev/null || { rm -f "$_d.hex" "$_d.bin"; return 1; }
    if grep -q '<?xml' "$_d.bin" 2>/dev/null || grep -q '<AndroidAttestation>' "$_d.bin" 2>/dev/null; then
        mv -f "$_d.bin" "$2"
        rm -f "$_d.hex"
        [ -s "$2" ]
        return
    fi
    $B64DEC < "$_d.bin" > "$2" 2>/dev/null
    rm -f "$_d.hex" "$_d.bin"
    [ -s "$2" ]
}

decode_by_type() {  # decode_by_type <type> <in> <out>
    case "$1" in
        base64) decode_base64 "$2" "$3" ;;
        mbh)    decode_mbh "$2" "$3" ;;
        hb64)   decode_hb64 "$2" "$3" ;;
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

# ---- Local verified pool -------------------------------------------------
# Save a key that passed both gates, then trim the pool to POOL_KEEP newest.
pool_add() {
    _src="$1"
    [ -s "$_src" ] || return 0
    mkdir -p "$POOL_DIR" 2>/dev/null
    _h=$($SHA256 < "$_src" | awk '{print tolower($1)}')
    [ -n "$_h" ] || return 0
    cp -f "$_src" "$POOL_DIR/keybox-${_h}.xml" 2>/dev/null
    _n=$(ls -1 "$POOL_DIR"/keybox-*.xml 2>/dev/null | wc -l)
    if [ "$_n" -gt "$POOL_KEEP" ]; then
        ls -1t "$POOL_DIR"/keybox-*.xml 2>/dev/null | tail -n +$((POOL_KEEP + 1)) | while IFS= read -r _old; do
            [ -n "$_old" ] && rm -f "$_old" 2>/dev/null
        done
    fi
}

# Restore the newest pooled key that is still structurally valid. Revocation is
# not re-checked here: a pooled key already passed it when it was stored, and
# the point of a rollback is to survive the network being gone entirely.
pool_rollback() {
    [ -d "$POOL_DIR" ] || return 1
    for _f in $(ls -1t "$POOL_DIR"/keybox-*.xml 2>/dev/null); do
        if kb_usable "$_f"; then
            mv -f "$_f" "$TARGET" 2>/dev/null || continue
            chmod 600 "$TARGET" 2>/dev/null
            echo "pool" > "$CONFIG_DIR/.keybox_source" 2>/dev/null
            log "rolled back to pooled key $(basename "$_f") ($(wc -c < "$TARGET") bytes)."
            return 0
        fi
        rm -f "$_f" 2>/dev/null
    done
    return 1
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
read_sources | while IFS='|' read -r _name _type _url; do
    [ -n "$_url" ] || continue
    tried=$((tried + 1))
    raw="$TMP/raw.$tried"
    xml="$TMP/dec.$tried.xml"

    if ! try_fetch "$raw" "$_url"; then
        log "[$_name] download failed — trying next source."
        continue
    fi
    if ! decode_by_type "$_type" "$raw" "$xml"; then
        [ "$_type" = "mbh" ] && [ -z "$HEX2BIN" ] && log "[$_name] needs xxd, not available — skipping." \
            || log "[$_name] decode failed — trying next source."
        continue
    fi
    if ! kb_usable "$xml"; then
        log "[$_name] decoded keybox is unusable — trying next source."
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
        log "[$_name] keybox is REVOKED by Google — trying next source."
        printf '%s\n' "$_rev" | sed 's/^/keybox_fetch: /' >&2
        continue
    fi
    [ "$_rrc" = 0 ] || log "[$_name] revocation check inconclusive — proceeding."

    if mv -f "$xml" "$TARGET" 2>/dev/null; then
        chmod 600 "$TARGET" 2>/dev/null
        echo "$_name" > "$CONFIG_DIR/.keybox_source" 2>/dev/null
        pool_add "$TARGET"
        log "[$_name] installed $TARGET ($(wc -c < "$TARGET") bytes)."
        echo 0 > "$TMP/.result"
        break
    fi
    log "[$_name] install failed — trying next source."
done

result=$(cat "$TMP/.result" 2>/dev/null)
case "$result" in
    0) rm -f "$CONFIG_DIR/.keybox.sha256" 2>/dev/null; exit 0 ;;
    2) exit 2 ;;
esac

# Nothing installed: fall back to the local pool before giving up.
if pool_rollback; then
    exit 0
fi

log "no usable keybox from any source, and the local pool is empty — keeping the one on disk."
exit 1
