#!/bin/bash

# BSL Language Server — install & auto-update hook
# Mirrors the logic from vsc-language-1c-bsl extension

BSL_LS_REPO="1c-syntax/bsl-language-server"
UPDATE_INTERVAL=480 # seconds (8 minutes) between GitHub API checks

# ── Platform detection ──────────────────────────────────────────────

detect_platform() {
    OS="$(uname -s)"
    case "${OS}" in
        Linux*)
            PLATFORM="nix"
            ARCHIVE_DIR="bsl-language-server"
            BINARY_SUBPATH="bin/bsl-language-server"
            BINARY_NAME="bsl-language-server"
            DATA_DIR="${HOME}/.local/share/bsl-language-server"
            BIN_DIR="${HOME}/.local/bin"
            ;;
        Darwin*)
            PLATFORM="mac"
            ARCHIVE_DIR="bsl-language-server.app"
            BINARY_SUBPATH="Contents/MacOS/bsl-language-server"
            BINARY_NAME="bsl-language-server"
            DATA_DIR="${HOME}/.local/share/bsl-language-server"
            BIN_DIR="${HOME}/.local/bin"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            PLATFORM="win"
            ARCHIVE_DIR="bsl-language-server"
            BINARY_SUBPATH="bsl-language-server.exe"
            BINARY_NAME="bsl-language-server.exe"
            DATA_DIR="${LOCALAPPDATA:-${USERPROFILE}/AppData/Local}/Programs/bsl-language-server"
            BIN_DIR="${DATA_DIR}"
            ;;
        *)
            echo "[bsl-language-server] Unsupported OS: ${OS}"
            exit 0
            ;;
    esac

    ARCHIVE_NAME="bsl-language-server_${PLATFORM}.zip"
    SERVER_INFO="${DATA_DIR}/SERVER-INFO"
}

# ── SERVER-INFO helpers ─────────────────────────────────────────────

read_installed_version() {
    if [ -f "${SERVER_INFO}" ]; then
        grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "${SERVER_INFO}" 2>/dev/null \
            | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
    fi
}

read_last_update() {
    if [ -f "${SERVER_INFO}" ]; then
        grep -o '"lastUpdate"[[:space:]]*:[[:space:]]*[0-9]*' "${SERVER_INFO}" 2>/dev/null \
            | head -1 | sed 's/.*[[:space:]]//'
    fi
}

write_server_info() {
    local version="$1"
    local timestamp="$2"
    mkdir -p "$(dirname "${SERVER_INFO}")"
    echo "{\"version\":\"${version}\",\"lastUpdate\":${timestamp}}" > "${SERVER_INFO}"
}

# ── Version comparison (true if $1 > $2) ───────────────────────────

version_gt() {
    local v1="${1#v}"
    local v2="${2#v}"
    [ "${v1}" = "${v2}" ] && return 1
    local highest
    highest="$(printf '%s\n%s' "${v1}" "${v2}" | sort -V | tail -1)"
    [ "${highest}" = "${v1}" ]
}

# ── GitHub API ──────────────────────────────────────────────────────

fetch_url() {
    local url="$1"
    if command -v curl &> /dev/null; then
        curl -fsSL "${url}" 2>/dev/null
    elif command -v wget &> /dev/null; then
        wget -qO- "${url}" 2>/dev/null
    else
        return 1
    fi
}

download_file() {
    local url="$1" dest="$2"
    if command -v curl &> /dev/null; then
        curl -fsSL -o "${dest}" "${url}" 2>/dev/null
    elif command -v wget &> /dev/null; then
        wget -q -O "${dest}" "${url}" 2>/dev/null
    else
        return 1
    fi
}

get_latest_version() {
    local response
    response="$(fetch_url "https://api.github.com/repos/${BSL_LS_REPO}/releases/latest")" || return 1
    echo "${response}" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
}

# ── Binary resolution ──────────────────────────────────────────────

find_installed_binary() {
    local version="$1"
    local binary="${DATA_DIR}/${version}/${ARCHIVE_DIR}/${BINARY_SUBPATH}"
    if [ -f "${binary}" ]; then
        echo "${binary}"
    fi
}

# ── Download & install ──────────────────────────────────────────────

download_and_install() {
    local version="$1"
    local url="https://github.com/${BSL_LS_REPO}/releases/download/${version}/${ARCHIVE_NAME}"
    local version_dir="${DATA_DIR}/${version}"

    mkdir -p "${DATA_DIR}"

    local tmpdir
    tmpdir=$(mktemp -d)

    echo "[bsl-language-server] Downloading ${version} (${PLATFORM})..."
    if ! download_file "${url}" "${tmpdir}/${ARCHIVE_NAME}"; then
        rm -rf "${tmpdir}"
        echo "[bsl-language-server] Download failed."
        return 1
    fi

    echo "[bsl-language-server] Extracting..."
    if ! command -v unzip &> /dev/null; then
        rm -rf "${tmpdir}"
        echo "[bsl-language-server] unzip not found."
        return 1
    fi

    mkdir -p "${version_dir}"
    if ! unzip -q -o "${tmpdir}/${ARCHIVE_NAME}" -d "${version_dir}"; then
        rm -rf "${tmpdir}"
        echo "[bsl-language-server] Extraction failed."
        return 1
    fi
    rm -rf "${tmpdir}"

    local binary="${version_dir}/${ARCHIVE_DIR}/${BINARY_SUBPATH}"
    if [ ! -f "${binary}" ]; then
        echo "[bsl-language-server] Binary not found at expected path: ${binary}"
        return 1
    fi

    # Make executable on Unix-like systems
    if [ "${PLATFORM}" != "win" ]; then
        chmod +x "${binary}"
    fi

    # Create symlink / wrapper in BIN_DIR
    mkdir -p "${BIN_DIR}"
    if [ "${PLATFORM}" = "win" ]; then
        # On Windows (Git Bash) create a shell wrapper
        cat > "${BIN_DIR}/bsl-language-server" << WRAPPER
#!/bin/bash
exec "${binary}" "\$@"
WRAPPER
        chmod +x "${BIN_DIR}/bsl-language-server"
    else
        ln -sf "${binary}" "${BIN_DIR}/${BINARY_NAME}"
    fi

    echo "[bsl-language-server] Installed ${version}"
    return 0
}

# ── Cleanup old versions ───────────────────────────────────────────

cleanup_old_versions() {
    local current_version="$1"
    if [ -z "${current_version}" ]; then return; fi

    for dir in "${DATA_DIR}"/v*; do
        [ -d "${dir}" ] || continue
        local dirname
        dirname="$(basename "${dir}")"
        if [ "${dirname}" != "${current_version}" ]; then
            rm -rf "${dir}"
            echo "[bsl-language-server] Removed old version ${dirname}"
        fi
    done
}

# ── Main ────────────────────────────────────────────────────────────

detect_platform

installed_version="$(read_installed_version)"
last_update="$(read_last_update)"
now_ms="$(date +%s)000"

# Throttle: skip GitHub check if updated recently
if [ -n "${last_update}" ] && [ -n "${installed_version}" ]; then
    elapsed_s=$(( (now_ms - last_update) / 1000 ))
    if [ "${elapsed_s}" -lt "${UPDATE_INTERVAL}" ]; then
        binary="$(find_installed_binary "${installed_version}")"
        if [ -n "${binary}" ]; then
            echo "[bsl-language-server] Up to date (${installed_version})"
            exit 0
        fi
    fi
fi

# Query GitHub for latest release
latest_version="$(get_latest_version)"

if [ -z "${latest_version}" ]; then
    if [ -n "${installed_version}" ]; then
        write_server_info "${installed_version}" "${now_ms}"
        echo "[bsl-language-server] Offline, using ${installed_version}"
        exit 0
    fi
    echo "[bsl-language-server] Cannot reach GitHub API and no version installed."
    echo "          Install manually: https://github.com/${BSL_LS_REPO}/releases/latest"
    exit 0
fi

# Compare versions
needs_install=false
if [ -z "${installed_version}" ]; then
    needs_install=true
elif version_gt "${latest_version}" "${installed_version}"; then
    echo "[bsl-language-server] Update available: ${installed_version} → ${latest_version}"
    needs_install=true
else
    binary="$(find_installed_binary "${installed_version}")"
    if [ -z "${binary}" ]; then
        needs_install=true
    fi
fi

if [ "${needs_install}" = true ]; then
    if download_and_install "${latest_version}"; then
        write_server_info "${latest_version}" "${now_ms}"
        cleanup_old_versions "${latest_version}"

        if [ "${PLATFORM}" != "win" ] && [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
            echo "[bsl-language-server] Warning: ${BIN_DIR} is not in PATH."
            echo "          Add: export PATH=\"${BIN_DIR}:\${PATH}\""
        fi
    else
        echo "          Install manually: https://github.com/${BSL_LS_REPO}/releases/latest"
    fi
else
    write_server_info "${installed_version}" "${now_ms}"
    echo "[bsl-language-server] Up to date (${installed_version})"
fi

exit 0
