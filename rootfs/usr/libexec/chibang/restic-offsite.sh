#!/bin/bash
# Mirror the local restic repo to offsite (MEGA S4). Credentials are in core's
# rclone.conf (restored from pass by restore-secrets.sh), not in the image.
set -euo pipefail
R=/var/hdd_pool/transfer/restic; D=mega:backup/
[ -f "$R/config" ] && [ -d "$R/data" ]            || { echo "ABORT: local repo missing"; exit 1; }
[ -z "$(ls -A "$R/locks" 2>/dev/null)" ]          || { echo "ABORT: repo locked (backup/prune running)"; exit 1; }
rclone cat "${D}config" | cmp -s - "$R/config"    || { echo "ABORT: remote is not the same repo"; exit 1; }
rclone sync "$R" "$D" --stats 5m --stats-one-line -v
