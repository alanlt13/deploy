#!/usr/bin/env bash
# Root-run bootstrap for a fresh Ubuntu cloud VPS.
# Usage (as root on a brand new box):
#   bash <(curl -fsSL https://raw.githubusercontent.com/alanlt13/deploy/main/install.sh)
#
# Env vars (all optional):
#   USERNAME            non-root user to create           (default: alan)
#   SSH_PUBKEY_URL      URL returning one pubkey per line (default: https://github.com/alanlt13.keys)
#   SSH_PUBKEY          literal pubkey, skips URL fetch   (default: unset)
#   PASSWORDLESS_SUDO   "1" to grant NOPASSWD sudo        (default: 1)

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

USERNAME="${USERNAME:-alan}"
SSH_PUBKEY_URL="${SSH_PUBKEY_URL:-https://github.com/alanlt13.keys}"
SSH_PUBKEY="${SSH_PUBKEY:-}"
PASSWORDLESS_SUDO="${PASSWORDLESS_SUDO:-1}"

REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/alanlt13/deploy/main}"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

# Fetch a file from the repo (used for etc/* assets when running via curl|bash).
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
# 1. Guards
########################################
log "Checking environment"
[[ -r /etc/os-release ]] || die "no /etc/os-release — is this Ubuntu?"
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "this script targets Ubuntu only (found ID=${ID:-unknown})"
[[ "${EUID}" -eq 0 ]] || die "must run as root (try: sudo -i, then re-run)"

########################################
# 2. Create user
########################################
log "Ensuring user '${USERNAME}' exists"
if id -u "${USERNAME}" >/dev/null 2>&1; then
    echo "user ${USERNAME} already exists"
else
    adduser --disabled-password --gecos "" "${USERNAME}"
fi
usermod -aG sudo "${USERNAME}"

########################################
# 3. Authorized keys
########################################
log "Installing SSH authorized_keys for ${USERNAME}"
HOME_DIR="$(getent passwd "${USERNAME}" | cut -d: -f6)"
[[ -n "${HOME_DIR}" && -d "${HOME_DIR}" ]] || die "could not resolve home dir for ${USERNAME}"

install -d -m 700 -o "${USERNAME}" -g "${USERNAME}" "${HOME_DIR}/.ssh"
AUTH_KEYS="${HOME_DIR}/.ssh/authorized_keys"
touch "${AUTH_KEYS}"
chown "${USERNAME}:${USERNAME}" "${AUTH_KEYS}"
chmod 600 "${AUTH_KEYS}"

if [[ -n "${SSH_PUBKEY}" ]]; then
    NEW_KEYS="${SSH_PUBKEY}"
else
    NEW_KEYS="$(curl -fsSL "${SSH_PUBKEY_URL}")" || die "failed to fetch pubkeys from ${SSH_PUBKEY_URL}"
fi
NEW_KEYS="$(printf '%s\n' "${NEW_KEYS}" | sed -e 's/[[:space:]]*$//' -e '/^$/d')"
[[ -n "${NEW_KEYS}" ]] || die "no pubkeys collected — refusing to continue (box would be unreachable)"

added=0
while IFS= read -r key; do
    [[ -z "${key}" ]] && continue
    if ! grep -qxF "${key}" "${AUTH_KEYS}"; then
        printf '%s\n' "${key}" >> "${AUTH_KEYS}"
        added=$((added + 1))
    fi
done <<< "${NEW_KEYS}"
echo "authorized_keys: ${added} new key(s) added, $(wc -l < "${AUTH_KEYS}") total"

########################################
# 4. Passwordless sudo
########################################
if [[ "${PASSWORDLESS_SUDO}" == "1" ]]; then
    log "Granting passwordless sudo to ${USERNAME}"
    SUDOERS_FILE="/etc/sudoers.d/90-${USERNAME}"
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${USERNAME}" > "${SUDOERS_FILE}"
    chmod 440 "${SUDOERS_FILE}"
    visudo -c -f "${SUDOERS_FILE}" >/dev/null
else
    echo "passwordless sudo skipped (PASSWORDLESS_SUDO=${PASSWORDLESS_SUDO})"
fi

########################################
# 5. apt base
########################################
log "Updating apt and installing base packages"
apt-get update
apt-get -y dist-upgrade
apt-get install -y \
    build-essential cmake ninja-build gdb pkg-config \
    ncdu htop btop tmux \
    ripgrep fd-find bat eza zoxide \
    unattended-upgrades \
    mailutils msmtp msmtp-mta \
    ca-certificates curl gnupg

########################################
# 6. MOTD trim
########################################
log "Trimming /etc/update-motd.d"
for f in 00-header 10-help-text 50-motd-news; do
    path="/etc/update-motd.d/${f}"
    if [[ -f "${path}" ]]; then
        chmod -x "${path}" || true
        echo "  disabled ${path}"
    fi
done

########################################
# 7. Mail alias
########################################
log "Installing /etc/aliases"
fetch_asset "etc/aliases" /etc/aliases
chmod 644 /etc/aliases
newaliases
if [[ ! -f /etc/msmtprc ]]; then
    warn "/etc/msmtprc is not configured — mail will not be delivered yet"
    warn "see secrets.example/README.md for the post-install step"
fi

########################################
# 8. Unattended-upgrades
########################################
log "Configuring unattended-upgrades"
fetch_asset "etc/52unattended-upgrades-local" /etc/apt/apt.conf.d/52unattended-upgrades-local
chmod 644 /etc/apt/apt.conf.d/52unattended-upgrades-local
# Ensure the periodic config exists (enables auto-download + auto-upgrade).
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF
chmod 644 /etc/apt/apt.conf.d/20auto-upgrades
systemctl enable --now unattended-upgrades.service >/dev/null

########################################
# 9. Summary
########################################
log "Done"
cat <<EOF

Bootstrap complete.

  user:              ${USERNAME} (in sudo group)
  passwordless sudo: $([[ "${PASSWORDLESS_SUDO}" == "1" ]] && echo yes || echo no)
  authorized_keys:   $(wc -l < "${AUTH_KEYS}") key(s) at ${AUTH_KEYS}
  mail alias:        $(awk -F: '/^root:/{print $2}' /etc/aliases | xargs || echo "(none)")
  unattended-upgr:   $(systemctl is-active unattended-upgrades.service)

Next steps:
  1. From your laptop: ssh ${USERNAME}@<host>  (verify key-auth works)
  2. Drop /etc/msmtprc on the box — see secrets.example/README.md
  3. git config --global user.name / user.email as needed
  4. Optional: disable root SSH login once you've verified step 1

EOF
