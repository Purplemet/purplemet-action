#!/usr/bin/env bash
# Purplemet CLI — Shared Installation Script
#
# Downloads and installs purplemet-cli from GitHub releases.
#
# Two install modes:
#   - "full"   (default): downloads the platform tarball and installs binary
#                         + 72 man pages + bash/zsh/fish completions.
#                         The user gets `man purplemet-cli` working with no
#                         extra steps. Linux/macOS only.
#   - "binary": downloads the raw binary only. Used by CI integrations that
#               only need the executable (no man, no completions).
#               Always used on Windows. Equivalent to the legacy behavior.
#   - "auto"   (the default): tries full first, falls back to binary if the
#                             tarball isn't available (e.g. legacy releases)
#                             or if the embedded installer fails.
#
# Used by GitHub Actions, Jenkins, Azure DevOps, and any CI/user that doesn't
# use the purplemet/cli Docker image.
#
# Configuration via environment variables:
#   PURPLEMET_CLI_VERSION    — version to install (default: "latest")
#   PURPLEMET_INSTALL_MODE   — "auto" | "full" | "binary" (default: "auto")
#   PURPLEMET_INSTALL_DIR    — binary destination dir (default: /usr/local/bin)
#                              — used by binary mode only
#   PURPLEMET_INSTALL_PREFIX — install root for full mode (default: /usr/local,
#                              with ~/.local fallback if not writable)
#   PURPLEMET_VERIFY_CHECKSUM — verify SHA256 checksum (default: "true")
#   PURPLEMET_RELEASES_URL   — base URL for releases (default: GitHub)
#
# Usage:
#   - One-liner (full install with man + completions):
#       curl -fsSL https://github.com/purplemet/cli/releases/latest/download/install.sh | sh
#   - CI / binary-only:
#       PURPLEMET_INSTALL_MODE=binary bash install.sh
#   - Source for functions:
#       source install.sh && purplemet_install        # binary only (legacy API)
#       source install.sh && purplemet_install_full   # binary + man + completions

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
  if [ "${PURPLEMET_OS}" = "windows" ]; then
    PURPLEMET_EXT=".exe"
  fi
}

# ── Verify SHA256 checksum of a file against checksums.txt ──
# Args: <file_path> <filename_in_checksums> <base_url>
# Returns 0 if verified or skipped (with warning), non-zero on real mismatch.
purplemet_verify_checksum() {
  local file_path="$1"
  local filename="$2"
  local base_url="$3"

  local checksum_file
  checksum_file=$(mktemp "${TMPDIR:-/tmp}/purplemet-checksums.XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -f '${checksum_file}'" RETURN

  local checksum_code
  checksum_code=$(curl -sSL -w "%{http_code}" "${base_url}/checksums.txt" -o "${checksum_file}" 2>/dev/null)
  if [ "${checksum_code}" != "200" ]; then
    echo "WARNING: Could not download checksums.txt (HTTP ${checksum_code}), skipping verification" >&2
    return 0
  fi

  local expected actual
  expected=$(grep " ${filename}\$\\| ${filename}$" "${checksum_file}" | awk '{print $1}' | head -1)
  if [ -z "${expected}" ]; then
    echo "WARNING: No checksum found for ${filename} in checksums.txt" >&2
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "${file_path}" | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "${file_path}" | awk '{print $1}')
  else
    echo "WARNING: No sha256sum/shasum available, skipping checksum verification" >&2
    return 0
  fi

  if [ "${expected}" != "${actual}" ]; then
    echo "ERROR: Checksum mismatch for ${filename}. Expected: ${expected}, Got: ${actual}" >&2
    return 1
  fi
  echo "Checksum verified: ${actual}"
}

# ── Download and install binary only (legacy mode) ──────────
# Sets: PURPLEMET_INSTALL_PATH
purplemet_install() {
  local version="${PURPLEMET_CLI_VERSION:-latest}"
  local install_dir="${PURPLEMET_INSTALL_DIR:-/usr/local/bin}"
  local verify_checksum="${PURPLEMET_VERIFY_CHECKSUM:-true}"

  version=$(purplemet_resolve_version "${version}") || return $?
  echo "Installing purplemet-cli ${version} (binary only)..."

  purplemet_detect_platform

  local filename="purplemet-cli-${PURPLEMET_OS}-${PURPLEMET_ARCH}${PURPLEMET_EXT}"
  local base_url="https://github.com/purplemet/cli/releases/download/${version}"

  # Fall back to user-local if the dir isn't writable and no override was given.
  if [ ! -w "${install_dir}" ] && [ -z "${PURPLEMET_INSTALL_DIR:-}" ]; then
    local fallback="${HOME}/.local/bin"
    echo "WARNING: ${install_dir} not writable; falling back to ${fallback}" >&2
    mkdir -p "${fallback}"
    install_dir="${fallback}"
    case ":${PATH}:" in
      *":${fallback}:"*) ;;
      *) export PATH="${fallback}:${PATH}" ;;
    esac
  fi
  PURPLEMET_INSTALL_PATH="${install_dir}/purplemet-cli${PURPLEMET_EXT}"

  local http_code
  http_code=$(curl -sSL -w "%{http_code}" "${base_url}/${filename}" -o "${PURPLEMET_INSTALL_PATH}")
  if [ "${http_code}" != "200" ]; then
    echo "ERROR: Failed to download ${base_url}/${filename} (HTTP ${http_code})" >&2
    rm -f "${PURPLEMET_INSTALL_PATH}"
    return 1
  fi

  if [ "${verify_checksum}" = "true" ]; then
    purplemet_verify_checksum "${PURPLEMET_INSTALL_PATH}" "${filename}" "${base_url}" || {
      rm -f "${PURPLEMET_INSTALL_PATH}"
      return 1
    }
  fi

  chmod +x "${PURPLEMET_INSTALL_PATH}"
  echo "Installed purplemet-cli ${version} (${PURPLEMET_OS}/${PURPLEMET_ARCH}) → ${PURPLEMET_INSTALL_PATH}"
  purplemet-cli version 2>/dev/null || "${PURPLEMET_INSTALL_PATH}" version
}

# ── Download and install full bundle (binary + man + completions) ──
# Sets: PURPLEMET_INSTALL_PATH
purplemet_install_full() {
  local version="${PURPLEMET_CLI_VERSION:-latest}"
  local verify_checksum="${PURPLEMET_VERIFY_CHECKSUM:-true}"

  version=$(purplemet_resolve_version "${version}") || return $?
  purplemet_detect_platform

  # Windows has no .tar.gz archive (no man tradition). Always use binary mode.
  if [ "${PURPLEMET_OS}" = "windows" ]; then
    purplemet_install
    return $?
  fi

  echo "Installing purplemet-cli ${version} (binary + man + completions)..."

  local archive="purplemet-cli-${PURPLEMET_OS}-${PURPLEMET_ARCH}.tar.gz"
  local base_url="https://github.com/purplemet/cli/releases/download/${version}"

  # Pick prefix: explicit override, /usr/local if writable (or sudo NOPASSWD),
  # otherwise ~/.local. The embedded installer escalates with sudo on its own
  # if neither prefix nor parent is writable.
  local prefix="${PURPLEMET_INSTALL_PREFIX:-}"
  if [ -z "${prefix}" ]; then
    if [ -w "/usr/local" ] || [ -w "/usr/local/bin" ]; then
      prefix="/usr/local"
    elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      prefix="/usr/local"
    else
      prefix="${HOME}/.local"
      echo "WARNING: /usr/local not writable; falling back to ${prefix}" >&2
    fi
  fi

  local tmp
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/purplemet-install.XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -rf '${tmp}'" RETURN

  local http_code
  http_code=$(curl -sSL -w "%{http_code}" "${base_url}/${archive}" -o "${tmp}/${archive}")
  if [ "${http_code}" != "200" ]; then
    echo "ERROR: Failed to download ${base_url}/${archive} (HTTP ${http_code})" >&2
    return 1
  fi

  if [ "${verify_checksum}" = "true" ]; then
    purplemet_verify_checksum "${tmp}/${archive}" "${archive}" "${base_url}" || return 1
  fi

  tar -xzf "${tmp}/${archive}" -C "${tmp}"
  local extracted="${tmp}/purplemet-cli-${PURPLEMET_OS}-${PURPLEMET_ARCH}"
  if [ ! -x "${extracted}/install.sh" ]; then
    echo "ERROR: extracted archive does not contain install.sh" >&2
    return 1
  fi

  bash "${extracted}/install.sh" "${prefix}"

  PURPLEMET_INSTALL_PATH="${prefix}/bin/purplemet-cli"

  if [ "${prefix}" = "${HOME}/.local" ]; then
    case ":${PATH}:" in
      *":${prefix}/bin:"*) ;;
      *) export PATH="${prefix}/bin:${PATH}"
         echo "Added ${prefix}/bin to PATH for this shell. Add it to your shell rc to make it permanent." ;;
    esac
  fi

  echo "Installed purplemet-cli ${version} (${PURPLEMET_OS}/${PURPLEMET_ARCH}) with man pages and completions"
  "${PURPLEMET_INSTALL_PATH}" version 2>/dev/null || true
}

# ── Main (when executed directly, not sourced) ────────
if [ "${BASH_SOURCE[0]}" = "${0}" ] || [ -z "${BASH_SOURCE[0]}" ]; then
  case "${PURPLEMET_INSTALL_MODE:-auto}" in
    binary)
      purplemet_install
      ;;
    full)
      purplemet_install_full
      ;;
    auto)
      # Try full install first; fall back to binary-only if it fails (e.g. legacy
      # releases without .tar.gz, or non-writable man/completions paths).
      purplemet_install_full || {
        echo "WARNING: full install failed, falling back to binary-only install" >&2
        purplemet_install
      }
      ;;
    *)
      echo "ERROR: invalid PURPLEMET_INSTALL_MODE='${PURPLEMET_INSTALL_MODE}' (use 'auto', 'full', or 'binary')" >&2
      exit 1
      ;;
  esac
fi
