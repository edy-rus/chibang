#!/bin/bash
# Copy the local restic repo offsite (MEGA S4), append only. Credentials are in
# core's rclone.conf (restored from pass by restore-secrets.sh), not in the image.
#
# `copy`, not `sync`: this script never deletes offsite, and the bucket policy
# denies deletes for this key, so a bad prune, deleted files or ransomware on
# chibang (which holds the key) cannot reach the offsite copy. restic writes
# every file once and never edits it, so `--immutable` turns a file whose size
# or timestamp changed into a failed run instead of an overwrite. Existing
# offsite objects are never replaced. Bit rot is ZFS's job: checksums make a
# corrupted local read fail instead of returning bad data. Lock files are
# the only files restic deletes as normal work, so they stay local.
# Cost: prune frees no space offsite. Clean it up deliberately from the laptop.
#
# Locks: chibang has no restic password, so it cannot read a lock, only its
# timestamp. A running restic refreshes its lock every 5 minutes, and restic
# itself treats a lock untouched for 30 minutes as stale. So a fresh lock
# means "wait", and a stale one (a client that crashed or slept mid backup)
# only gets a warning, because copying immutable files around it is safe.
set -euo pipefail
R=/var/hdd_pool/transfer/restic; D=mega:backup/
STALE_MIN=30      # restic's own stale lock age
WAIT_MAX_MIN=180  # give a running backup this long before giving up

[ -f "$R/config" ] && [ -d "$R/data" ]            || { echo "ABORT: local repo missing"; exit 1; }
rclone cat "${D}config" | cmp -s - "$R/config"    || { echo "ABORT: remote is not the same repo"; exit 1; }

waited=0
while [ -n "$(find "$R/locks" -type f -mmin -"$STALE_MIN" 2>/dev/null)" ]; do
  [ "$waited" -lt "$WAIT_MAX_MIN" ] || { echo "ABORT: repo still locked by a running backup or prune after ${WAIT_MAX_MIN} min"; exit 1; }
  echo "repo locked by a running backup or prune, waiting 5 min (${waited}/${WAIT_MAX_MIN})"
  sleep 300; waited=$((waited + 5))
done
stale=$(find "$R/locks" -type f 2>/dev/null | wc -l)
[ "$stale" -eq 0 ] || echo "WARNING: ${stale} stale lock(s) older than ${STALE_MIN} min. A client ended without unlocking: run 'restic unlock' there. Copying anyway."

rclone copy "$R" "$D" --immutable --exclude 'locks/**' --stats 5m --stats-one-line -v

# Prove it worked: every local snapshot must now exist offsite.
missing=$(comm -23 <(ls "$R/snapshots" | sort) <(rclone lsf "${D}snapshots/" | sort))
[ -z "$missing" ] || { echo "ERROR: snapshots not offsite: $(echo $missing | tr ' ' ',')"; exit 1; }
newest=$(ls -t "$R/snapshots" | head -1)
echo "OK: all $(ls "$R/snapshots" | wc -l) snapshots offsite, newest ${newest:0:8} from $(date -r "$R/snapshots/$newest" '+%F %R %Z')"
