#!/bin/bash
# Copy the local restic repo offsite (MEGA S4), append only. Credentials are in
# core's rclone.conf (restored from pass by restore-secrets.sh), not in the image.
#
# `copy`, not `sync`: nothing is ever deleted offsite, so a bad prune, deleted
# files or ransomware on chibang cannot reach the offsite copy. restic writes
# every file once and never edits it, so `--immutable` turns a file whose size
# or timestamp changed into a failed run instead of an overwrite. Existing
# offsite objects are never replaced. Bit rot is ZFS's job: checksums make a
# corrupted local read fail instead of returning bad data. Lock files are
# the only files restic deletes as normal work, so they stay local.
# Cost: prune frees no space offsite. Clean it up deliberately from the laptop.
set -euo pipefail
R=/var/hdd_pool/transfer/restic; D=mega:backup/
[ -f "$R/config" ] && [ -d "$R/data" ]            || { echo "ABORT: local repo missing"; exit 1; }
[ -z "$(ls -A "$R/locks" 2>/dev/null)" ]          || { echo "ABORT: repo locked (backup/prune running)"; exit 1; }
rclone cat "${D}config" | cmp -s - "$R/config"    || { echo "ABORT: remote is not the same repo"; exit 1; }
rclone copy "$R" "$D" --immutable --exclude 'locks/**' --stats 5m --stats-one-line -v
