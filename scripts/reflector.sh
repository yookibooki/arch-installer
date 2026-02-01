#!/usr/bin/env bash
set -euo pipefail
sudo mkdir -p /etc/xdg/reflector
sudo tee /etc/xdg/reflector/reflector.conf >/dev/null <<'EOF'
--save /etc/pacman.d/mirrorlist
--protocol https
--latest 50
--sort rate
--number 10
EOF
sudo mkdir -p /etc/systemd/system/reflector.timer.d
sudo tee /etc/systemd/system/reflector.timer.d/override.conf >/dev/null <<'EOF'
[Timer]
OnCalendar=
OnCalendar=72h
AccuracySec=1h
EOF
sudo systemctl enable reflector.timer
