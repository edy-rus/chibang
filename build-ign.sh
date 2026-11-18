#!/bin/bash
# Build ucore-autorebase.ign from the Butane file, injecting the core user's
# password hash from pass. The .ign contains the hash, so it is git-ignored.
set -euo pipefail
cd "$(dirname "$0")"

CORE_PASSWORD_HASH=$(pass show homelab/chibang/core-hash | head -1)
[[ $CORE_PASSWORD_HASH == \$* ]] || { echo "pass entry homelab/chibang/core-hash missing or not a crypt hash" >&2; exit 1; }
export CORE_PASSWORD_HASH

# Only substitute this one variable; the Butane file has other $VARs (restic script).
envsubst '${CORE_PASSWORD_HASH}' < ucore-autorebase.butane \
  | docker run --rm -i quay.io/coreos/butane:release --pretty --strict \
  > ucore-autorebase.ign
echo "wrote ucore-autorebase.ign (contains the password hash; don't commit it)"
