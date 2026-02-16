#!/usr/bin/env bash
set -euo pipefail

BIN_DIR=""

usage() {
  cat >&2 <<'EOF'
ascctl uninstaller

Usage:
  ./uninstall.sh

Options:
  --bin-dir <dir>    Install directory to remove from (default: /usr/local/bin if writable, else ~/.local/bin)
  -h, --help         Show this help
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin-dir)
      [[ $# -ge 2 ]] || die "--bin-dir requires a value"
      BIN_DIR="$2"
      shift 2
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

if [[ -z "$BIN_DIR" ]]; then
  if [[ -d "/usr/local/bin" && -w "/usr/local/bin" ]]; then
    BIN_DIR="/usr/local/bin"
  else
    BIN_DIR="${HOME}/.local/bin"
  fi
fi

path="${BIN_DIR}/ascctl"
if [[ -f "$path" ]]; then
  rm -f "$path"
  echo "Removed ${path}" >&2
else
  echo "ascctl not found at ${path}" >&2
fi

