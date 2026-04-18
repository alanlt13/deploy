#!/usr/bin/env bash
# User-level bootstrap for a fresh account. Run after install.sh, as the
# unprivileged user (not root). Touches only $HOME — no sudo required.
#
# Usage (after logging in as $USERNAME):
#   bash <(curl -fsSL https://raw.githubusercontent.com/alanlt13/deploy/main/user.sh)
#
# Env vars (all optional):
#   VCPKG_ROOT          where to clone vcpkg      (default: $XDG_DATA_HOME/vcpkg, i.e. ~/.local/share/vcpkg)
#   SKIP_VCPKG          "1" to skip vcpkg         (default: 0)
#   SKIP_UV             "1" to skip uv            (default: 0)

set -euo pipefail

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
VCPKG_ROOT="${VCPKG_ROOT:-$XDG_DATA_HOME/vcpkg}"
SKIP_VCPKG="${SKIP_VCPKG:-0}"
SKIP_UV="${SKIP_UV:-0}"

REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/alanlt13/deploy/main}"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

# Fetch a file from the repo (used for dotfiles when running via curl|bash).
# If the script is executed from a local checkout, prefer the local copy.
fetch_asset() {
    local rel="$1" dest="$2"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
    if [[ -n "${script_dir}" && -f "${script_dir}/${rel}" ]]; then
        install -m 644 "${script_dir}/${rel}" "${dest}"
    else
        curl -fsSL "${REPO_RAW_BASE}/${rel}" -o "${dest}"
    fi
}

########################################
# Guards
########################################
log "Checking environment"
[[ "${EUID}" -ne 0 ]] || die "run as your user, not root (install.sh is the root-bootstrap script)"
[[ -r /etc/os-release ]] || die "no /etc/os-release — is this Ubuntu?"
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "this script targets Ubuntu only (found ID=${ID:-unknown})"

########################################
# Fastfetch dotfiles
########################################
log "Installing fastfetch config + .profile hook"
FF_DIR="${HOME}/.config/fastfetch"
install -d -m 755 "${HOME}/.config"
install -d -m 755 "${FF_DIR}"
fetch_asset "dotfiles/fastfetch/config.jsonc" "${FF_DIR}/config.jsonc"
chmod 644 "${FF_DIR}/config.jsonc"

PROFILE="${HOME}/.profile"
FF_MARKER="# >>> deploy: fastfetch on ssh login >>>"
if [[ -f "${PROFILE}" ]] && grep -qF "${FF_MARKER}" "${PROFILE}"; then
    echo "fastfetch block already present in ${PROFILE}"
else
    cat >> "${PROFILE}" <<EOF

${FF_MARKER}
if [ -n "\$SSH_CONNECTION" ] && [ -t 1 ] && command -v fastfetch >/dev/null 2>&1; then
    echo
    fastfetch
fi
# <<< deploy: fastfetch on ssh login <<<
EOF
    echo "appended fastfetch block to ${PROFILE}"
fi

########################################
# uv
########################################
if [[ "${SKIP_UV}" != "1" ]]; then
    if [[ -x "${HOME}/.local/bin/uv" ]] || command -v uv >/dev/null 2>&1; then
        echo "uv already installed ($(${HOME}/.local/bin/uv --version 2>/dev/null || uv --version 2>/dev/null))"
    else
        log "Installing uv"
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
else
    echo "uv skipped (SKIP_UV=${SKIP_UV})"
fi

########################################
# vcpkg
########################################
if [[ "${SKIP_VCPKG}" != "1" ]]; then
    log "Installing vcpkg to ${VCPKG_ROOT}"
    for dep in git curl tar unzip zip; do
        command -v "${dep}" >/dev/null 2>&1 || die "missing '${dep}' — run install.sh as root first (it installs the build toolchain)"
    done

    install -d -m 755 "$(dirname "${VCPKG_ROOT}")"
    if [[ -d "${VCPKG_ROOT}/.git" ]]; then
        echo "vcpkg already cloned at ${VCPKG_ROOT}"
    else
        git clone https://github.com/microsoft/vcpkg.git "${VCPKG_ROOT}"
    fi

    if [[ -x "${VCPKG_ROOT}/vcpkg" ]]; then
        echo "vcpkg already bootstrapped ($("${VCPKG_ROOT}/vcpkg" version 2>/dev/null | head -1))"
    else
        "${VCPKG_ROOT}/bootstrap-vcpkg.sh" -disableMetrics
    fi

    BASHRC="${HOME}/.bashrc"
    MARKER="# >>> deploy: vcpkg >>>"
    if [[ -f "${BASHRC}" ]] && grep -qF "${MARKER}" "${BASHRC}"; then
        echo "vcpkg block already present in ${BASHRC}"
    else
        cat >> "${BASHRC}" <<EOF

${MARKER}
export VCPKG_ROOT="${VCPKG_ROOT}"
export PATH="\$VCPKG_ROOT:\$PATH"
# <<< deploy: vcpkg <<<
EOF
        echo "appended VCPKG_ROOT export to ${BASHRC}"
    fi
else
    echo "vcpkg skipped (SKIP_VCPKG=${SKIP_VCPKG})"
fi

########################################
# Summary
########################################
log "Done"
needs_gitconfig=0
if [[ ! -f "${HOME}/.gitconfig" ]] || ! git config --global --get user.email >/dev/null 2>&1; then
    needs_gitconfig=1
fi

cat <<EOF

============================================================
User bootstrap complete.
============================================================

Status
------
  fastfetch: ${FF_DIR}/config.jsonc (+ .profile SSH hook)
  uv:        $([[ "${SKIP_UV}" == "1" ]] && echo "(skipped)" || echo "${HOME}/.local/bin/uv")
  vcpkg:     $([[ "${SKIP_VCPKG}" == "1" ]] && echo "(skipped)" || echo "${VCPKG_ROOT}")
  gitconfig: $([[ "${needs_gitconfig}" == "1" ]] && echo "not set (see below)" || echo "$(git config --global user.name) <$(git config --global user.email)>")

EOF

if [[ "${needs_gitconfig}" == "1" ]]; then
    cat <<'EOF'
Next steps (run these now)
--------------------------
  # Set your git identity (edit the values to yours)
  git config --global user.name  "Your Name"
  git config --global user.email "you@example.com"

EOF
fi

cat <<EOF
Then
----
  - Open a new shell (or 'source ~/.bashrc') to pick up VCPKG_ROOT + uv on PATH.
  - Project builds can now use:
      -DCMAKE_TOOLCHAIN_FILE=\$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake

EOF
