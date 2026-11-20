# chibang

Fedora CoreOS host built from a custom image on top of `ucore-hci:stable`.

```
Containerfile        image = ucore-hci + packages.txt + rootfs/
packages.txt         extra packages (instead of toolbox/distrobox)
rootfs/              files copied onto / (units, firewalld zones, sysctl, scripts, signing pubkey)
ignition/chibang.bu  minimal first-boot config: SSH key, hostname, rebase to the image
build-ign.sh         renders ignition/*.bu -> *.ign (no secrets, committed)
restore-secrets.sh   pushes the ZFS key + rclone.conf from pass after install
.github/workflows/   builds, pushes and signs ghcr.io/edy-rus/chibang daily and on change
```

Config changes go in the image, not in Ignition: commit, CI builds, and the host
picks it up on the next `rpm-ostree upgrade` / reboot. Ignition only runs once.

## One-time setup

1. Push this repo to GitHub as a **public** repo (the host pulls the image and the
   .ign anonymously).
2. Repo secret `SIGNING_SECRET` = `pass show homelab/chibang/cosign.key`.
   The matching public key is `rootfs/etc/pki/containers/chibang.pub`.
3. Run the workflow once, then make the `chibang` package public in
   GitHub → Packages → chibang → Package settings.

## Fresh install

```
coreos-installer install /dev/sdX \
  --ignition-url https://raw.githubusercontent.com/edy-rus/chibang/main/ignition/chibang.ign
```

First boot rebases to the image unverified, reboots, rebases to the signed ref,
reboots again. Then, from the laptop: `./restore-secrets.sh`.
Tailscale logs itself in from the auth key on the pool.

## Moving the existing chibang onto the image

```
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/edy-rus/chibang:stable && sudo systemctl reboot
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/edy-rus/chibang:stable && sudo systemctl reboot
```

Then delete the copies the old Ignition wrote to `/etc` and `/usr/local`, so they
stop shadowing the image's versions:

```
sudo rm /etc/systemd/system/{zfs-load-key,zfs-firstboot-import,restic-offsite,tailscale-init}.service \
        /etc/systemd/system/restic-offsite.timer \
        /etc/firewalld/zones/{FedoraServer,trusted}.xml /etc/sysctl.d/99-tailscale.conf \
        /usr/local/bin/restic-offsite.sh
sudo rm -r /etc/systemd/system/zfs-load-key.service.d    # old drop-in, if present
sudo find /etc/systemd/system -xtype l -delete            # dangling *.wants links
sudo systemctl daemon-reload
sudo systemctl enable tailscaled.service tailscale-init.service zfs-firstboot-import.service \
     chibang-zfs-load-key.service restic-offsite.timer       # re-point enables at the image's units
sudo systemctl reboot
```

Check first with `sudo ostree admin config-diff`: it lists every file in `/etc` that
differs from the image (M = modified, A = added, D = deleted), which also shows any
hand-made changes that still need to go into git.
