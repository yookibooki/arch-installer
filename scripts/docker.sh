#!/usr/bin/env bash
set -euo pipefail

sudo usermod -aG docker "$USER"
