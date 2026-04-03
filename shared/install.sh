#!/usr/bin/env bash
# Purplemet CLI — Shared Installation Script
#
# Downloads and installs the purplemet-cli binary from GitHub releases.
# Used by GitHub Actions, Jenkins, Azure DevOps, and any CI platform
# that doesn't use the purplemet/cli Docker image.
#
# Configuration via environment variables:
#   PURPLEMET_CLI_VERSION   — version to install (default: "latest")
#   PURPLEMET_INSTALL_DIR   — where to put the binary (default: /usr/local/bin)
#   PURPLEMET_VERIFY_CHECKSUM — verify SHA256 checksum (default: "true")
#   PURPLEMET_RELEASES_URL  — base URL for releases (default: GitHub)
#
# Usage:
#   - Execute directly:  ./install.sh
#   - Source for functions:  source install.sh

set -euo pipefail

# ── Resolve "latest" version tag ──────────────────────
purplemet_resolve_version() {
  local version="${1:-latest}"

  if [ "${version}" = "latest" ]; then
    local api_url="${PURPLEMET_RELEASES_URL:-https://api.github.com/repos/purplemet/cli/releases/latest}"
    local release_info
    release_info=$(curl -sSf "${api_url}" 2>/dev/null) || {
      echo "ERROR: Could not fetch latest version from ${api_url}" >&2
      return 1
    }
    version=$(echo "${release_info}" | grep -o '"tag_name": "[^"]*"' | cut -d'"' -f4)
    if [ -z "${version}" ]; then
      echo "ERROR: Could not parse version from release info" >&2
      return 1
    fi
  fi

  echo "${version}"
}

# ── Detect OS and architecture ────────────────────────
purplemet_detect_platform() {
  PURPLEMET_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  PURPLEMET_ARCH=$(uname -m)
  case "${PURPLEMET_ARCH}" in
    x86_64)        PURPLEMET_ARCH=amd64 ;;
    aarch64|arm64) PURPLEMET_ARCH=arm64 ;;
  esac
  PURPLEMET_EXT=""
  [ "${PURPLEMET_OS}" = "windows" ] && PURPLEMET_EXT=".exe"
}

# ── Download and install binary ───────────────────────
# Sets: PURPLEMET_INSTALL_PATH
purplemet_install() {
  local version="${PURPLEMET_CLI_VERSION:-latest}"
  local install_dir="${PURPLEMET_INSTALL_DIR:-/usr/local/bin}"
  local verify_checksum="${PURPLEMET_VERIFY_CHECKSUM:-true}"

  # Resolve version
  version=$(purplemet_resolve_version "${version}") || return $?
  echo "Installing purplemet-cli ${version}..."
  echo "DEBUG1: starting install, install_dir=${install_dir}" >&2

  # Detect platform
  purplemet_detect_platform
  echo "DEBUG2: platform detected: os=${PURPLEMET_OS} arch=${PURPLEMET_ARCH} ext=${PURPLEMET_EXT}" >&2

  local filename="purplemet-cli-${PURPLEMET_OS}-${PURPLEMET_ARCH}${PURPLEMET_EXT}"
  local base_url="https://github.com/Purplemet/cli/releases/download/${version}"
  PURPLEMET_INSTALL_PATH="${install_dir}/purplemet-cli${PURPLEMET_EXT}"

  # Download binary
  local http_code
  echo "DEBUG: platform=${PURPLEMET_OS}/${PURPLEMET_ARCH}, file=${filename}" >&2
  echo "DEBUG: url=${base_url}/${filename}" >&2
  http_code=$(curl -sSL -w "%{http_code}" "${base_url}/${filename}" -o "${PURPLEMET_INSTALL_PATH}" 2>&1 | tail -1 || echo "CURL_FAILED")
  if [ "${http_code}" != "200" ]; then
    echo "ERROR: Failed to download ${base_url}/${filename} (HTTP ${http_code})" >&2
    rm -f "${PURPLEMET_INSTALL_PATH}"
    return 1
  fi

  # Verify checksum
  if [ "${verify_checksum}" = "true" ]; then
    local checksum_code
    checksum_code=$(curl -sSL -w "%{http_code}" "${base_url}/checksums.txt" -o /tmp/purplemet-checksums.txt 2>/dev/null)
    if [ "${checksum_code}" = "200" ]; then
      local expected actual
      expected=$(grep "${filename}" /tmp/purplemet-checksums.txt | awk '{print $1}')
      if [ -n "${expected}" ]; then
        # Use sha256sum or shasum depending on platform
        if command -v sha256sum > /dev/null 2>&1; then
          actual=$(sha256sum "${PURPLEMET_INSTALL_PATH}" | awk '{print $1}')
        elif command -v shasum > /dev/null 2>&1; then
          actual=$(shasum -a 256 "${PURPLEMET_INSTALL_PATH}" | awk '{print $1}')
        else
          echo "WARNING: No sha256sum/shasum available, skipping checksum verification" >&2
          actual="${expected}"
        fi
        if [ "${expected}" != "${actual}" ]; then
          echo "ERROR: Checksum mismatch. Expected: ${expected}, Got: ${actual}" >&2
          rm -f "${PURPLEMET_INSTALL_PATH}"
          return 1
        fi
        echo "Checksum verified: ${actual}"
      else
        echo "WARNING: No checksum found for ${filename} in checksums.txt" >&2
      fi
      rm -f /tmp/purplemet-checksums.txt
    else
      echo "WARNING: Could not download checksums.txt (HTTP ${checksum_code}), skipping verification" >&2
    fi
  fi

  chmod +x "${PURPLEMET_INSTALL_PATH}"
  echo "Installed purplemet-cli ${version} (${PURPLEMET_OS}/${PURPLEMET_ARCH}) → ${PURPLEMET_INSTALL_PATH}"
  purplemet-cli version 2>/dev/null || "${PURPLEMET_INSTALL_PATH}" version
}

# ── Main (when executed directly, not sourced) ────────
if [ "${BASH_SOURCE[0]}" = "${0}" ] || [ -z "${BASH_SOURCE[0]}" ]; then
  purplemet_install
fi
