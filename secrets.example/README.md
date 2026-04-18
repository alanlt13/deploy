# Post-install secrets

`install.sh` leaves the box in a working state but without credentials.
Do these steps manually after the bootstrap finishes.

## 1. Mail (msmtp)

Copy `msmtprc.example` to `/etc/msmtprc`, fill in the four `<...>` placeholders,
and lock it down:

```
sudo install -m 600 -o root -g mail /dev/null /etc/msmtprc
sudo $EDITOR /etc/msmtprc   # paste from your password manager
sudo touch /var/log/msmtp.log && sudo chown root:mail /var/log/msmtp.log && sudo chmod 640 /var/log/msmtp.log
echo "bootstrap test from $(hostname)" | mail -s "msmtp test" root
```

You should get an email at the address set in `/etc/aliases` (root → …).

## 2. (Optional) disable root SSH login

Only do this *after* you have confirmed `ssh <user>@<host>` works from your
laptop. Before running this, also confirm `tailscale status` shows the node
joined and `ssh alan@<tailnet-name>` works — Tailscale SSH is your escape
hatch if the key ever goes bad. See [`../README.md`](../README.md) →
"Lockout recovery" for the full map.

```
sudo tee /etc/ssh/sshd_config.d/50-no-root.conf <<EOF
PermitRootLogin no
PasswordAuthentication no
EOF
sudo systemctl reload ssh
```
