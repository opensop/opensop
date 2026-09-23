#!/usr/bin/env bash
#
# install.sh — curl-pipe installer for the OpenSOP CLI
#
# Usage (latest release):
#   curl -fsSL https://raw.githubusercontent.com/opensop/opensop/main/cli/install.sh | bash
#
# Usage (pinned version):
#   curl -fsSL https://raw.githubusercontent.com/opensop/opensop/main/cli/install.sh | bash -s -- --version 0.8.1
#
# Usage (system-wide — writes to /usr/local/bin, may need sudo):
#   curl -fsSL ... | bash -s -- --prefix /usr/local
#
# Flags:
#   --version X.Y.Z     install a specific tagged release (default: latest = main)
#   --prefix  PATH      install directory parent; binary lands at <prefix>/bin/opensop
#                       (default: ~/.local — user-writable, no sudo needed)
#   --dry-run           print what would happen without making changes
#   --allow-unverified  skip checksum verification if no .sha256 file is published yet
#   --help              show this help
#
# Platform notes:
#   Linux   — fully supported; bash 4+ is the distro default everywhere.
#   macOS   — fully supported with bash 4+ (brew install bash).
#             macOS ships bash 3.2 which lacks associative arrays and other
#             bash-4 features the CLI uses.  The installer checks for this
#             and warns clearly if the active bash is too old.
#   Windows — WSL only (install inside a WSL Ubuntu/Debian shell).
#
# Dependencies:
#   bash >= 4.0   required to run opensop
#   jq            required to run opensop  (brew install jq / apt install jq)
#   curl          required for this installer and for opensop upgrade
#
# The installer is idempotent: running it again on an already-installed system
# simply re-downloads and replaces the binary with the same (or newer) version.
#
# Security:
#   The installer fetches a companion <binary>.sha256 checksum file from the
#   same release location and verifies the download before installing.  If no
#   checksum file is published yet, the install aborts unless --allow-unverified
#   is passed.
#   Note: the checksum and the binary come from the same origin — this verifies
#   transfer integrity, not source authenticity.  See cli/README.md.

set -euo pipefail

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

readonly REPO_OWNER="opensop"
readonly REPO_NAME="opensop"
readonly BINARY_NAME="opensop"
readonly RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}"

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

_info()    { printf '\033[2m%s\033[0m\n'    "$*" >&2; }
_ok()      { printf '\033[32m✓\033[0m %s\n' "$*" >&2; }
_warn()    { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }
_die()     { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
_bold()    { printf '\033[1m%s\033[0m' "$*"; }

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #

PIN_VERSION=""
PREFIX="${HOME}/.local"
DRY_RUN=false
ALLOW_UNVERIFIED=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || _die "--version requires a value (e.g. --version 0.8.1)"
      PIN_VERSION="$2"; shift
      ;;
    --prefix)
      [[ $# -ge 2 ]] || _die "--prefix requires a path (e.g. --prefix /usr/local)"
      PREFIX="$2"; shift
      ;;
    --dry-run) DRY_RUN=true ;;
    --allow-unverified) ALLOW_UNVERIFIED=true ;;
    --help|-h)
      grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,2\}//'
      exit 0
      ;;
    *)
      _die "unknown argument '$1' — run with --help for usage"
      ;;
  esac
  shift
done

INSTALL_DIR="${PREFIX}/bin"
INSTALL_PATH="${INSTALL_DIR}/${BINARY_NAME}"

# --------------------------------------------------------------------------- #
# Dependency checks
# --------------------------------------------------------------------------- #

# curl — required for the download itself.
command -v curl >/dev/null 2>&1 \
  || _die "curl is required but was not found on \$PATH"

# bash version check.
# The CLI requires bash 4+ for associative arrays and other 4-only features.
# macOS ships bash 3.2 (GPL-2 licensing prevented Apple from updating it).
_check_bash_version() {
  local major="${BASH_VERSINFO[0]:-0}"
  if [[ "$major" -lt 4 ]]; then
    _warn "your active bash is ${BASH_VERSION} (< 4.0)"
    _warn "opensop requires bash 4+.  On macOS, install a newer bash:"
    _warn "  brew install bash"
    _warn "  echo \$(brew --prefix)/bin/bash | sudo tee -a /etc/shells"
    _warn "  chsh -s \$(brew --prefix)/bin/bash"
    _warn ""
    _warn "On Linux this should not happen — if it does, update bash via your"
    _warn "package manager (apt install bash / yum install bash)."
    _warn ""
    _warn "Continuing install; opensop may not run correctly until bash is updated."
  fi
}

_check_bash_version

# jq — required by opensop at runtime (not by the installer itself).
if ! command -v jq >/dev/null 2>&1; then
  _warn "jq was not found on \$PATH"
  _warn "opensop requires jq to run.  Install it before using opensop:"
  _warn "  macOS:   brew install jq"
  _warn "  Debian:  sudo apt install jq"
  _warn "  Fedora:  sudo dnf install jq"
  _warn ""
  _warn "Continuing install; opensop will tell you when jq is missing."
fi

# --------------------------------------------------------------------------- #
# Determine fetch URL
# --------------------------------------------------------------------------- #

if [[ -n "$PIN_VERSION" ]]; then
  # Normalise: "0.8.1" → "v0.8.1"
  TAG="v${PIN_VERSION#v}"
  FETCH_REF="$TAG"
else
  FETCH_REF="main"
fi

FETCH_URL="${RAW_BASE}/${FETCH_REF}/cli/bin/${BINARY_NAME}"
CHECKSUM_URL="${RAW_BASE}/${FETCH_REF}/cli/bin/${BINARY_NAME}.sha256"

# --------------------------------------------------------------------------- #
# Show plan
# --------------------------------------------------------------------------- #

printf '\n'
printf '  %s\n' "$(_bold "OpenSOP CLI installer")"
printf '\n'
printf '  source  : %s\n' "$FETCH_URL"
printf '  checksum: %s\n' "$CHECKSUM_URL"
printf '  target  : %s\n' "$INSTALL_PATH"
[[ -n "$PIN_VERSION" ]] && printf '  version : %s\n' "$TAG"
$DRY_RUN       && printf '  mode    : DRY RUN (no changes will be made)\n'
printf '\n'

if $DRY_RUN; then
  _info "(dry run — exiting without making changes)"
  exit 0
fi

# --------------------------------------------------------------------------- #
# Download
# --------------------------------------------------------------------------- #

# Create the install directory first so we can place temp files there.
# This guarantees temp file and destination are on the same filesystem —
# making mv(1) an atomic rename (no truncation window, no cp fallback).
if [[ ! -d "$INSTALL_DIR" ]]; then
  _info "creating ${INSTALL_DIR} …"
  mkdir -p "$INSTALL_DIR" || _die "could not create ${INSTALL_DIR} — try --prefix with a writable path, or run with sudo"
fi

if [[ ! -w "$INSTALL_DIR" ]]; then
  _die "${INSTALL_DIR} is not writable.  Try:\n  sudo bash -s -- --prefix /usr/local < install.sh\nor use a writable prefix:\n  bash install.sh --prefix \$HOME/.local"
fi

TMP_BIN="$(mktemp "${INSTALL_DIR}/.opensop-install.XXXXXX")"
TMP_SUM="$(mktemp "${INSTALL_DIR}/.opensop-install-sum.XXXXXX")"
# shellcheck disable=SC2064
trap "rm -f '$TMP_BIN' '$TMP_SUM'" EXIT

_info "downloading ${FETCH_URL} …"
curl_exit=0
curl -fsSL "$FETCH_URL" -o "$TMP_BIN" 2>/dev/null || curl_exit=$?
if [[ $curl_exit -ne 0 ]]; then
  _die "download failed (curl exit ${curl_exit}).  Check your network${PIN_VERSION:+" and that tag ${TAG} exists in ${REPO_OWNER}/${REPO_NAME}"}."
fi

# Sanity-check the download: must contain the version constant.
if ! grep -q "OPENSOP_CLI_VERSION" "$TMP_BIN" 2>/dev/null; then
  _die "downloaded file does not look like an opensop binary (OPENSOP_CLI_VERSION missing).  Aborting."
fi

# Extract the version from the downloaded binary for the confirmation message.
NEW_VERSION="$(grep -m1 'OPENSOP_CLI_VERSION=' "$TMP_BIN" | sed 's/.*OPENSOP_CLI_VERSION="\{0,1\}\([^"]*\)"\{0,1\}.*/\1/')"

# ---- Pin version verification ----
# When --version was specified, compare the requested pin against the version
# embedded in the downloaded binary.  A mismatch means we fetched the wrong
# artifact (tag typo, git redirect, stale CDN cache, etc.) — abort WITHOUT
# touching the destination so the existing install is left untouched.
# Mirror the same check that cmd_upgrade already performs.
if [[ -n "$PIN_VERSION" ]]; then
  normalized_pin="v${PIN_VERSION#v}"
  embedded_tag="v${NEW_VERSION#v}"
  if [[ "$normalized_pin" != "$embedded_tag" ]]; then
    _die "--version ${PIN_VERSION} requested but downloaded binary embeds version ${NEW_VERSION} — aborting to leave any existing install untouched"
  fi
fi

# --------------------------------------------------------------------------- #
# Checksum verification
# --------------------------------------------------------------------------- #

# Portable SHA-256: prefer sha256sum (coreutils), then shasum (macOS), then openssl.
_portable_sha256() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$f" | awk '{print $NF}'
  else
    return 1
  fi
}

sum_curl_exit=0
curl -fsSL "$CHECKSUM_URL" -o "$TMP_SUM" 2>/dev/null || sum_curl_exit=$?
if [[ $sum_curl_exit -eq 0 && -s "$TMP_SUM" ]]; then
  # Verify SHA-256 of the downloaded binary.
  expected_sum="$(awk '{print $1}' "$TMP_SUM" | tr '[:upper:]' '[:lower:]')"
  actual_sum="$(_portable_sha256 "$TMP_BIN" 2>/dev/null)" \
    || _die "no SHA-256 tool found (need sha256sum, shasum, or openssl) — cannot verify download"
  actual_sum="$(printf '%s' "$actual_sum" | tr '[:upper:]' '[:lower:]')"
  if [[ "$actual_sum" != "$expected_sum" ]]; then
    _die "checksum mismatch — download may be corrupt or tampered with.\n  expected: ${expected_sum}\n  got:      ${actual_sum}"
  fi
  _ok "checksum verified (${actual_sum:0:16}…)"
else
  if [[ "$ALLOW_UNVERIFIED" != "true" ]]; then
    _die "no checksum file found at ${CHECKSUM_URL} — cannot verify download integrity.\nPass --allow-unverified to skip (not recommended). See 'Install verification & threat model' in cli/README.md."
  fi
  _warn "no checksum file found — proceeding unverified (--allow-unverified passed)"
fi

# --------------------------------------------------------------------------- #
# Install
# --------------------------------------------------------------------------- #

# Preserve the existing binary's permissions (or default to 0755).
# Portability: GNU stat uses -c '%a'; BSD stat (macOS) uses -f '%Lp' for the
# low permission bits only.  '%OLp' (capital O) on BSD prepends file-type bits
# (e.g. "100755" instead of "755"), which is invalid for chmod(1).  Use '%Lp'.
# Validate the extracted string matches ^[0-7]{3,4}$ before trusting it.
TARGET_MODE="0755"
if [[ -f "$INSTALL_PATH" ]]; then
  existing_mode="$(stat -c '%a' "$INSTALL_PATH" 2>/dev/null \
                || stat -f '%Lp' "$INSTALL_PATH" 2>/dev/null \
                || echo "")"
  if [[ "$existing_mode" =~ ^[0-7]{3,4}$ ]]; then
    TARGET_MODE="$existing_mode"
  fi
fi
chmod "$TARGET_MODE" "$TMP_BIN"

# Atomic rename: TMP_BIN is in the same directory as INSTALL_PATH, so this
# mv is guaranteed same-filesystem and is therefore atomic.
mv "$TMP_BIN" "$INSTALL_PATH"

_ok "installed opensop ${NEW_VERSION} → ${INSTALL_PATH}"

# --------------------------------------------------------------------------- #
# PATH check and post-install hint
# --------------------------------------------------------------------------- #

_on_path=false
if command -v opensop >/dev/null 2>&1; then
  _on_path=true
fi

printf '\n'
if $_on_path; then
  _ok "opensop is on your \$PATH — verify with: opensop --version"
else
  printf '  \033[33m!\033[0m  %s is not on your \$PATH.\n' "$INSTALL_DIR"
  printf '     Add it by appending this line to your shell profile\n'
  printf '     (~/.bashrc, ~/.zshrc, or ~/.profile):\n'
  printf '\n'
  printf '       export PATH="%s:$PATH"\n' "$INSTALL_DIR"
  printf '\n'
  printf '     Then reload your shell:\n'
  printf '       source ~/.bashrc   # or: exec bash\n'
fi

printf '\n'
printf '  %s\n' "Quick start:"
printf '    opensop --version\n'
printf '    opensop help\n'
printf '    opensop run ./your-process.sop.json\n'
printf '\n'
printf '  To upgrade later:\n'
printf '    opensop upgrade\n'
printf '    opensop upgrade --pin 0.9.1\n'
printf '\n'
