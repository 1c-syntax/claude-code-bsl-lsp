#!/bin/bash
# Tests for hooks/check-bsl-ls.sh and .lsp.json.
# Runs the hook against a stubbed `curl` (no network) in an isolated HOME.
#
# Usage: bash tests/check-bsl-ls.test.sh

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/check-bsl-ls.sh"

FAILED=0
PASSED=0

pass() { PASSED=$((PASSED + 1)); echo "  ok   - $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL - $1"; [ -n "${2:-}" ] && echo "         $2"; }

# ── Platform (mirrors detect_platform in the hook) ──────────────────

case "$(uname -s)" in
    Darwin*)              PLATFORM="mac" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="win" ;;
    *)                    PLATFORM="nix" ;;
esac

# Path of the binary inside the release archive
archive_binary() {
    case "${PLATFORM}" in
        mac) echo "bsl-language-server.app/Contents/MacOS/bsl-language-server" ;;
        win) echo "bsl-language-server/bsl-language-server.exe" ;;
        *)   echo "bsl-language-server/bin/bsl-language-server" ;;
    esac
}

data_dir() {
    if [ "${PLATFORM}" = "win" ]; then
        echo "${LOCALAPPDATA}/Programs/bsl-language-server"
    else
        echo "${HOME}/.local/share/bsl-language-server"
    fi
}

# ── Fixture ─────────────────────────────────────────────────────────

setup() {
    SANDBOX="$(mktemp -d)"
    export HOME="${SANDBOX}/home"
    export LOCALAPPDATA="${SANDBOX}/localappdata"
    export CLAUDE_PLUGIN_DATA="${SANDBOX}/plugin-data"
    STUB_BIN="${SANDBOX}/stub-bin"
    RELEASES="${SANDBOX}/releases"
    mkdir -p "${HOME}" "${STUB_BIN}" "${RELEASES}"

    # Fake `curl`: answers the GitHub API with $RELEASES/latest
    # and serves archives from $RELEASES/<version>.zip
    cat > "${STUB_BIN}/curl" << STUB
#!/bin/bash
dest=""; url=""
while [ \$# -gt 0 ]; do
    case "\$1" in
        -o) dest="\$2"; shift 2 ;;
        -*) shift ;;
        *)  url="\$1"; shift ;;
    esac
done
case "\${url}" in
    */releases/latest)
        echo "{\"tag_name\": \"\$(cat "${RELEASES}/latest")\"}" ;;
    */releases/download/*)
        version="\$(echo "\${url}" | sed 's#.*/download/\([^/]*\)/.*#\1#')"
        cp "${RELEASES}/\${version}.zip" "\${dest}" ;;
    *) exit 22 ;;
esac
STUB
    chmod +x "${STUB_BIN}/curl"
    export PATH="${STUB_BIN}:${ORIGINAL_PATH}"
}

ORIGINAL_PATH="${PATH}"

teardown() {
    rm -rf "${SANDBOX}"
}

# Build a fake release archive (platform layout) whose binary is a bash
# script printing its version and args
publish_release() {
    local version="$1"
    local work="${SANDBOX}/build-${version}"
    local binary="${work}/$(archive_binary)"
    mkdir -p "$(dirname "${binary}")"
    cat > "${binary}" << BIN
#!/bin/bash
echo "fake-bsl ${version} \$*"
BIN
    chmod +x "${binary}"
    local top="${binary#"${work}/"}"
    top="${top%%/*}"
    if command -v zip &> /dev/null; then
        (cd "${work}" && zip -qr "${RELEASES}/${version}.zip" "${top}")
    else
        (cd "${work}" && 7z a -tzip -bso0 -bsp0 "$(cygpath -w "${RELEASES}/${version}.zip")" "${top}")
    fi
    echo "${version}" > "${RELEASES}/latest"
}

run_hook() {
    bash "${HOOK}" > "${SANDBOX}/hook.log" 2>&1
}

launcher() {
    echo "${CLAUDE_PLUGIN_DATA}/bin/bsl-language-server"
}

# Runs the launcher the way the LSP client would. On Windows the spawner
# resolves bin/bsl-language-server to bin/bsl-language-server.exe; the fake
# .exe is a bash script, so run it through bash.
run_launcher() {
    if [ "${PLATFORM}" = "win" ]; then
        bash "$(launcher).exe" "$@"
    else
        "$(launcher)" "$@"
    fi
}

# ── Tests ───────────────────────────────────────────────────────────

test_lsp_json_uses_plugin_data_launcher() {
    local cmd
    cmd="$(jq -r '.bsl.command' "${REPO_ROOT}/.lsp.json")"
    if [ "${cmd}" = '${CLAUDE_PLUGIN_DATA}/bin/bsl-language-server' ]; then
        pass ".lsp.json command points to \${CLAUDE_PLUGIN_DATA}/bin/bsl-language-server"
    else
        fail ".lsp.json command points to \${CLAUDE_PLUGIN_DATA}/bin/bsl-language-server" "got: ${cmd}"
    fi
}

test_fresh_install_creates_launcher() {
    setup
    publish_release "v1.0.0"
    run_hook

    local out
    out="$(run_launcher lsp 2>&1)"
    if [ "${out}" = "fake-bsl v1.0.0 lsp" ]; then
        pass "fresh install: launcher in CLAUDE_PLUGIN_DATA runs the server"
    else
        fail "fresh install: launcher in CLAUDE_PLUGIN_DATA runs the server" "got: ${out}; log: $(cat "${SANDBOX}/hook.log")"
    fi
    teardown
}

test_existing_install_without_launcher_gets_launcher() {
    # Users upgrading the plugin already have the server installed and the
    # throttle window may still be active — the launcher must still appear.
    setup
    publish_release "v1.0.0"
    run_hook
    rm -rf "${CLAUDE_PLUGIN_DATA}"
    run_hook

    local out
    out="$(run_launcher lsp 2>&1)"
    if [ "${out}" = "fake-bsl v1.0.0 lsp" ]; then
        pass "existing install (throttled): launcher is (re)created"
    else
        fail "existing install (throttled): launcher is (re)created" "got: ${out}; log: $(cat "${SANDBOX}/hook.log")"
    fi
    teardown
}

test_update_repoints_launcher() {
    setup
    publish_release "v1.0.0"
    run_hook
    publish_release "v1.1.0"
    # Expire the throttle window
    echo '{"version":"v1.0.0","lastUpdate":0}' > "$(data_dir)/SERVER-INFO"
    run_hook

    local out
    out="$(run_launcher lsp 2>&1)"
    if [ "${out}" = "fake-bsl v1.1.0 lsp" ]; then
        pass "update: launcher points to the new version"
    else
        fail "update: launcher points to the new version" "got: ${out}; log: $(cat "${SANDBOX}/hook.log")"
    fi
    teardown
}

test_offline_with_existing_install_keeps_launcher() {
    setup
    publish_release "v1.0.0"
    run_hook
    rm -rf "${CLAUDE_PLUGIN_DATA}"
    echo '{"version":"v1.0.0","lastUpdate":0}' > "$(data_dir)/SERVER-INFO"
    rm -f "${RELEASES}/latest" # API unreachable
    run_hook

    local out
    out="$(run_launcher lsp 2>&1)"
    if [ "${out}" = "fake-bsl v1.0.0 lsp" ]; then
        pass "offline: launcher is created for the installed version"
    else
        fail "offline: launcher is created for the installed version" "got: ${out}; log: $(cat "${SANDBOX}/hook.log")"
    fi
    teardown
}

test_throttle_skips_github_check() {
    setup
    publish_release "v1.0.0"
    run_hook
    rm -f "${RELEASES}/latest" # any API call would now look "offline"
    run_hook

    local log
    log="$(cat "${SANDBOX}/hook.log")"
    if [ "${log}" = "[bsl-language-server] Up to date (v1.0.0)" ]; then
        pass "throttle: no GitHub check within the update interval"
    else
        fail "throttle: no GitHub check within the update interval" "log: ${log}"
    fi
    teardown
}

# ── Run ─────────────────────────────────────────────────────────────

echo "check-bsl-ls.sh"
test_lsp_json_uses_plugin_data_launcher
test_fresh_install_creates_launcher
test_existing_install_without_launcher_gets_launcher
test_update_repoints_launcher
test_offline_with_existing_install_keeps_launcher
test_throttle_skips_github_check

echo
echo "passed: ${PASSED}, failed: ${FAILED}"
[ "${FAILED}" -eq 0 ]
