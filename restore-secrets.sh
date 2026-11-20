#!/bin/bash
# Push the host's secrets from pass after first boot. Run from the laptop.
#   ./restore-secrets.sh [ssh-target]     (default core@chibang-1)
set -euo pipefail
host=${1:-core@chibang-1}

pass show zfs/hdd_pool_enc.key \
  | ssh "$host" 'sudo install -D -m 0400 -o root -g root /dev/stdin /etc/zfs/hdd_pool_enc.key'
pass show homelab/chibang/rclone.conf \
  | ssh "$host" 'install -D -m 0600 /dev/stdin ~/.config/rclone/rclone.conf'

# Unlock and mount enc now instead of waiting for the next boot.
ssh "$host" 'sudo zfs load-key hdd_pool/enc 2>/dev/null || true; sudo zfs mount -a; zfs get -H keystatus hdd_pool/enc'
