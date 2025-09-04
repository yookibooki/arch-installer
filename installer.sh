#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

info(){ printf '\e[32m[INFO]\e[0m %s\n' "$1"; }
warn(){ printf '\e[33m[WARN]\e[0m %s\n' "$1"; }
err(){ printf '\e[31m[ERROR]\e[0m %s\n' "$1" >&2; }
step(){ printf '\e[34m[STEP]\e[0m %s\n' "$1"; }
trap 'err "Script failed at line $LINENO"; exit 1' ERR

# --------- Configuration ----------
PACMAN_PKGS=( base-devel alsa-utils arch-wiki-lite btop dmenu docker docker-compose git i3-wm intel-ucode iwd linux-firmware neovim noto-fonts-emoji openssh postgresql redshift tmux ttf-firacode-nerd unzip uv nano xclip xorg-server xorg-xinit xorg-xrandr anydesk-bin brave-bin visual-studio-code-bin )
AUR_PKGS=( koreader-bin windsurf )
GO_PKGS=( github.com/cosmtrek/air@latest github.com/golangci/golangci-lint/cmd/golangci-lint@latest golang.org/x/tour@latest golang.org/x/tools/cmd/goimports@latest golang.org/x/tools/gopls@latest honnef.co/go/tools/cmd/staticcheck@latest golang.org/x/tools/cmd/godoc@latest )

MIRROR_URL="https://archlinux.org/mirrorlist/?country=all&protocol=https&ip_version=4&use_mirror_status=on"
DCUZ="Server = http://mirror.dc.uz/arch/\$repo/os/\$arch"

# --------- Privilege check ----------
check_priv() {
  [[ $EUID -eq 0 ]] && { err "Don't run as root. Use a regular user with sudo."; exit 1; }
  sudo -v || { err "Sudo access required."; exit 1; }
}

# --------- Helpers ----------
ensure_yay() {
  if command -v yay &>/dev/null; then
    info "yay exists"
    return
  fi
  step "Installing yay (AUR helper)..."
  sudo pacman -S --noconfirm --needed git base-devel || true
  tmp=$(mktemp -d)
  git clone --depth 1 https://aur.archlinux.org/yay.git "$tmp/yay"
  (cd "$tmp/yay" && makepkg -si --noconfirm)
  rm -rf "$tmp"
  command -v yay >/dev/null || { err "yay install failed"; exit 1; }
}

# --------- Mirrorlist (fast, idempotent-ish) ----------
setup_mirrors() {
  step "Updating pacman mirrorlist..."
  # Initial mirrorlist setup (run once during install)
  sudo curl -fsSLo /etc/pacman.d/mirrorlist "$MIRROR_URL"
  sudo sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist
  sudo sed -i '/mirror\.dc\.uz/d' /etc/pacman.d/mirrorlist
  sudo sed -i '/mirror\.yandex\.ru/d' /etc/pacman.d/mirrorlist
  if ! sudo grep -q 'mirror.dc.uz' /etc/pacman.d/mirrorlist; then
    sudo sed -i "1i$DCUZ" /etc/pacman.d/mirrorlist
  fi
  if ! sudo grep -q 'mirror.yandex.ru' /etc/pacman.d/mirrorlist; then
    sudo sed -i "1iServer = http://mirror.yandex.ru/arch/\$repo/os/\$arch" /etc/pacman.d/mirrorlist
  fi
  # Dedupe lines
  sudo awk '!seen[$0]++' /etc/pacman.d/mirrorlist | sudo tee /etc/pacman.d/mirrorlist >/dev/null
  info "Mirrorlist updated (initial setup)"
}

# --------- Mirrorlist Update Service and Timer ----------
setup_mirrorlist_service() {
  step "Setting up mirrorlist update service and timer..."

  # Write update-mirrorlist.sh
  sudo mkdir -p /usr/local/bin
  sudo tee /usr/local/bin/update-mirrorlist.sh >/dev/null <<'EOF'
#!/bin/bash
set -e
curl -so /etc/pacman.d/mirrorlist "https://archlinux.org/mirrorlist/?country=all&protocol=https&ip_version=4&use_mirror_status=on"
sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist
sed -i '/mirror\.dc\.uz/d' /etc/pacman.d/mirrorlist
sed -i '/mirror\.yandex\.ru/d' /etc/pacman.d/mirrorlist
sed -i '1iServer = http://mirror.dc.uz/arch/$repo/os/$arch' /etc/pacman.d/mirrorlist
sed -i '1iServer = http://mirror.yandex.ru/arch/$repo/os/$arch' /etc/pacman.d/mirrorlist
EOF
  sudo chmod +x /usr/local/bin/update-mirrorlist.sh

  # Write update-mirrorlist.service
  sudo tee /etc/systemd/system/update-mirrorlist.service >/dev/null <<'EOF'
[Unit]
Description=Update Arch Linux mirrorlist

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-mirrorlist.sh
EOF

  # Write update-mirrorlist.timer
  sudo tee /etc/systemd/system/update-mirrorlist.timer >/dev/null <<'EOF'
[Unit]
Description=Run update-mirrorlist.service weekly

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

  # Enable and start the timer
  sudo systemctl enable update-mirrorlist.timer
  sudo systemctl start update-mirrorlist.timer
  info "Mirrorlist update service and timer configured"
}

# --------- Chaotic AUR (minimal) ----------
setup_chaotic() {
  step "Configuring Chaotic AUR (if missing)..."
  if sudo grep -q '^\[chaotic-aur\]' /etc/pacman.conf 2>/dev/null; then
    info "Chaotic already configured"
    return
  fi

  # import key if absent
  if ! sudo pacman-key --list-keys | grep -q 3056513887B78AEB; then
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com || true
    sudo pacman-key --lsign-key 3056513887B78AEB || true
  fi

  # install chaotic keyring/mirrorlist if not installed
  if ! pacman -Qi chaotic-keyring &>/dev/null; then
    sudo pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' || warn "chaotic-keyring install failed"
  fi
  if ! pacman -Qi chaotic-mirrorlist &>/dev/null; then
    sudo pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' || warn "chaotic-mirrorlist install failed"
  fi

  if ! sudo grep -q '^Include = /etc/pacman.d/chaotic-mirrorlist' /etc/pacman.conf; then
    { echo ""; echo "[chaotic-aur]"; echo "Include = /etc/pacman.d/chaotic-mirrorlist"; } | sudo tee -a /etc/pacman.conf >/dev/null
  fi

  # enable multilib if commented
  sudo sed -i "/\[multilib\]/,/Include/ s/^#//" /etc/pacman.conf || true
  info "Chaotic configured (if necessary)"
}

# --------- Packages (single heavy step) ----------
install_packages() {
  step "Updating system and installing pacman packages..."
  sudo pacman -Syu --noconfirm --needed "${PACMAN_PKGS[@]}"
  ensure_yay
  step "Installing AUR packages (yay)..."
  yay -S --noconfirm --nodiffmenu --needed "${AUR_PKGS[@]}" || warn "Some AUR installs may have failed"
}

# --------- Fast, independent installs (parallel where safe) ----------
setup_st() {
  step "Installing st (replace /opt/st)..."
  sudo rm -rf /opt/st
  sudo mkdir -p /opt/st
  curl -fsL https://dl.suckless.org/st/st-0.9.3.tar.gz | sudo tar -xz --strip-components=1 -C /opt/st
  sudo chown -R "$USER:$USER" /opt/st
  info "st installed to /opt/st"
}

setup_lazyvim() {
  step "Installing LazyVim (replace ~/.config/nvim)..."
  rm -rf "${HOME}/.config/nvim"
  git clone --depth 1 https://github.com/LazyVim/starter "${HOME}/.config/nvim"
  rm -rf "${HOME}/.config/nvim/.git" || true
  info "LazyVim installed"
}

setup_node_tools() {
  step "Installing fnm & Gemini CLI (user-local)..."
  if ! command -v fnm &>/dev/null; then
    curl -fsSL https://fnm.vercel.app/install | bash
  fi
  export PATH="$HOME/.fnm:$PATH"
  eval "$(fnm env)" 2>/dev/null || true
  fnm install 24 || true
  if ! npm list -g @google/gemini-cli >/dev/null 2>&1; then
    npm install -g @google/gemini-cli || warn "npm gemini install failed"
  fi
  info "Node tooling done"
}

# go tooling should run only after 'go' package is present
setup_go_tools() {
  step "Installing Go tools..."
  export PATH="$HOME/go/bin:$PATH"
  for pkg in "${GO_PKGS[@]}"; do
    go install "$pkg" || warn "go install failed for $pkg"
  done
  info "Go tools installed"
}

# --------- User/system configs (force-overwrite, no backups) ----------
write_i3() {
  step "Writing i3 config (force overwrite)..."
  mkdir -p "${HOME}/.config/i3"
  cat >"${HOME}/.config/i3/config" <<'EOF'
set $mod Mod4
mode "x"{
    bindsym l exec xrandr --output eDP-1 --auto --output HDMI-1 --off; mode "default"
    bindsym e exec xrandr --output HDMI-1 --auto --output eDP-1 --off; mode "default"
    bindsym p exec sudo systemctl poweroff; mode "default"
    bindsym r exec sudo systemctl reboot; mode "default"
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
bindsym $mod+Shift+1 move workspace 1
bindsym $mod+Shift+2 move workspace 2
bindsym $mod+Shift+3 move workspace 3
bindsym $mod+Shift+4 move workspace 4
bindsym $mod+Shift+5 move workspace 5
bindsym $mod+Shift+6 move workspace 6
bindsym $mod+Shift+7 move workspace 7
bindsym $mod+Shift+8 move workspace 8
bindsym $mod+Shift+9 move workspace 9
bindsym $mod+Shift+0 move workspace 10
bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart
EOF
  info "i3 config written"
}

write_redshift() {
  mkdir -p "${HOME}/.config"
  cat >"${HOME}/.config/redshift.conf" <<'EOF'
[redshift]
temp-day=3000
temp-night=3000
transition=0
adjustment-method=randr
location-provider=manual
[manual]
lat=41.3
lon=69.3
EOF
}

write_gemini() {
  mkdir -p "${HOME}/.gemini"
  cat >"${HOME}/.gemini/settings.json" <<'EOF'
{
  "selectedAuthType": "oauth-personal",
  "mcpServers": {
    "context7": {
      "httpUrl": "https://mcp.context7.com/mcp"
    }
  }
}
EOF
}

write_tmux() {
  mkdir -p "${HOME}/.config/tmux"
  cat >"${HOME}/.config/tmux/tmux.conf" <<'EOF'
set -g mouse on
set -g status off
bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "xclip -sel clip -i"
set -g base-index 1
setw -g pane-base-index 1
unbind C-b
set -g prefix C-a
bind C-a send-prefix
EOF
}

write_xinit_bash() {
  cat >"${HOME}/.xinitrc" <<'EOF'
xrandr --output HDMI-1 --auto --output eDP-1 --off
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

  # ensure .bashrc contains block (idempotent by grep)
  if ! grep -q 'alias xc=' "${HOME}/.bashrc" 2>/dev/null; then
    cat >>"${HOME}/.bashrc" <<'EOF'

# additions from setup script
alias xc='xclip -selection clipboard'
export EDITOR=nvim
export TERMINAL=st
export PATH="\$HOME/.local/bin:\$HOME/go/bin:/usr/local/go/bin:\$HOME/.fnm:\$PATH"
EOF
  fi
}

# --------- autologin (force) ----------
setup_autologin() {
  step "Configuring autologin (force)..."
  local vt=${XDG_VTNR:-1}
  local dir="/etc/systemd/system/getty@tty${vt}.service.d"
  sudo mkdir -p "$dir"
  sudo tee "${dir}/override.conf" >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${USER} --noclear %I \$TERM
EOF
  info "Autologin configured for tty${vt}"
}

# --------- postgres init (guarded) ----------
ensure_postgres() {
  step "Ensuring PostgreSQL initialized (if empty)..."
  if [[ ! -d /var/lib/postgres/data || -z "$(ls -A /var/lib/postgres/data 2>/dev/null)" ]]; then
    sudo -u postgres initdb -D /var/lib/postgres/data
    info "PostgreSQL initialized"
  else
    info "Postgres data directory non-empty; skipping initdb"
  fi
}

# --------- main ----------
main() {
  info "Starting minimal, fast Arch+i3 setup (force-overwrite, no backups)"

  check_priv

  # quick parallelizable user-level tasks that do not need 'go' or pacman packages:
  setup_st & st_pid=$!
  setup_lazyvim & lazy_pid=$!
  setup_node_tools & node_pid=$!

  # system-level prep (must run before pacman install)
  setup_mirrors
  setup_mirrorlist_service  # Add this line
  setup_chaotic

  # install system + AUR packages (blocking)
  install_packages

  # now Go is available; install go tools in background
  setup_go_tools & go_pid=$!

  # write/overwrite user configs (fast)
  write_i3
  write_redshift
  write_gemini
  write_tmux
  write_xinit_bash

  # docker group (only if docker installed)
  if command -v docker &>/dev/null; then
    if ! id -nG "$USER" | grep -qw docker; then
      sudo usermod -aG docker "$USER"
      info "Added $USER to docker group"
    else
      info "$USER already in docker group"
    fi
  else
    warn "docker not found - skipping group change"
  fi

  # postgres, alsa, autologin
  ensure_postgres
  if systemctl list-unit-files | grep -q '^alsa-state'; then
    sudo systemctl enable --now alsa-state || warn "Failed enabling alsa-state"
  fi
  setup_autologin

  # wait for background tasks (some PIDs may be empty if tasks finished quickly)
  wait || true

  sudo systemctl daemon-reload || true

  info "Done. Reboot to activate autologin, docker group membership and some services."
}

main "$@"
