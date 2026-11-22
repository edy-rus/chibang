# chibang

chibang is a home server: ZFS storage, a restic backup target (mirrored nightly
offsite), and the libvirt host for the Talos Kubernetes VMs defined in
[k8s-infra](https://github.com/edy-rus/k8s-infra).

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
                     NetworkManager profiles, polkit rule, sysctl, scripts,
                     image-signing public key
ignition/chibang.bu  first-boot config (Butane): SSH key, hostname, rebase to the image
restore-secrets.sh   puts the secrets from pass onto the host after install
.github/workflows/   build.yml: builds, pushes and signs ghcr.io/edy-rus/chibang
                     validate-ignition.yml: butane --strict on ignition/*.bu
```

What the image sets up:

- **ZFS**: imports existing pools on first boot, then loads encryption keys and
  mounts `hdd_pool` on every boot.
- **Backups**: `restic-offsite.timer` mirrors `/var/hdd_pool/transfer/restic` to
  MEGA S4 every night at 00:00 UTC.
- **Network**: bridge `br0` (DHCP) over whatever wired NIC the machine has, so
  VMs sit directly on the LAN. `br0` takes the NIC's MAC, so the router's DHCP
  reservation keeps matching. Nothing in the image names a NIC, MAC or IP.
- **libvirt**: KVM via uCore HCI; a polkit rule lets `core` manage system
  libvirt over SSH without a password prompt (used by OpenTofu).
- **Tailscale**: exit node, logs itself in from the auth key on the pool.
- **Firewall**: only ssh (and DHCPv6) on the LAN, everything on `tailscale0`.

## Making changes

Edit the repo and push. CI builds a new image (on every change and daily, to pick
up upstream uCore), signs it and pushes it to ghcr.io. chibang stages the update
automatically and switches to it on its next reboot (`rpm-ostree status` shows
what is staged). The build fails on systemd ordering cycles and `bootc container
lint` errors, so a broken image never reaches the host.

### Versions and tags

Each build is versioned `<Fedora major>.<YYYYMMDD>.<n>`, e.g. `45.20261122.0`
(`n` counts builds that day). That is what `rpm-ostree status` shows. The ucore
build it sits on is recorded in the `org.opencontainers.image.base.name` and
`base.digest` labels.

| Tag | Moves? | Use |
|---|---|---|
| `stable` | yes | what chibang tracks |
| `45` | yes | latest build on Fedora 45 |
| `stable-20261122` | yes, within the day | last build of that day |
| `45.20261122.0` | no | pin or roll back to an exact build |

To go back further than the one rollback deployment:

```
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/edy-rus/chibang:45.20261122.0
# later, back to tracking:
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/edy-rus/chibang:stable
```

Ignition only runs on the very first boot, so don't put config there. It belongs
in `rootfs/` or the Containerfile.

## Installing (bare metal or VM)

```
sudo coreos-installer install /dev/sdX \
  --ignition-url https://raw.githubusercontent.com/edy-rus/chibang/main/ignition/chibang.bu
```

`--ignition-url`/`--ignition-file` take either Butane YAML or Ignition JSON
(coreos-installer 0.27.0+, Fedora CoreOS 45+ Ignition), so there is no transpile
step; CI checks every change with `butane --strict` instead. An older installer
(e.g. an old live ISO) fails with "not a valid Ignition JSON config": render it once with
`docker run --rm -i quay.io/coreos/butane:release --strict < ignition/chibang.bu > chibang.ign`
and pass `--ignition-file chibang.ign`.

First boot rebases to the image unverified, reboots, switches to the signed
image and reboots again. That takes a few minutes and needs no input.

For a test VM, copy `ignition/chibang.bu` to e.g. `chibang-test.bu`, change the
hostname, push and use that URL. Otherwise it shows up
as a second "chibang" on the LAN and tailnet.

## After install: load the secrets

Secrets are never in the image, in git or on the install media; the only key
Ignition installs is the SSH *public* key. Until this step `hdd_pool/enc` stays
locked (`chibang-zfs-load-key` shows as failed) and the offsite mirror can't run.

Once the host is up on the signed image (`rpm-ostree status` shows
`ostree-image-signed:...`), run from the laptop. After a reinstall, clear the
old host key first with `ssh-keygen -R chibang-1`.

```
./restore-secrets.sh            # default target core@chibang-1
```

This copies from pass:

| pass entry                    | goes to                                   |
|-------------------------------|-------------------------------------------|
| `zfs/hdd_pool_enc.key`        | `/etc/zfs/hdd_pool_enc.key` (unlocks `hdd_pool/enc`) |
| `homelab/chibang/rclone.conf` | `~core/.config/rclone/rclone.conf` (offsite mirror) |

It then re-runs `chibang-zfs-load-key` and mounts `hdd_pool/enc` right away. Afterwards, check:

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
