#!/usr/bin/env bash
set -euo pipefail

sudo systemctl enable --now alsa-state.service || true
