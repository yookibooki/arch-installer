#!/usr/bin/env bash
set -euo pipefail

echo "$USER ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$USER >/dev/null
