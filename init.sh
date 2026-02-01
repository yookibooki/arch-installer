#!/usr/bin/env bash
set -euo pipefail
(($EUID==0)) && echo "Do not run as root" && exit 1
sudo -v

SETUP_DIR="$HOME/.arch-installer"

PACMAN_PKGS=(zed i3-wm dmenu alsa-utils noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra ttf-firacode-nerd ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-common fontconfig libxft git gitui github-cli neovim chezmoi docker docker-compose postgresql jq fzf btop tmux less pass openssh efibootmgr brightnessctl reflector redshift rsync unzip xclip xdotool iwd zram-generator)
AUR_PKGS=(mods pass-secret-service-bin brave-bin)

git clone --depth 1 https://github.com/yookibooki/arch-installer.git "$SETUP_DIR" || true

sudo pacman -Syu --noconfirm --needed "${PACMAN_PKGS[@]}"

command -v yay >/dev/null || {
    git clone --depth 1 https://aur.archlinux.org/yay-bin.git
    (cd yay-bin && makepkg -si --noconfirm)
    rm -rf yay-bin
}
yay -S --noconfirm --needed "${AUR_PKGS[@]}"

SCRIPTS=(nopass.sh iwd.sh zram.sh reflector.sh docker.sh tty.sh alsa.sh st.sh chezmoi.sh go.sh nvm.sh uv.sh bun.sh)

for script in "${SCRIPTS[@]}"; do
	[[ -f "$SETUP_DIR/scripts/$script" ]] && bash "$SETUP_DIR/scripts/$script"
done

sudo systemctl daemon-reload
echo "Done. Reboot."
