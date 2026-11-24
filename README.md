# chibang

chibang is my home server. It provides ZFS storage, a restic backup target with a nightly offsite copy, and the libvirt host for the Talos Kubernetes VMs defined in [k8s-infra](https://github.com/edy-rus/k8s-infra).

It runs a custom, signed [bootc](https://containers.github.io/bootc/) image built on [uCore HCI](https://projectucore.org), which is Fedora CoreOS with ZFS, KVM/libvirt and Tailscale. The OS is immutable, and everything that makes it *this* server lives in this repo. A reinstall, a new disk or a test VM comes back to the same state from one Ignition URL.

## Layout

```
Containerfile        image = ucore-hci:stable + packages.txt + rootfs/
packages.txt         extra host packages
rootfs/              files copied onto / : systemd units, firewall zones,
                     NetworkManager profiles, polkit rule, sysctl, scripts,
                     image-signing public key
ignition/chibang.bu  first-boot config (Butane): SSH key, hostname, rebase to the image
restore-secrets.sh   puts the secrets back on the host after an install
.github/workflows/   build.yml: builds, pushes and signs the image
                     validate-ignition.yml: butane --strict on ignition/*.bu
```

## What the Image Sets Up

- **ZFS:** imports existing pools on first boot, then unlocks and mounts the pool on every boot.
- **Backups:** a systemd timer mirrors the restic repository offsite every night.
- **Network:** a `br0` bridge over whatever wired NIC the machine has, so VMs sit directly on the LAN. The bridge takes the NIC's MAC address, so the router's DHCP reservation keeps matching. Nothing in the image names a NIC, MAC or IP address.
- **libvirt:** KVM through uCore HCI. A polkit rule lets the admin user manage system libvirt over SSH, which OpenTofu uses.
- **Tailscale:** joins the tailnet automatically on boot.
- **Firewall:** only what the host needs is open on the LAN. Everything else is reachable over Tailscale only.

## Making Changes

Edit the repo and push. CI builds a new image on every change and once a day, to pick up upstream uCore. It signs the image and pushes it to ghcr.io. chibang stages the update automatically and switches to it on the next reboot (`rpm-ostree status` shows what is staged).

The build fails on systemd ordering cycles and `bootc container lint` errors, so a broken image never reaches the host.

Ignition only runs on the very first boot, so do not put configuration there. It belongs in `rootfs/` or the Containerfile.

### Versions and Tags

Each build is versioned `<Fedora major>.<YYYYMMDD>.<n>`, for example `45.20261122.0`, where `n` counts the builds that day. That is what `rpm-ostree status` shows. The uCore build it sits on is recorded in the `org.opencontainers.image.base.name` and `base.digest` labels.

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

## Installing

The same steps work on bare metal or in a VM:

```
sudo coreos-installer install /dev/sdX \
  --ignition-url https://raw.githubusercontent.com/edy-rus/chibang/main/ignition/chibang.bu
```

coreos-installer 0.27.0 and later accept Butane YAML directly, so there is no transpile step. CI checks every change with `butane --strict` instead. An older installer fails with "not a valid Ignition JSON config". In that case, render the config once and pass the file:

```
docker run --rm -i quay.io/coreos/butane:release --strict < ignition/chibang.bu > chibang.ign
sudo coreos-installer install /dev/sdX --ignition-file chibang.ign
```

On first boot the machine rebases to the image unverified, reboots, switches to the signed image and reboots again. This takes a few minutes and needs no input.

For a test VM, copy `ignition/chibang.bu` to a new file, change the hostname, push it and install from that URL. Otherwise the VM shows up as a second chibang on the LAN and the tailnet.

## Restoring Secrets

Secrets are never in the image, in git or on the install media. The only key Ignition installs is the SSH *public* key. Until the secrets are restored, the encrypted dataset stays locked and the offsite mirror cannot run.

Once the host is up on the signed image (`rpm-ostree status` shows `ostree-image-signed:...`), run this from the admin machine:

```
./restore-secrets.sh
```

It copies the secrets from my password store onto the host, unlocks the encrypted dataset and mounts it. After a reinstall, clear the old host key first with `ssh-keygen -R <host>`.

Then check:

```
systemctl --failed
zfs get -H keystatus
systemctl list-timers restic-offsite.timer
```

## Image Signing

Images are signed with cosign. The private key is in my password store and in a repository secret used by CI. The public key ships in the image under `rootfs/etc/pki/containers/`, and the image's `/etc/containers/policy.json` trusts it for `ghcr.io/edy-rus/chibang`. Every update is verified before it is staged.
