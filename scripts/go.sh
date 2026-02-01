#!/usr/bin/env bash
set -euo pipefail

new="$(curl -fsSL 'https://go.dev/dl/?mode=json' | jq -r '.[0].version')"
old="$(/usr/local/go/bin/go version 2>/dev/null | awk '{print $3}' || true)"

[[ "$new" == "$old" ]] && exit 0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "https://go.dev/dl/${new}.linux-amd64.tar.gz" | tar -C "$tmp" -xzf -
sudo rm -rf /usr/local/go
sudo mv "$tmp/go" /usr/local/go
