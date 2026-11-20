#!/bin/bash
# Render ignition/*.bu to .ign. The .ign files hold no secrets and are committed.
set -euo pipefail
cd "$(dirname "$0")/ignition"
for bu in *.bu; do
  docker run --rm -i quay.io/coreos/butane:release --pretty --strict < "$bu" > "${bu%.bu}.ign"
  echo "wrote ignition/${bu%.bu}.ign"
done
