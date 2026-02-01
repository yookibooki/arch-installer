#!/usr/bin/env bash
set -euo pipefail

sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
[zram0]
compression-algorithm = lz4
EOF
