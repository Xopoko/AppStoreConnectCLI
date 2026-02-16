#!/usr/bin/env bash
set -euo pipefail

REPO="Xopoko/AppStoreConnectCLI"
VERSION=""
BIN_DIR=""
UPDATE_PATH="0"

usage() {
  cat >&2 <<'EOF'
ascctl installer

Usage:
  curl -fsSL https://raw.githubusercontent.com/Xopoko/AppStoreConnectCLI/main/install.sh | bash

Options:
  --version vX.Y.Z     Install a specific version (default: latest GitHub release)
  --bin-dir <dir>      Install directory (default: /usr/local/bin if writable, else ~/.local/bin)
  --update-path        If bin-dir isn't in PATH, append it to ~/.zshrc or ~/.bashrc
  -h, --help           Show this help
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

fetch() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url"
    return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO- "$url"
    return 0
  fi
  die "curl or wget is required"
}

download_to() {
  local url="$1"
  local out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 1 -o "$out" "$url"
    return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
    return 0
  fi
  die "curl or wget is required"
}

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return 0
  fi
  die "shasum or sha256sum is required"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || die "--version requires a value"
      VERSION="$2"
      shift 2
      ;;
    --bin-dir)
      [[ $# -ge 2 ]] || die "--bin-dir requires a value"
      BIN_DIR="$2"
      shift 2
      ;;
    --update-path)
      UPDATE_PATH="1"
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  json="$(fetch "https://api.github.com/repos/${REPO}/releases/latest")"
  VERSION="$(printf "%s" "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  [[ -n "$VERSION" ]] || die "Could not determine latest release version"
fi
if [[ "$VERSION" != v* ]]; then
  VERSION="v${VERSION}"
fi

os_raw="$(uname -s)"
case "$os_raw" in
  Darwin) OS="macos" ;;
  Linux) OS="linux" ;;
  *) die "Unsupported OS: ${os_raw}" ;;
esac

arch_raw="$(uname -m)"
case "$arch_raw" in
  arm64|x86_64) ARCH="$arch_raw" ;;
  aarch64) ARCH="arm64" ;;
  *) die "Unsupported architecture: ${arch_raw}" ;;
esac

if [[ "$OS" == "linux" && "$ARCH" == "arm64" ]]; then
  die "linux arm64 is not supported yet (no prebuilt binaries)"
fi

if [[ -z "$BIN_DIR" ]]; then
  if [[ -d "/usr/local/bin" && -w "/usr/local/bin" ]]; then
    BIN_DIR="/usr/local/bin"
  else
    BIN_DIR="${HOME}/.local/bin"
  fi
fi

mkdir -p "$BIN_DIR"

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

download_release_pair() {
  local asset="$1"
  local sha_asset="${asset}.sha256"
  local base="https://github.com/${REPO}/releases/download/${VERSION}"

  download_to "${base}/${asset}" "${tmp}/${asset}" || return 1
  download_to "${base}/${sha_asset}" "${tmp}/${sha_asset}" || return 1
  echo "${asset}"
  return 0
}

asset="ascctl-${VERSION}-${OS}-${ARCH}.tar.gz"
if ! asset="$(download_release_pair "$asset")"; then
  # Backward-compat for v0.1.0 assets.
  if [[ "$OS" == "macos" ]]; then
    asset="ascctl-${VERSION}-macos-latest-${ARCH}.tar.gz"
  else
    asset="ascctl-${VERSION}-ubuntu-latest-${ARCH}.tar.gz"
  fi
  asset="$(download_release_pair "$asset")" || die "Release asset not found for ${OS}/${ARCH} (${VERSION})"
fi

expected="$(awk '{print $1}' "${tmp}/${asset}.sha256" | head -n 1)"
[[ -n "$expected" ]] || die "Could not parse expected sha256"
actual="$(sha256_file "${tmp}/${asset}")"
[[ "$expected" == "$actual" ]] || die "sha256 mismatch: expected ${expected}, got ${actual}"

tar -xzf "${tmp}/${asset}" -C "$tmp"
bin_path="$(find "$tmp" -type f -name ascctl | head -n 1)"
[[ -n "$bin_path" && -f "$bin_path" ]] || die "ascctl binary not found in archive"

install -m 0755 "$bin_path" "${BIN_DIR}/ascctl"

echo "Installed ascctl ${VERSION} to ${BIN_DIR}/ascctl" >&2

bin_in_path="0"
case ":$PATH:" in
  *":${BIN_DIR}:"*) bin_in_path="1" ;;
esac

if [[ "$UPDATE_PATH" == "1" && "$bin_in_path" == "0" ]]; then
  shell="${SHELL:-}"
  if [[ "$shell" == *"zsh" ]]; then
    rc="${HOME}/.zshrc"
  else
    rc="${HOME}/.bashrc"
  fi
  line="export PATH=\"${BIN_DIR}:\$PATH\""
  if [[ -f "$rc" ]] && grep -Fq "$line" "$rc"; then
    :
  else
    {
      echo ""
      echo "# Added by ascctl installer (${VERSION})"
      echo "$line"
    } >> "$rc"
  fi
  echo "Added ${BIN_DIR} to PATH in ${rc}. Restart your shell (or 'source ${rc}')." >&2
elif [[ "$bin_in_path" == "0" ]]; then
  echo "NOTE: ${BIN_DIR} is not on PATH. Re-run with --update-path or add it to your shell rc." >&2
fi

