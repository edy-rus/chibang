# chibang

chibang is my main home server: ZFS storage for my data, the household restic
backup target (mirrored nightly offsite), and the host for my apps and VMs.

It runs a custom, signed [bootc](https://containers.github.io/bootc/) image built
on [uCore HCI](https://projectucore.org) (Fedora CoreOS with ZFS, KVM/libvirt and
Tailscale). The OS is immutable and everything that makes it *this* server lives
in this repo, so a reinstall, a new disk or a test VM comes back to the same state
from one Ignition URL.

## Layout

```
Containerfile        image = ucore-hci:stable + packages.txt + rootfs/
packages.txt         extra host packages (btop, lftp, ...)
rootfs/              files copied onto / : systemd units, firewalld zones,
                     sysctl, scripts, image-signing public key
ignition/chibang.bu  first-boot config: SSH key, hostname, rebase to the image
build-ign.sh         renders ignition/*.bu -> *.ign (no secrets, committed)
restore-secrets.sh   puts the secrets from pass onto the host after install
.github/workflows/   builds, pushes and signs ghcr.io/edy-rus/chibang
```

What the image sets up:

- **ZFS**: imports existing pools on first boot, then loads encryption keys and
  mounts `hdd_pool` on every boot.
- **Backups**: `restic-offsite.timer` mirrors `/var/hdd_pool/transfer/restic` to
  MEGA S4 every night at 00:00 UTC.
- **Tailscale**: exit node, logs itself in from the auth key on the pool.
- **Firewall**: ssh and cockpit on the LAN, everything on `tailscale0`.

## Making changes

Edit the repo and push. CI builds a new image (on every change and daily, to pick
up upstream uCore), signs it and pushes it to ghcr.io. chibang stages the update
automatically and switches to it on its next reboot (`rpm-ostree status` shows
what is staged). The build fails on systemd ordering cycles and `bootc container
lint` errors, so a broken image never reaches the host.

Ignition only runs on the very first boot, so don't put config there. It belongs
in `rootfs/` or the Containerfile.

## Installing (bare metal or VM)

```
sudo coreos-installer install /dev/sdX \
  --ignition-url https://raw.githubusercontent.com/edy-rus/chibang/main/ignition/chibang.ign
```

First boot rebases to the image unverified, reboots, switches to the signed
image and reboots again. That takes a few minutes and needs no input.

For a test VM, copy `ignition/chibang.bu` to e.g. `chibang-test.bu`, change the
hostname, run `./build-ign.sh`, push and use that URL. Otherwise it shows up
as a second "chibang" on the LAN and tailnet.

## After install: load the secrets

Secrets are never in the image or in git. Once the host is up on the signed
image (`rpm-ostree status` shows `ostree-image-signed:...`), run from the laptop:

```
./restore-secrets.sh            # default target core@chibang-1
```

This copies from pass:

| pass entry                    | goes to                                   |
|-------------------------------|-------------------------------------------|
| `zfs/hdd_pool_enc.key`        | `/etc/zfs/hdd_pool_enc.key` (unlocks `hdd_pool/enc`) |
| `homelab/chibang/rclone.conf` | `~core/.config/rclone/rclone.conf` (offsite mirror) |

It then unlocks and mounts `hdd_pool/enc` right away. Afterwards, check:

```
systemctl --failed
zfs get -H keystatus hdd_pool/enc        # available
systemctl list-timers restic-offsite.timer
```

The Tailscale auth key stays on the pool (`/var/hdd_pool/secrets/tailscale.auth`),
so it doesn't need restoring.

## Signing (one-time, already done)

Images are signed with cosign. The private key is in pass as
`homelab/chibang/cosign.key` and in the repo secret `SIGNING_SECRET`. The public
key is `rootfs/etc/pki/containers/chibang.pub`, and the image's
`/etc/containers/policy.json` trusts it for `ghcr.io/edy-rus/chibang`, so every
update is verified before it is staged.
