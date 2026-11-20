# chibang: ucore-hci plus this host's config and a few extra packages.
# Built and signed by .github/workflows/build.yml; the host tracks :stable.
FROM ghcr.io/ublue-os/ucore-hci:stable

# Set by CI to ghcr.io/<owner>/chibang. Used for the signature policy below.
ARG IMAGE_REF

# Extra packages, one per line in packages.txt ('#' comments allowed).
COPY packages.txt /tmp/packages.txt
RUN pkgs=$(sed 's/#.*//' /tmp/packages.txt | xargs); \
    if [ -n "$pkgs" ]; then dnf -y install $pkgs && dnf clean all; fi; \
    rm -rf /tmp/packages.txt /var/cache/* /var/log/*

# Host config: systemd units, firewalld zones, sysctl, scripts, signing pubkey.
COPY rootfs/ /

# Trust our own signature for ghcr.io/<owner>/chibang, so `rpm-ostree upgrade`
# and the ostree-image-signed rebase verify every update.
RUN test -n "$IMAGE_REF"; \
    jq --arg ref "$IMAGE_REF" \
      '.transports.docker[$ref] = [{"type":"sigstoreSigned","keyPath":"/etc/pki/containers/chibang.pub","signedIdentity":{"type":"matchRepository"}}]' \
      /etc/containers/policy.json > /tmp/policy.json && mv /tmp/policy.json /etc/containers/policy.json; \
    printf 'docker:\n  %s:\n    use-sigstore-attachments: true\n' "$IMAGE_REF" > /etc/containers/registries.d/chibang.yaml

RUN systemctl enable tailscaled.service tailscale-init.service \
      zfs-firstboot-import.service chibang-zfs-load-key.service restic-offsite.timer

# Fail the build on systemd ordering cycles (systemd "fixes" them at boot by
# dropping random jobs, which can leave the host half-booted and unreachable).
RUN ! systemd-analyze verify default.target 2>&1 | grep -i 'ordering cycle'

RUN bootc container lint
