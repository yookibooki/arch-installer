#!/usr/bin/env bash
set -euo pipefail

sudo mkdir -p /etc/iwd
sudo tee /etc/iwd/main.conf >/dev/null <<'EOF'
[General]
EnableNetworkConfiguration=true

[Network]
EnableIPv6=true
NameResolvingService=systemd
EOF

sudo systemctl enable iwd.service systemd-resolved.service
