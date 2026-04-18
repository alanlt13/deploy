# deploy

Bootstrap for a fresh Ubuntu cloud VPS, in two stages:

- **`install.sh`** — root-run, box-level. Creates the user, installs base
  packages, configures mail, Tailscale, unattended-upgrades, hardens sshd.
  One command per box.
- **`user.sh`** — user-run, account-level. Sets up `$HOME`-scoped tooling
  (vcpkg today; more later). Idempotent, no sudo. One command per account.

Repo: <https://github.com/alanlt13/deploy>

## Usage

### Stage 1 — box bootstrap (as root)

On a brand-new VPS, SSH in as root and run:

```
bash <(curl -fsSL https://raw.githubusercontent.com/alanlt13/deploy/main/install.sh)
```

Or audit the script before piping it:

```
curl -fsSL https://raw.githubusercontent.com/alanlt13/deploy/main/install.sh | less
```

### Stage 2 — user bootstrap (as your user)

Log in as the non-root user (`alan` by default) and run:

```
bash <(curl -fsSL https://raw.githubusercontent.com/alanlt13/deploy/main/user.sh)
```

This is safe to run on existing accounts — every section is idempotent.

### Overrides

```
TAILSCALE_AUTHKEY=tskey-auth-xxxx \
bash <(curl -fsSL https://raw.githubusercontent.com/alanlt13/deploy/main/install.sh)
```

#### `install.sh` env vars

| Env var              | Default                                 | Notes                                         |
|----------------------|-----------------------------------------|-----------------------------------------------|
| `USERNAME`           | `alan`                                  | Non-root account to create.                   |
| `SSH_PUBKEY_URL`     | `https://github.com/alanlt13.keys`      | GitHub exposes your pubkeys at `/<user>.keys`.|
| `SSH_PUBKEY`         | *(unset)*                               | Literal key; overrides `SSH_PUBKEY_URL`.      |
| `PASSWORDLESS_SUDO`  | `1`                                     | Set `0` to require a password for sudo.       |
| `TAILSCALE_AUTHKEY`  | *(unset)*                               | If set, `tailscale up --ssh` joins the tailnet non-interactively. Generate at <https://login.tailscale.com/admin/settings/keys> (reusable + ephemeral + tagged is a good cattle default). If unset, the package is still installed — finish with `sudo tailscale up --ssh`. |
| `HARDEN_SSH`         | `1`                                     | Drops a sshd_config.d snippet disabling password auth. Only applied if at least one authorized_key is present. |

#### `user.sh` env vars

| Env var              | Default                                 | Notes                                         |
|----------------------|-----------------------------------------|-----------------------------------------------|
| `VCPKG_ROOT`         | `$XDG_DATA_HOME/vcpkg` (`~/.local/share/vcpkg`) | Where vcpkg gets cloned and bootstrapped. Also exported into `~/.bashrc`. |
| `SKIP_VCPKG`         | `0`                                     | Set `1` to skip the vcpkg step entirely.      |
| `SKIP_UV`            | `0`                                     | Set `1` to skip the uv install step.          |

## `install.sh` — what it does

Each section below is a distinct phase in `install.sh`; they run in this order.

### Guards
Asserts Ubuntu + root.

### Create user
Creates `$USERNAME` and adds them to the `sudo` group.

### Authorized keys
Installs `authorized_keys` from `$SSH_PUBKEY_URL` (defaults to GitHub),
or from the literal `$SSH_PUBKEY`. Aborts if no key ends up installed.

### Passwordless sudo
Drops a `NOPASSWD:ALL` sudoers file for the user. Skippable via
`PASSWORDLESS_SUDO=0`.

### apt base
`apt update && dist-upgrade`, installs base packages:
- Build toolchain: `build-essential cmake ninja-build gdb pkg-config autoconf automake libtool`
- Archive tools: `git zip unzip tar`
- Sysadmin tools: `ncdu htop btop tmux`
- Modern CLI: `ripgrep fd-find bat eza zoxide`
- Mail: `mailutils msmtp msmtp-mta`
- Plus: `unattended-upgrades ca-certificates curl gnupg software-properties-common`

### Fastfetch package
Adds `ppa:zhangsongcui3371/fastfetch` and installs the package. The
per-account config + `.profile` login hook live in `user.sh`.

### MOTD trim
Disables noisy MOTD entries: `00-header`, `10-help-text`, `50-motd-news`.

### Mail alias
Installs `/etc/aliases` (root → your email) and runs `newaliases`.

### Tailscale
Installs via the official `tailscale.com/install.sh` and enables the
daemon. If `TAILSCALE_AUTHKEY` is set, runs `tailscale up --ssh` to join
the tailnet non-interactively. Otherwise just leaves the package
installed (daemon running but not joined) — finish with
`sudo tailscale up --ssh` when ready.

### SSH hardening
Drops `/etc/ssh/sshd_config.d/50-hardening.conf` with
`PasswordAuthentication no`. Skipped if no authorized_key is present
(safety). `sshd -t` is run before `systemctl reload ssh`.

**Ordering is deliberate** — Tailscale comes up *before* password auth
is disabled, so Tailscale SSH is already a working escape hatch by the
time sshd is locked down. See "Lockout recovery" below.

### Unattended-upgrades
Drops `/etc/apt/apt.conf.d/52unattended-upgrades-local` — enables the
`-security` origin, emails root on action, auto-reboots at 04:00 if
required.

### Summary
Prints a summary and next-step reminders.

The script is idempotent; re-running should be a no-op.

## `user.sh` — what it does

Run as the non-root user after `install.sh`. No sudo — only touches `$HOME`.

### Guards
Asserts Ubuntu and that the caller is not root.

### Git config
Installs `~/.gitconfig` from `dotfiles/gitconfig` (name + email), only if
the file doesn't already exist — re-runs won't clobber per-account tweaks.

### Fastfetch dotfiles
Drops `~/.config/fastfetch/config.jsonc` and appends an idempotent block
to `~/.profile` that runs `fastfetch` on interactive SSH logins.

### uv
Installs uv via the official `astral.sh/uv/install.sh` if not already
present. Skipped if `~/.local/bin/uv` exists (or `uv` is on PATH).
Disable with `SKIP_UV=1`.

### vcpkg
Clones <https://github.com/microsoft/vcpkg> to `$VCPKG_ROOT`
(default `~/.local/share/vcpkg`), runs `bootstrap-vcpkg.sh -disableMetrics`,
and appends an idempotent block to `~/.bashrc`:

```
# >>> deploy: vcpkg >>>
export VCPKG_ROOT="$HOME/.local/share/vcpkg"
export PATH="$VCPKG_ROOT:$PATH"
# <<< deploy: vcpkg <<<
```

Why `~/.local/share/`: keeps $HOME uncluttered, XDG-compliant, and
vcpkg is inert data (a git checkout + a binary) — the textbook use case
for `XDG_DATA_HOME`.

Skip with `SKIP_VCPKG=1` if the box doesn't need C++ builds.

### Summary
Prints a summary and reminds you to re-source `~/.bashrc`.

The script is idempotent; re-running should be a no-op.

## After install

1. From your laptop: `ssh $USERNAME@<host>` — confirm key-auth works.
2. Drop `/etc/msmtprc` on the box — template at
   [`secrets.example/msmtprc.example`](secrets.example/msmtprc.example).
   Full steps in [`secrets.example/README.md`](secrets.example/README.md).
3. `git config --global user.{name,email}` as needed.
4. Run `user.sh` (stage 2) as the non-root user to finish account-level setup.
5. Optional: disable root SSH login (see secrets README).

## Lockout recovery

"My MacBook (with my only SSH private key) just died. How do I get back in?"

Layered answer, in order of how painful each is:

### 1. Tailscale SSH (primary recovery path)

Your Tailscale *account* is not tied to the MacBook — it's a Google /
Microsoft / GitHub SSO login. On a new device:

1. Install Tailscale, log in with the same SSO account.
2. `ssh alan@<tailnet-name-of-vps>` — you're in.

Tailscale SSH authenticates via tailnet identity, not the old SSH key.
No console access needed, no new key needed, nothing in `authorized_keys`
needs to change.

**Precondition:** the VPS joined the tailnet at bootstrap (you passed
`TAILSCALE_AUTHKEY`) or shortly after (`sudo tailscale up --ssh` from
the console). If you installed and never ran `tailscale up`, this
escape hatch doesn't exist yet — go do it now.

### 2. New key, distributed via GitHub

1. New MacBook → `ssh-keygen -t ed25519`.
2. Paste the new `~/.ssh/id_ed25519.pub` into github.com → Settings → SSH keys.
3. From any entry point that still works (Tailscale, provider console):
   `curl -fsSL https://github.com/alanlt13.keys >> ~/.ssh/authorized_keys`.

GitHub is your "what keys should be trusted" source of truth, so replacing
a laptop is a 2-minute operation as long as GitHub access is intact.

### 3. Provider web console (always works)

Hetzner Cloud Console, DO droplet console, EC2 Serial Console, etc. give
you a virtual TTY as root. The root password is whatever the provider
set (check the provider UI / initial email). `PermitRootLogin no` in
sshd_config only blocks *SSH* root login — it doesn't touch the serial
console. Paste your new pubkey into `/home/alan/.ssh/authorized_keys`,
you're back.

### 4. Backup key (cheap insurance)

Generate a second ed25519 key. Put the private half on a YubiKey or in
1Password. Put the public half on github.com alongside your main key.
Now "MacBook died" and "MacBook + YubiKey died" require different
disasters.

## What it deliberately doesn't do

- No firewall config (ufw) — add later if you need to restrict beyond
  sshd + tailscaled.
- No `PermitRootLogin no` by default — handled in the post-install
  secrets README once you've verified the new user works.
- No Hetzner mirror or other host-specific apt sources.
- No further dotfiles sync beyond the fastfetch config + the SSH-login
  snippet in `~/.profile`.
- No secrets in the repo — credentials are a manual post-step so this
  repo stays safe to keep public.
