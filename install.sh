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
#   TAILSCALE_AUTHKEY   tskey-auth-... from admin console (default: unset)
#   HARDEN_SSH          "1" to disable password SSH       (default: 1)

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

USERNAME="${USERNAME:-alan}"
SSH_PUBKEY_URL="${SSH_PUBKEY_URL:-https://github.com/alanlt13.keys}"
SSH_PUBKEY="${SSH_PUBKEY:-}"
PASSWORDLESS_SUDO="${PASSWORDLESS_SUDO:-1}"
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"
HARDEN_SSH="${HARDEN_SSH:-1}"

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
# Guards
########################################
log "Checking environment"
[[ -r /etc/os-release ]] || die "no /etc/os-release — is this Ubuntu?"
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "this script targets Ubuntu only (found ID=${ID:-unknown})"
[[ "${EUID}" -eq 0 ]] || die "must run as root (try: sudo -i, then re-run)"

########################################
# Create user
########################################
log "Ensuring user '${USERNAME}' exists"
if id -u "${USERNAME}" >/dev/null 2>&1; then
    echo "user ${USERNAME} already exists"
else
    adduser --disabled-password --gecos "" "${USERNAME}"
fi
usermod -aG sudo "${USERNAME}"

########################################
# Authorized keys
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
# Passwordless sudo
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
# apt base
########################################
log "Updating apt and installing base packages"
apt-get update
apt-get -y dist-upgrade
apt-get install -y \
    build-essential cmake ninja-build gdb pkg-config \
    autoconf automake libtool \
    git zip unzip tar \
    ncdu htop btop tmux \
    ripgrep fd-find bat eza zoxide \
    unattended-upgrades \
    mailutils msmtp msmtp-mta \
    ca-certificates curl gnupg software-properties-common

########################################
# Fastfetch package
########################################
# The per-user fastfetch config + .profile login hook live in user.sh.
log "Installing fastfetch"
if ! apt-cache policy fastfetch | grep -q zhangsongcui3371; then
    add-apt-repository -y ppa:zhangsongcui3371/fastfetch
    apt-get update
fi
apt-get install -y fastfetch

########################################
# MOTD trim
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
# Mail alias
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
# Tailscale
########################################
log "Installing Tailscale"
if command -v tailscale >/dev/null 2>&1; then
    echo "tailscale already installed ($(tailscale version | head -1))"
else
    curl -fsSL https://tailscale.com/install.sh | sh
fi
systemctl enable --now tailscaled.service >/dev/null

if [[ -n "${TAILSCALE_AUTHKEY}" ]]; then
    if tailscale status >/dev/null 2>&1; then
        echo "tailscale already up — skipping tailscale up"
    else
        tailscale up --authkey="${TAILSCALE_AUTHKEY}" --ssh
        echo "tailscale: $(tailscale ip -4 | head -1)"
    fi
else
    warn "TAILSCALE_AUTHKEY not set — run 'sudo tailscale up --ssh' and follow the login URL to join the tailnet"
fi

########################################
# SSH hardening
########################################
if [[ "${HARDEN_SSH}" == "1" ]]; then
    log "Hardening sshd (disabling password auth)"
    # Safety check: only harden if we actually installed at least one key.
    if [[ ! -s "${AUTH_KEYS}" ]]; then
        warn "authorized_keys is empty — refusing to disable password auth (would lock you out)"
    else
        cat > /etc/ssh/sshd_config.d/50-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
EOF
        chmod 644 /etc/ssh/sshd_config.d/50-hardening.conf
        if sshd -t; then
            systemctl reload ssh
            echo "  sshd reloaded — password auth disabled"
        else
            warn "sshd config test failed — leaving current config alone"
            rm -f /etc/ssh/sshd_config.d/50-hardening.conf
        fi
    fi
else
    echo "SSH hardening skipped (HARDEN_SSH=${HARDEN_SSH})"
fi

########################################
# Unattended-upgrades
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
# Summary
########################################
log "Done"
ts_status="not joined"
if tailscale status >/dev/null 2>&1; then
    ts_status="$(tailscale ip -4 2>/dev/null | head -1) ($(tailscale status --self --peers=false --json 2>/dev/null | awk -F\" '/"DNSName"/{print $4; exit}' | sed 's/\.$//'))"
fi
cat <<EOF

Bootstrap complete.

  user:              ${USERNAME} (in sudo group)
  passwordless sudo: $([[ "${PASSWORDLESS_SUDO}" == "1" ]] && echo yes || echo no)
  authorized_keys:   $(wc -l < "${AUTH_KEYS}") key(s) at ${AUTH_KEYS}
  tailscale:         ${ts_status}
  ssh password auth: $([[ "${HARDEN_SSH}" == "1" && -f /etc/ssh/sshd_config.d/50-hardening.conf ]] && echo disabled || echo "(image default)")
  mail alias:        $(awk -F: '/^root:/{print $2}' /etc/aliases | xargs || echo "(none)")
  unattended-upgr:   $(systemctl is-active unattended-upgrades.service)

Next steps:
  1. From your laptop: ssh ${USERNAME}@<host>  (verify key-auth works)
     — or, if tailscale is up: ssh ${USERNAME}@<tailscale-name>
  2. If tailscale says "not joined": sudo tailscale up --ssh   (then open the URL it prints)
  3. Drop /etc/msmtprc on the box — see secrets.example/README.md
  4. Optional: also disable root SSH login (secrets README has the drop-in)

EOF
