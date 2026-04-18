# deploy

Root-run bootstrap for a fresh Ubuntu cloud VPS. Gives you a usable,
key-auth-only user account and a sensible baseline of packages, mail,
and auto-security-updates — in one command.

Repo: <https://github.com/alanlt13/deploy>

## Usage

On a brand-new VPS, SSH in as root and run:

```
bash <(curl -fsSL https://raw.githubusercontent.com/alanlt13/deploy/main/install.sh)
```

Or audit the script before piping it:

```
curl -fsSL https://raw.githubusercontent.com/alanlt13/deploy/main/install.sh | less
```

### Overrides

```
USERNAME=bob \
SSH_PUBKEY_URL=https://github.com/bob.keys \
PASSWORDLESS_SUDO=0 \
bash <(curl -fsSL https://raw.githubusercontent.com/alanlt13/deploy/main/install.sh)
```

| Env var              | Default                                 | Notes                                         |
|----------------------|-----------------------------------------|-----------------------------------------------|
| `USERNAME`           | `alan`                                  | Non-root account to create.                   |
| `SSH_PUBKEY_URL`     | `https://github.com/alanlt13.keys`      | GitHub exposes your pubkeys at `/<user>.keys`.|
| `SSH_PUBKEY`         | *(unset)*                               | Literal key; overrides `SSH_PUBKEY_URL`.      |
| `PASSWORDLESS_SUDO`  | `1`                                     | Set `0` to require a password for sudo.       |

## What it does

1. Asserts Ubuntu + root.
2. Creates `$USERNAME`, adds to `sudo`.
3. Installs `authorized_keys` from GitHub (or `$SSH_PUBKEY`). Aborts if empty.
4. `NOPASSWD:ALL` sudoers drop-in (skippable).
5. `apt update && dist-upgrade`, installs base packages: build toolchain
   (`build-essential cmake ninja-build gdb pkg-config`), sysadmin tools
   (`ncdu htop btop tmux`), modern CLI (`ripgrep fd-find bat eza zoxide`),
   `unattended-upgrades`, mail (`mailutils msmtp msmtp-mta`).
6. Disables noisy MOTD entries (`00-header`, `10-help-text`, `50-motd-news`).
7. Installs `/etc/aliases` (root → your email) and runs `newaliases`.
8. Drops `/etc/apt/apt.conf.d/52unattended-upgrades-local` — enables
   `-security` origin, emails root on action, auto-reboots at 04:00 if
   required.
9. Prints a summary and next-step reminders.

The script is idempotent; re-running should be a no-op.

## After install

1. From your laptop: `ssh $USERNAME@<host>` — confirm key-auth works.
2. Drop `/etc/msmtprc` on the box — template at
   [`secrets.example/msmtprc.example`](secrets.example/msmtprc.example).
   Full steps in [`secrets.example/README.md`](secrets.example/README.md).
3. `git config --global user.{name,email}` as needed.
4. Optional: disable root SSH login (see secrets README).

## What it deliberately doesn't do

- No SSH hardening / firewall — will live in a future `harden.sh`.
- No Tailscale, Hetzner mirror, or other host-specific apt sources.
- No dotfiles sync; no fastfetch.
- No secrets in the repo — credentials are a manual post-step so this
  repo stays safe to keep public.
