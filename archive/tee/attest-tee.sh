#!/system/bin/sh
# Attestation-engine adapter — TEESimulator-RS (ZeyolZZZ/TEESimulator-RS-fix).
#
# customize.sh sources it and calls attest_install (with $ABI_DIR / $ARCH /
# $ZIPFILE / $MODPATH and install_file() + ui_print() in scope). service.sh and
# action.sh source it and call attest_early / attest_start / attest_alive /
# attest_sync / attest_ensure_injection (with $MODDIR in scope).
#
# TEESimulator-RS replaces the keystore2 keymaster backend. Its layout:
#   - the daemon is a Kotlin/Java app (classes.dex) launched through
#     app_process by the module-root `daemon` script, supervised by the native
#     `supervisor` binary (libsupervisor.so);
#   - the KeyMint interceptor is `inject` (libinject.so) and the TEE library is
#     libTEESimulator.so; optional native certificate generation is libcertgen.so;
#   - all runtime state lives under /data/adb/tricky_store (keybox.xml,
#     target.txt, security_patch.txt, hbk, tee_status.txt), so it reads the
#     AlwaysStrong config dir directly and needs no mirroring.
#
# Everything the user configures is already in the layout this engine expects,
# so no sync step is required — attest_sync / attest_ensure_injection exist only
# to satisfy the engine-neutral callers in service.sh and are no-ops here.

ATTEST=tee
ATTEST_NAME="TEESimulator-RS"

# Install the native TEE stack out of the flashed module zip. Every ABI upstream
# ships is staged by build.sh under lib/<abi>/, so the same install works on all
# four architectures. libcertgen.so is optional (only the fused builds ship it).
attest_install() {
    install_file "lib/$ABI_DIR/libTEESimulator.so" "$MODPATH"
    install_file "lib/$ABI_DIR/libinject.so"       "$MODPATH"
    install_file "lib/$ABI_DIR/libsupervisor.so"   "$MODPATH"
    HAS_CERTGEN=0
    if unzip -l "$ZIPFILE" 2>/dev/null | grep -q "lib/$ABI_DIR/libcertgen.so"; then
        install_file "lib/$ABI_DIR/libcertgen.so" "$MODPATH"
        HAS_CERTGEN=1
    fi
    mv "$MODPATH/libinject.so"     "$MODPATH/inject"
    mv "$MODPATH/libsupervisor.so" "$MODPATH/supervisor"
    install_file "tee_classes.dex" "$MODPATH"
    install_file "daemon"          "$MODPATH"
    chmod 755 "$MODPATH/inject" "$MODPATH/supervisor" "$MODPATH/daemon" 2>/dev/null
    if [ "$HAS_CERTGEN" -eq 1 ]; then
        ui_print "TEESimulator-RS installed ($ABI_DIR, native certgen)"
    else
        ui_print "TEESimulator-RS installed ($ABI_DIR)"
    fi
}

# TEESimulator-RS is started after sys.boot_completed: its Java daemon needs a
# fully-booted system, so it does NOT want the early start.
attest_early() { return 1; }

# Fork-based supervisor + daemon (TEESimulator-RS standard pattern). The
# supervisor keeps the daemon alive and re-injects after keystore2 restarts.
attest_start() {
    "$MODDIR/supervisor" "$MODDIR/daemon" "$MODDIR" &
}

# True while the TEE daemon is alive: app_process renames itself to
# "TEESimulator", and the launcher script shows up as "daemon".
attest_alive() {
    pidof TEESimulator >/dev/null 2>&1 || pidof daemon >/dev/null 2>&1
}

# TEESimulator-RS watches /data/adb/tricky_store itself (keybox.xml, target.txt,
# security_patch.txt), so there is nothing to mirror or poke.
attest_sync() { return 0; }

# The supervisor owns injection and crash recovery; nothing for us to watchdog.
attest_ensure_injection() { return 0; }
