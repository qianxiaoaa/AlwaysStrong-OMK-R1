#!/system/bin/sh
# AlwaysStrong — log collector.
#
# Dumps a diagnostic bundle to /sdcard so a user can attach it to a GitHub
# issue. Deliberately does NOT include the keybox contents (it holds private
# keys) — only its name, size and hash. The spoofed Pixel fingerprint IS
# included: it is fake by design and is exactly what a support request needs.
#
# Run it three ways:
#   - the "Collect logs" button in the WebUI (KSU / APatch / the standalone app)
#   - sh /data/adb/modules/tricky_store/collect_logs.sh   (root shell)
#   - sh action.sh logs
#
# Prints the output path on the last line so callers can show it.

MODDIR=$(cd "${0%/*}" 2>/dev/null && pwd)
# fall back to the install path if run from a copy elsewhere (so the Module
# section isn't blank when someone runs the script from /sdcard or /tmp)
[ -f "$MODDIR/module.prop" ] || MODDIR=/data/adb/modules/tricky_store
CFG=/data/adb/tricky_store
KEY_HOST="${KEYBOX_BASE_URL:-https://raw.githubusercontent.com/Yurii0307/yurikey/main}"
STATUS_URL="${KEYBOX_STATUS_URL:-https://raw.githubusercontent.com/purainity/keybox-tools/main/res/status.json}"

# The engine identifier is a plain assignment in attest.sh. This script is run by
# hand or by the WebUI and is never sourced by the module, so nothing ever puts
# it in the environment — read it out of the file, or the section below prints an
# empty "?" no matter which engine is installed.
ATTEST=$(sed -n 's/^ATTEST=//p' "$MODDIR/attest.sh" 2>/dev/null | head -n 1)

# Timestamped filename so repeated collections don't overwrite each other. If
# date is somehow unavailable, fall back to a fixed name.
STAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null)
[ -n "$STAMP" ] && OUT="/sdcard/AlwaysStrong-log-$STAMP.txt" || OUT="/sdcard/AlwaysStrong-log.txt"

# busybox for the tools toybox may lack (sha256sum on old devices, etc.)
BB=""
for bb in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox \
          /data/adb/modules/busybox-ndk/system/*/busybox; do
    [ -x "$bb" ] && BB="$bb" && break
done
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; elif [ -n "$BB" ]; then "$BB" sha256sum; else echo "n/a"; fi; }

# asfetch, the same native fetcher the module uses — the one that fails on some
# ROMs, so it's exactly what we want to test here.
case "$(uname -m)" in
    aarch64) ABI=arm64-v8a ;; armv7*|armv8l) ABI=armeabi-v7a ;;
    x86_64) ABI=x86_64 ;; i?86) ABI=x86 ;; *) ABI="" ;;
esac
ASFETCH="$MODDIR/bin/$ABI/asfetch"

sec() { echo ""; echo "===== $* ====="; }

{
echo "AlwaysStrong diagnostic log"
echo "generated: $(date 2>/dev/null)"

sec "Module"
grep -E '^(name|version|versionCode)=' "$MODDIR/module.prop" 2>/dev/null
# Two different builds can carry the same version= string (nothing stops a rebuild
# under the same number, and a flashed zip is not proof of what is installed after a
# partial install), so hash the shipped scripts too. sha256sum's output includes the
# filenames, so this moves when a file is renamed, added, removed or edited — which
# is the question "which bytes are actually on this device" that version= cannot
# answer.
_fp=$(sha256sum "$MODDIR"/*.sh 2>/dev/null | sha256sum 2>/dev/null | cut -c1-8)
echo "scripts fingerprint: ${_fp:-?} ($(ls "$MODDIR"/*.sh 2>/dev/null | wc -l) files)"
[ -f "$MODDIR/engine.sh" ] && grep -E '^ENGINE(_NAME)?=' "$MODDIR/engine.sh"
[ -f "$MODDIR/attest.sh" ] && grep -E '^ATTEST(_NAME)?=' "$MODDIR/attest.sh"

sec "Device / ROM"
for p in ro.product.brand ro.product.model ro.product.device \
         ro.build.version.release ro.build.version.sdk ro.build.fingerprint \
         ro.build.version.security_patch ro.product.cpu.abi; do
    echo "$p=$(getprop $p)"
done

sec "Root manager / Zygisk"
echo "KSU: $([ -d /data/adb/ksu ] && echo yes || echo no)"
echo "APatch: $([ -d /data/adb/ap ] && echo yes || echo no)"
echo "Magisk: $([ -d /data/adb/magisk ] && echo yes || echo no)"
echo "ZygiskNext: $([ -d /data/adb/modules/zygisksu ] && echo yes || echo no)"
echo "ReZygisk: $([ -d /data/adb/modules/rezygisk ] && echo yes || echo no)"

sec "TEE / daemon processes"
echo "ATTEST=${ATTEST:-?} (expect tee)"
# The daemon file is a launcher: it execs into app_process under the engine's own
# process name, so it shows up as TEESimulator, not daemon.
for proc in TEESimulator supervisor aswatcher; do
    echo "$proc: $(pidof "$proc" 2>/dev/null || echo 'not running')"
done
KP=$(pidof keystore2 2>/dev/null | head -1)
echo "keystore2 pid: ${KP:-NOT RUNNING}"
[ -n "$KP" ] && echo "injected into keystore2: $(grep -oE '[^ ]*(TEESimulator|tricky_store|inject)[^ ]*' "/proc/$KP/maps" 2>/dev/null | sort -u | tr '\n' ' ' | grep . || echo 'NOTHING (engine lib not mapped)')"
echo "--- process ages (a keystore2 younger than the engine lost its injection)"
ps -A -o PID,ELAPSED,NAME 2>/dev/null | grep -E 'keystore2|TEESimulator|supervisor|aswatcher' || ps -A 2>/dev/null | grep -E 'keystore2|TEESimulator|supervisor'

sec "TEESimulator-RS runtime"
echo "ATTEST=${ATTEST:-?} (expect tee)"
# The engine reads its whole config out of /data/adb/tricky_store; state that
# persists across boots is hbk (the hardware-bound key seed) and the daemon's
# per-boot status file. Show both, plus the runtime libraries actually installed.
echo "hbk: $([ -s "$CFG/hbk" ] && echo "present ($(wc -c < "$CFG/hbk") bytes)" || echo MISSING)"
echo "persistent_keys: $([ -d "$CFG/persistent_keys" ] && echo "present ($(ls "$CFG/persistent_keys" 2>/dev/null | wc -l) files)" || echo none)"
echo "tee_status.txt: $([ -s "$CFG/tee_status.txt" ] && echo present || echo none)"
[ -s "$CFG/tee_status.txt" ] && { echo "--- tee_status.txt (last 40)"; tail -40 "$CFG/tee_status.txt" 2>/dev/null; }
echo "--- engine libraries in the module"
for f in inject supervisor libTEESimulator.so libcertgen.so tee_classes.dex daemon; do
    if [ -e "$MODDIR/$f" ]; then
        echo "  $(ls -l "$MODDIR/$f" 2>/dev/null | awk '{print $5" bytes  "$9}')"
    else
        echo "  MISSING: $f"
    fi
done
# TEESimulator-RS logs to logcat (tag TEESimulator) rather than to a file; the
# tail is the only on-device proof the daemon reached its keystore2 injection.
echo "--- logcat TEESimulator (last 40)"
logcat -d -t 3000 2>/dev/null | grep -iE 'TEESimulator|org\.matrix\.TEESimulator' | tail -40 || echo none

# --- verified boot inputs -------------------------------------------------
# The attestation engine copies these two props into the attested root of trust,
# so the values Google judges DEVICE on are these, not anything in the keybox.
# Module versions before
# r10 filled an empty prop with sha256 over the raw first 64 KiB of the vbmeta
# partition, which is not what AVB measures, and nothing in a log distinguishes
# that from the real thing: it is 64 hex chars either way. Reproducing the old
# formula here flags it if an earlier install leaves one behind, and keeps the
# fabrication from quietly coming back.
# The four values used to live in three different files, which cost a full
# debugging session to line up by hand.
echo "--- verified boot inputs"
_vbd=$(getprop ro.boot.vbmeta.digest 2>/dev/null)
_vbk=$(getprop ro.boot.vbmeta.public_key_digest 2>/dev/null)
echo "ro.boot.vbmeta.digest: ${_vbd:-<empty>}"
echo "ro.boot.vbmeta.public_key_digest: ${_vbk:-<empty>}"
echo "ro.boot.verifiedbootstate: $(getprop ro.boot.verifiedbootstate 2>/dev/null)"
echo "ro.boot.vbmeta.device_state: $(getprop ro.boot.vbmeta.device_state 2>/dev/null)"
[ -z "$_vbd" ] && echo "WARN: no vbmeta digest — the attested root of trust is empty"
_vbblk=""
if [ -n "$_vbd" ]; then
    for _vb in /dev/block/by-name/vbmeta /dev/block/by-name/vbmeta_a \
               /dev/block/bootdevice/by-name/vbmeta; do
        [ -r "$_vb" ] && _vbblk="$_vb" && break
    done
fi
if [ -n "$_vbblk" ]; then
    # 64 KiB only: reading the whole partition during boot can hang the boot
    # animation on some Xiaomi devices, and the AVB struct fits well inside it.
    _vbc=$(dd if="$_vbblk" bs=4096 count=16 2>/dev/null | sha256sum 2>/dev/null | cut -d' ' -f1)
    if [ -n "$_vbc" ] && [ "$_vbc" = "$_vbd" ]; then
        echo "WARN: the digest equals sha256(first 64 KiB of $_vbblk) — that is the pre-r10 service.sh formula, not an AVB digest, so no build Google knows can match it"
    elif [ -n "$_vbc" ]; then
        echo "digest is not the 64 KiB sha256 of $_vbblk"
    fi
fi
sec "Spoofed fingerprint (pif.prop — safe to share)"
for f in "$CFG/pif.prop" "$MODDIR/pif.prop" "$MODDIR/custom.pif.prop"; do
    [ -s "$f" ] && { echo "--- $f"; cat "$f"; break; }
done

sec "Spoof overrides + effective flags"
if [ -s "$CFG/spoof.conf" ]; then
    echo "--- $CFG/spoof.conf"
    cat "$CFG/spoof.conf"
    # These three drive the verdicts: when on, the PIF zygisk intercepts the
    # keystore calls the attestation engine answers, the two fight, and all three
    # Play Integrity verdicts go red. Say so, so a red verdict isn't chased in the
    # wrong place.
    for _lk in spoofProvider spoofSignature spoofVendingSdk; do
        _v=$(sed -n "s/^${_lk}=//p" "$CFG/spoof.conf" 2>/dev/null | head -1 | tr -d ' \t\r')
        case "$_v" in
            1|true|on|yes)
                echo "WARN: ${_lk}=${_v} is ON — this fights the attestation engine and turns all three Play Integrity verdicts red" ;;
        esac
    done
    echo "inherited-key purge: $([ -f "$CFG/.spoof_keys_purged" ] && echo done || echo pending)"
else
    echo "no spoof.conf (engine defaults only)"
fi
# The flags the zygisk actually reads, module dir first — spoof.conf feeds these
# through engine_enforce_spoof, so this is what the verdicts are decided on.
for f in "$MODDIR/custom.pif.prop" "$CFG/custom.pif.prop" "$MODDIR/pif.prop" "$CFG/pif.prop"; do
    [ -s "$f" ] && { echo "--- $f (effective spoof flags)"; grep -iE '^(spoof|DEBUG)' "$f"; break; }
done

sec "Security patch consistency"
# The OS patch prop, the attested patch (security_patch.txt) and the PIF date all
# have to agree, or an attestation checker flags "OS patch differs". Print all
# three plus the ROM's captured real date, and name any mismatch outright.
echo "patch spoof: $([ -f "$CFG/no_spoof_patch_props" ] && echo "off (ROM real date everywhere)" || echo on)"
echo "date mode: $([ -f "$CFG/unified_patch_date" ] && echo "unified, newest of fingerprint/ROM (experimental toggle ON)" || echo "strict fingerprint, own date (default)")"
echo "ROM real (captured at boot): $(cat "$CFG/.rom_security_patch" 2>/dev/null | tr -cd '0-9')"
_sp=$(cat "$CFG/security_patch.txt" 2>/dev/null | sed 's/^all=//' | tr -d ' \r')
echo "security_patch.txt: ${_sp:-missing}"
_pifsp=""
for f in "$CFG/custom.pif.prop" "$MODDIR/custom.pif.prop" "$CFG/pif.prop" "$MODDIR/pif.prop"; do
    [ -s "$f" ] || continue
    _pifsp=$(grep -m1 '^[#]\?\*\.security_patch=' "$f" 2>/dev/null | cut -d= -f2- | tr -d ' \r')
    [ -n "$_pifsp" ] && { echo "pif *.security_patch: $_pifsp  ($f)"; break; }
done
_pr=$(getprop ro.build.version.security_patch 2>/dev/null)
echo "ro.build.version.security_patch: ${_pr:-unset}"
echo "ro.vendor.build.security_patch: $(getprop ro.vendor.build.security_patch 2>/dev/null)"
[ -n "$_sp" ] && [ -n "$_pr" ] && [ "$_sp" != "$_pr" ] && \
    echo "WARN: security_patch.txt ($_sp) != ro.build.version.security_patch ($_pr) — OS-patch / osPatchLevel mismatch, checkers flag this"
[ -n "$_sp" ] && [ -n "$_pifsp" ] && [ "$_sp" != "$_pifsp" ] && \
    echo "WARN: security_patch.txt ($_sp) != pif *.security_patch ($_pifsp) — PIF and the engine report different patch dates"

sec "Keybox (metadata only — contents withheld)"
KB="$CFG/keybox.xml"
KB_CHECK="$MODDIR/keybox_check.sh"
if [ -s "$KB" ]; then
    echo "path: $KB"
    echo "size: $(wc -c < "$KB") bytes"
    echo "sha256: $(sha < "$KB" | awk '{print $1}')"
    # The structural verdict, not "contains the string Keybox". TEESimulator-RS
    # rejects a document whose key entry is incomplete, and a rejected keybox
    # yields no usable attestation chain — the difference between one red verdict
    # and three, so it is worth naming.
    if [ -f "$KB_CHECK" ]; then
        _why=$(sh "$KB_CHECK" "$KB" 2>&1)
        if [ -z "$_why" ]; then
            echo "usable-by-engine: yes"
        else
            echo "usable-by-engine: NO"
            printf '%s\n' "$_why" | sed 's/^/  reason: /'
            echo "WARN: TEESimulator-RS will reject this keybox and fall back to a software chain — all three Play Integrity verdicts go red. Fix: turn custom keybox off and re-run the Action to re-fetch, or import a keybox that passes this check."
        fi
    else
        echo "usable-by-engine: unknown (keybox_check.sh not installed)"
    fi
    # Google's half of the question, which nothing local can answer: a keybox can
    # be structurally perfect, load in the engine without complaint, and still fail
    # every verdict because its serial is on attestation/status. Public mirrors
    # are the usual source of such a key — one key shared by everyone is revoked
    # the moment it leaks, and the mirror keeps serving it. So read the list
    # Google reads rather than guessing from the file.
    KB_REVOKE="$MODDIR/keybox_revoke_check.sh"
    if [ -f "$KB_REVOKE" ]; then
        _RT="$CFG/.revcheck.$$"; mkdir -p "$_RT"
        _got=0
        if [ -n "$ABI" ] && [ -x "$ASFETCH" ] \
           && "$ASFETCH" -T 8 -o "$_RT/status.json" "$STATUS_URL" >/dev/null 2>&1 \
           && [ -s "$_RT/status.json" ]; then _got=1; fi
        if [ "$_got" = 0 ] && [ -n "$BB" ] \
           && "$BB" wget -q -T 10 -O "$_RT/status.json" "$STATUS_URL" >/dev/null 2>&1 \
           && [ -s "$_RT/status.json" ]; then _got=1; fi
        if [ "$_got" = 0 ] && command -v curl >/dev/null 2>&1 \
           && curl -fsSL --connect-timeout 8 --max-time 20 -o "$_RT/status.json" "$STATUS_URL" >/dev/null 2>&1 \
           && [ -s "$_RT/status.json" ]; then _got=1; fi
        if [ "$_got" = 1 ]; then
            _rev=$(sh "$KB_REVOKE" "$KB" "$_RT/status.json" 2>&1); _rrc=$?
            case "$_rrc" in
                0) echo "revoked-by-google: no" ;;
                1) echo "revoked-by-google: YES"
                   printf '%s\n' "$_rev" | sed 's/^/  /'
                   echo "WARN: Google revoked this keybox — every Play Integrity verdict stays red however good the rest of the device looks. Tap [Action] to re-fetch from the mirror, or import a keybox that passes this check." ;;
                *) echo "revoked-by-google: unknown (checker: $(printf '%s' "$_rev" | head -n 1))" ;;
            esac
        else
            echo "revoked-by-google: unknown (could not fetch $STATUS_URL)"
        fi
        rm -rf "$_RT"
    else
        echo "revoked-by-google: unknown (keybox_revoke_check.sh not installed)"
    fi
    echo "custom-keybox mode: $([ -f "$CFG/custom_keybox" ] && echo on || echo off)"
else
    echo "no keybox.xml present"
fi

sec "Target list (count + first 15)"
if [ -s "$CFG/target.txt" ]; then
    echo "apps: $(grep -cvE '^[[:space:]]*$' "$CFG/target.txt")"
    grep -vE '^[[:space:]]*$' "$CFG/target.txt" | head -15
else
    echo "no target.txt"
fi

sec "Config dir"
ls -l "$CFG" 2>/dev/null

sec "Network (most keybox/fingerprint failures are here)"
# raw IP reachability — no DNS involved
for ip in 1.1.1.1 8.8.8.8; do
    if ping -c1 -W2 "$ip" >/dev/null 2>&1; then echo "ping $ip: ok"; else echo "ping $ip: FAIL"; fi
done
# DNS: can the keybox host be resolved? Resolver often comes up late on some
# AOSP ROMs, which is what leaves them with no keybox on first boot.
HOST=$(echo "$KEY_HOST" | sed -e 's#^[a-z]*://##' -e 's#/.*##' -e 's#:.*##')
if command -v getent >/dev/null 2>&1 && getent hosts "$HOST" >/dev/null 2>&1; then
    echo "dns $HOST: ok ($(getent hosts "$HOST" | awk '{print $1}' | tr '\n' ' '))"
elif [ -n "$BB" ] && "$BB" nslookup "$HOST" >/dev/null 2>&1; then
    echo "dns $HOST: ok (via nslookup)"
else
    echo "dns $HOST: FAIL — cannot resolve (resolver not up / blocked)"
fi
# actual keybox fetch, one attempt per engine, with timing — shows which
# downloader works on this ROM and how long it takes.
NT="$CFG/.netcheck.$$"; mkdir -p "$NT"; trap 'rm -rf "$NT"' EXIT INT TERM
test_engine() {
    _name="$1"; shift
    _t0=$(date +%s 2>/dev/null)
    rm -f "$NT/out"
    "$@" >/dev/null 2>&1
    _t1=$(date +%s 2>/dev/null)
    if [ -s "$NT/out" ]; then
        echo "$_name: ok ($(wc -c < "$NT/out") bytes, ~$((_t1 - _t0))s)"
    else
        echo "$_name: FAIL (~$((_t1 - _t0))s)"
    fi
}
KURL="$KEY_HOST/key"
# short timeouts: this is a reachability probe, not the real fetch, and long
# per-engine stalls are what made pressing the button feel like a freeze.
[ -n "$ABI" ] && [ -x "$ASFETCH" ] && test_engine "asfetch    $KURL" "$ASFETCH" -T 5 -o "$NT/out" "$KURL" || echo "asfetch: not available for $ABI"
[ -n "$BB" ] && test_engine "busybox-wget" "$BB" wget -q -T 5 -O "$NT/out" "$KURL"
command -v curl >/dev/null 2>&1 && test_engine "curl       " curl -fsSL --connect-timeout 5 --max-time 8 -o "$NT/out" "$KURL"
command -v wget >/dev/null 2>&1 && test_engine "wget       " wget -q -T 5 -O "$NT/out" "$KURL"
echo "last-good engine (cached): $(cat "$CFG/.kb_engine" 2>/dev/null || echo none)"
rm -rf "$NT"; trap - EXIT INT TERM

sec "autopif.log (fingerprint fetch)"
cat "$CFG/autopif.log" 2>/dev/null | tail -40 || echo "none"

sec "Conflicting modules present"
for c in playintegrityfix playintegrityfork tricky_store_v2 TrickyStore \
         tee_simulator TEESimulator oh_my_keymint OhMyKeymint omk \
         safetynet-fix MagiskHidePropsConf Yurikey; do
    [ -d "/data/adb/modules/$c" ] && echo "present: $c"
done

sec "logcat (our tags, last 200 lines)"
# -t 3000 reads only the tail of the ring buffer; a full `logcat -d` dump can be
# tens of MB and takes seconds, which is most of the button's perceived lag.
logcat -d -t 3000 2>/dev/null | grep -iE 'AlwaysStrong|TEESimulator|tricky_store|aswatcher|libinject|libTEESimulator|PlayIntegrity' | tail -200 || echo "logcat unavailable"

sec "dmesg (our tags)"
dmesg 2>/dev/null | grep -iE 'TEESimulator|tricky_store|aswatcher|libTEESimulator' | tail -40 || echo "dmesg unavailable"

echo ""
echo "===== end ====="
} > "$OUT" 2>&1

chmod 664 "$OUT" 2>/dev/null
# leave a pointer to the newest log so the WebUI can launch this detached (no UI
# freeze) and poll for the path instead of waiting on the whole run.
echo "$OUT" > "$CFG/.last_log" 2>/dev/null
echo "$OUT"
