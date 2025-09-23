#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

info(){ printf '\e[32m[INFO]\e[0m %s\n' "$1"; }
step(){ printf '\e[34m[STEP]\e[0m %s\n' "$1"; }
trap 'exit 1' ERR

PACMAN_PKGS=(golangci-lint xorg-xsetroot base-devel alsa-utils btop dmenu docker docker-compose git i3-wm iwd neovim noto-fonts-emoji openssh postgresql redshift tmux unzip nano xclip xorg-server xorg-xinit xorg-xrandr jq libx11 libxft)
AUR_PKGS=(yay-bin koreader-bin windsurf ttf-firacode-nerd uv anydesk-bin brave-bin visual-studio-code-bin)

check_priv() {
  [[ $EUID -eq 0 ]] && exit 1
  sudo -v || exit 1
}

ensure_yay() {
  command -v yay &>/dev/null && return
  if ! command -v git &>/dev/null; then
    sudo pacman -S --noconfirm --needed git base-devel
  fi
  local tmp=$(mktemp -d)
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
  (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
  rm -rf "$tmp"
  command -v yay >/dev/null || exit 1
}

setup_mirror_updater() {
  sudo mkdir -p /usr/local/bin
  sudo tee /usr/local/bin/update-mirrorlist.sh >/dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
curl -fsSo /etc/pacman.d/mirrorlist "https://archlinux.org/mirrorlist/?country=all&protocol=https&ip_version=4&use_mirror_status=on"
sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist
awk '!seen[$0]++' /etc/pacman.d/mirrorlist > /tmp/mirrorlist.tmp && mv /tmp/mirrorlist.tmp /etc/pacman.d/mirrorlist
EOF
  sudo chmod +x /usr/local/bin/update-mirrorlist.sh
  sudo /usr/local/bin/update-mirrorlist.sh
  sudo tee /etc/systemd/system/update-mirrorlist.service >/dev/null <<'EOF'
[Unit]
Description=Update Arch Linux mirrorlist
[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-mirrorlist.sh
EOF
  sudo tee /etc/systemd/system/update-mirrorlist.timer >/dev/null <<'EOF'
[Unit]
Description=Run update-mirrorlist.service every 3 days
[Timer]
OnUnitActiveSec=3d
Persistent=true
[Install]
WantedBy=timers.target
EOF
  sudo systemctl enable --now update-mirrorlist.timer
}

install_packages() {
  sudo pacman -Syu --noconfirm --needed "${PACMAN_PKGS[@]}"
  ensure_yay
  yay -S --noconfirm --needed "${AUR_PKGS[@]}" || true
}

setup_st() {
  local tmp=$(mktemp -d)
  curl -fsL https://dl.suckless.org/st/st-0.9.3.tar.gz | tar -xz --strip-components=1 -C "$tmp"
  sed -i "s/static char \*font = .*/static char *font = \"FiraCode Nerd Font Mono:pixelsize=21:antialias=true:autohint=true\";/" "$tmp/config.h"
  sed -i "s/static int borderpx = .*/static int borderpx = 0;/" "$tmp/config.h"
  sed -i "s/static unsigned int blinktimeout = .*/static unsigned int blinktimeout = 0;/" "$tmp/config.h"
  sed -i "s/static unsigned int cursorshape = .*/static unsigned int cursorshape = 4;/" "$tmp/config.h"
  sed -i "s|^X11INC = .*|X11INC = /usr/include|" "$tmp/config.mk"
  sed -i "s|^X11LIB = .*|X11LIB = /usr/lib|" "$tmp/config.mk"
  (cd "$tmp" && make && sudo make install)
  rm -rf "$tmp"
}

setup_lazyvim() {
  rm -rf "${HOME}/.config/nvim"
  git clone --depth 1 https://github.com/LazyVim/starter "${HOME}/.config/nvim"
  rm -rf "${HOME}/.config/nvim/.git" || true
}

write_i3() {
  mkdir -p "${HOME}/.config/i3"
  cat >"${HOME}/.config/i3/config" <<'EOF'
set $mod Mod4
mode "x"{
    bindsym l exec xrandr --output eDP-1 --auto --output HDMI-1 --off; mode "default"
    bindsym e exec xrandr --output HDMI-1 --auto --output eDP-1 --off; mode "default"
    bindsym p exec systemctl poweroff; mode "default"
    bindsym r exec systemctl reboot; mode "default"
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+x mode "x"
focus_follows_mouse no
default_border none 
hide_edge_borders smart
focus_on_window_activation smart
assign [class="^Brave-browser$"] 1
assign [class="^st$"] 2
assign [class="^Windsurf$"] 3
assign [class="^code$"] 3
bindsym $mod+b workspace number 1; exec brave
bindsym $mod+Return workspace number 2; exec st -e tmux new -A -s main
bindsym $mod+w workspace number 3; exec windsurf
bindsym $mod+c workspace number 3; exec code
bindsym $mod+d exec --no-startup-id dmenu_run
bindsym $mod+q kill
for_window [title="^Scratchpad$"] move to scratchpad
bindsym $mod+Shift+Return exec st -t Scratchpad -e tmux new -A -s main
bindsym $mod+minus scratchpad show
bindsym $mod+Shift+v split v
bindsym $mod+Shift+h split h
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right
bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+5 workspace number 5
bindsym $mod+6 workspace number 6
bindsym $mod+7 workspace number 7
bindsym $mod+8 workspace number 8
bindsym $mod+9 workspace number 9
bindsym $mod+0 workspace number 10
bindsym $mod+Shift+1 move container to workspace number 1
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move container to workspace number 3
bindsym $mod+Shift+4 move container to workspace number 4
bindsym $mod+Shift+5 move container to workspace number 5
bindsym $mod+Shift+6 move container to workspace number 6
bindsym $mod+Shift+7 move container to workspace number 7
bindsym $mod+Shift+8 move container to workspace number 8
bindsym $mod+Shift+9 move container to workspace number 9
bindsym $mod+Shift+0 move container to workspace number 10
bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart
EOF
}

write_redshift() { 
  mkdir -p "${HOME}/.config" 
  cat >"${HOME}/.config/redshift.conf" <<'EOF'
[redshift]
temp-day=3000; temp-night=3000; transition=0; adjustment-method=randr; location-provider=manual
[manual]
lat=41.3; lon=69.3
EOF
}

write_tmux() { 
  mkdir -p "${HOME}/.config/tmux" 
  cat >"${HOME}/.config/tmux/tmux.conf" <<'EOF'
set -g mouse on; set -g status off; bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "xclip -sel clip -i"; set -g base-index 1; setw -g pane-base-index 1; unbind C-b; set -g prefix C-a; bind C-a send-prefix
EOF
}

write_xinit_bash() {
  cat >"${HOME}/.xinitrc" <<'EOF'
redshift &
exec i3
EOF
  chmod +x "${HOME}/.xinitrc"
  cat >"${HOME}/.bash_profile" <<'EOF'
[[ -f ~/.bashrc ]] && . ~/.bashrc
if [ -z "$DISPLAY" ] && [ "${XDG_VTNR:-1}" = 1 ]; then
    exec startx
fi
EOF
  if ! grep -q '# additions from setup script' "${HOME}/.bashrc" 2>/dev/null; then
    cat >>"${HOME}/.bashrc" <<'EOF'

# additions from setup script
alias xc='xclip -selection clipboard'
export EDITOR=nvim
export TERMINAL=st
export PATH="$HOME/.local/bin:/usr/local/go/bin:$HOME/go/bin:$PATH"
EOF
  fi
}

setup_autologin() {
  local vt=${XDG_VTNR:-1}
  local dir="/etc/systemd/system/getty@tty${vt}.service.d"
  sudo mkdir -p "$dir"
  sudo tee "${dir}/override.conf" >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${USER} --noclear %I \$TERM
EOF
}

main() {
  info "Starting Arch+i3 setup"
  check_priv

  setup_st &
  setup_lazyvim &

  setup_mirror_updater
  install_packages

  write_i3
  write_redshift
  write_tmux
  write_xinit_bash

  command -v docker &>/dev/null && ! id -nG "$USER" | grep -qw docker && sudo usermod -aG docker "$USER"

  sudo systemctl enable --now alsa-state.service || true
  setup_autologin

  wait
  sudo systemctl daemon-reload
  info "Done. Reboot."
}

main "$@"