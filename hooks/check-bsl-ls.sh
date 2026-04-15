#!/bin/bash

# Check if BSL Language Server is installed and available in PATH

BSL_LS_VERSION="0.29.0"
BSL_LS_REPO="1c-syntax/bsl-language-server"
INSTALL_DIR="${HOME}/.local/bin"

if command -v bsl-language-server &> /dev/null; then
    echo "[bsl-language-server] Found in PATH: $(command -v bsl-language-server)"
    exit 0
fi

echo "[bsl-language-server] Not found in PATH. Attempting to install..."

# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*)   ARCHIVE="bsl-language-server_nix.zip" ;;
    Darwin*)  ARCHIVE="bsl-language-server_mac.zip" ;;
    MINGW*|MSYS*|CYGWIN*)
        echo "[bsl-language-server] Windows detected."
        echo "          Download manually: https://github.com/${BSL_LS_REPO}/releases/latest"
        exit 0
        ;;
    *)
        echo "[bsl-language-server] Unknown OS: ${OS}"
        exit 0
        ;;
esac

DOWNLOAD_URL="https://github.com/${BSL_LS_REPO}/releases/download/v${BSL_LS_VERSION}/${ARCHIVE}"

# Create install directory
mkdir -p "${INSTALL_DIR}"

# Download and extract
TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" EXIT

echo "[bsl-language-server] Downloading v${BSL_LS_VERSION} for ${OS}..."

if command -v curl &> /dev/null; then
    curl -fsSL -o "${TMPDIR}/${ARCHIVE}" "${DOWNLOAD_URL}"
elif command -v wget &> /dev/null; then
    wget -q -O "${TMPDIR}/${ARCHIVE}" "${DOWNLOAD_URL}"
else
    echo "[bsl-language-server] Neither curl nor wget found. Cannot download."
    echo "          Install manually: https://github.com/${BSL_LS_REPO}/releases/latest"
    exit 0
fi

if [ $? -ne 0 ]; then
    echo "[bsl-language-server] Download failed."
    echo "          Install manually: https://github.com/${BSL_LS_REPO}/releases/latest"
    exit 0
fi

echo "[bsl-language-server] Extracting..."

if command -v unzip &> /dev/null; then
    unzip -q -o "${TMPDIR}/${ARCHIVE}" -d "${TMPDIR}/extracted"
else
    echo "[bsl-language-server] unzip not found. Cannot extract."
    echo "          Install manually: https://github.com/${BSL_LS_REPO}/releases/latest"
    exit 0
fi

# Find the binary in extracted files and install it
BINARY=$(find "${TMPDIR}/extracted" -name "bsl-language-server" -type f 2>/dev/null | head -1)

if [ -z "${BINARY}" ]; then
    # Try alternative name patterns
    BINARY=$(find "${TMPDIR}/extracted" -name "bsl-ls" -type f 2>/dev/null | head -1)
fi

if [ -z "${BINARY}" ]; then
    # Find any executable
    BINARY=$(find "${TMPDIR}/extracted" -type f -executable 2>/dev/null | head -1)
fi

if [ -n "${BINARY}" ]; then
    cp "${BINARY}" "${INSTALL_DIR}/bsl-language-server"
    chmod +x "${INSTALL_DIR}/bsl-language-server"
    echo "[bsl-language-server] Installed to ${INSTALL_DIR}/bsl-language-server"

    # Check if INSTALL_DIR is in PATH
    if [[ ":${PATH}:" != *":${INSTALL_DIR}:"* ]]; then
        echo "[bsl-language-server] Warning: ${INSTALL_DIR} is not in PATH."
        echo "          Add to PATH: export PATH=\"${INSTALL_DIR}:\${PATH}\""
    fi
else
    echo "[bsl-language-server] Could not find binary in archive."
    echo "          Install manually: https://github.com/${BSL_LS_REPO}/releases/latest"
fi

exit 0
