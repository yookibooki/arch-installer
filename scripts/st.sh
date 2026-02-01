#!/usr/bin/env bash
set -euo pipefail

ST_DIR="$HOME/.local/src/st"
mkdir -p "$HOME/.local/src"
git clone --depth 1 https://git.suckless.org/st "$ST_DIR" || true
make -C "$ST_DIR"
sed -i 's/pixelsize=12/pixelsize=19/' "$ST_DIR/config.h"
sed -i 's/borderpx = 2/borderpx = 0/' "$ST_DIR/config.h"
sed -i 's/cursorshape = 2/cursorshape = 4/' "$ST_DIR/config.h"
sudo make -C "$ST_DIR" clean install
