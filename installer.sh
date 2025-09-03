#!/bin/bash
set -euo pipefail
info() { echo -e "\033[32m[INFO]\033[0m $1"; }
warn() { echo -e "\033[33m[WARN]\033[0m $1"; }
error() { echo -e "\033[31m[ERROR]\033[0m $1" >&2; }
step() { echo -e "\033[34m[STEP]\033[0m $1"; }
trap 'error "Script failed at line $LINENO"' ERR
check_privileges() {
  [[ $EUID -eq 0 ]] && {
    error "Don't run as root. Use regular user with sudo."
    exit 1
  }
  sudo -v || {
    error "Sudo access required."
    exit 1
  }
}

# Configure mirrors
setup_mirrors() {
  step "Configuring pacman mirrors..."
  sudo curl -so /etc/pacman.d/mirrorlist "https://archlinux.org/mirrorlist/?country=all&protocol=https&ip_version=4&use_mirror_status=on"
  sudo sed -i \
    -e 's/^#Server/Server/' \
    -e '/mirror\.dc\.uz/d' \
    -e '1iServer = http://mirror.dc.uz/arch/$repo/os/$arch' \
    /etc/pacman.d/mirrorlist
}

# Setup Chaotic AUR
setup_chaotic_aur() {
  step "Setting up Chaotic AUR..."
  if grep -q "\[chaotic-aur\]" /etc/pacman.conf; then
    warn "Chaotic AUR already configured, skipping."
    return
  fi

  sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
  sudo pacman-key --lsign-key 3056513887B78AEB
  sudo pacman --noconfirm -U \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

  {
    echo ""
    echo "[chaotic-aur]"
    echo "Include = /etc/pacman.d/chaotic-mirrorlist"
  } | sudo tee -a /etc/pacman.conf >/dev/null

  sudo sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
}

# Update system and install all packages in one go
install_packages_and_update_system() {
  step "Updating system and installing packages..."
  local pacman_pkgs=(
    base-devel go alsa-utils arch-wiki-lite btop dmenu docker docker-compose git i3-wm intel-ucode iwd linux-firmware neovim noto-fonts-emoji openssh postgresql redshift tmux ttf-firacode-nerd unzip uv xclip xorg-server xorg-xinit xorg-xrandr anydesk-bin brave-bin visual-studio-code-bin yay
  )
  local aur_pkgs=(
    koreader-bin windsurf
  )

  sudo pacman -Syyu --noconfirm --needed "${pacman_pkgs[@]}"

  yay -S --noconfirm --nodiffmenu --needed "${aur_pkgs[@]}"
}


setup_go_tools() {
  step "Installing Go tools..."
  local go_pkgs=(
    github.com/cosmtrek/air@latest
    github.com/golangci/golangci-lint/cmd/golangci-lint@latest
    golang.org/x/tour@latest
    golang.org/x/tools/cmd/goimports@latest
    golang.org/x/tools/gopls@latest
    honnef.co/go/tools/cmd/staticcheck@latest
    golang.org/x/tools/cmd/godoc@latest
  )
  go install "${go_pkgs[@]}"
  info "Go tools installation complete."
}

setup_st() {
  step "Setting up st..."
  sudo mkdir -p /opt/st
  curl -L https://dl.suckless.org/st/st-0.9.3.tar.gz | sudo tar -xz --strip-components=1 -C /opt/st
  sudo chown -R "$USER:$USER" /opt/st
  info "st setup complete."
}

setup_node_tools() {
  step "Installing Node.js and Gemini CLI..."
  (
    if ! command -v fnm &>/dev/null; then
      curl -fsSL https://fnm.vercel.app/install | bash
    fi
    export PATH="$HOME/.fnm:$PATH"
    eval "$(fnm env)"

    fnm install 24
    npm install -g @google/gemini-cli
  )
  info "Node.js and Gemini CLI installation complete."
}

setup_lazyvim() {
  step "Installing LazyVim..."
  if [[ -d ~/.config/nvim ]]; then
    warn "LazyVim config already exists, skipping."
    return
  fi
  git clone --depth 1 https://github.com/LazyVim/starter ~/.config/nvim
  rm -rf ~/.config/nvim/.git
  info "LazyVim installation complete."
}


setup_i3() {
  step "Setting up i3 configuration..."
  mkdir -p ~/.config/i3
  cat >~/.config/i3/config <<'EOF'
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
}

create_configs() {
  step "Creating configuration files..."
  mkdir -p ~/.config ~/.gemini ~/.config/tmux
  cat >~/.config/redshift.conf <<'EOF'
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
  cat >~/.gemini/settings.json <<'EOF'
{
  "selectedAuthType": "oauth-personal",
  "mcpServers": {
    "context7": {
      "httpUrl": "https://mcp.context7.com/mcp"
    }
  }
}
EOF
  cat >~/.config/tmux/tmux.conf <<'EOF'
set -g mouse on
set -g status off
bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "xclip -sel clip -i"
set -g base-index 1
setw -g pane-base-index 1
unbind C-b
set -g prefix C-a
bind C-a send-prefix
EOF
  cat >~/.xinitrc <<'EOF'
xrandr --output HDMI-1 --auto --output eDP-1 --off
redshift &
exec i3
EOF
  chmod +x ~/.xinitrc
  cat >~/.bash_profile <<'EOF'
[[ -f ~/.bashrc ]] && . ~/.bashrc
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
    exec startx
fi
EOF
  cat >>~/.bashrc <<'EOF'
alias xc='xclip -selection clipboard'
export EDITOR=nvim
export TERMINAL=st
export PATH="$HOME/.local/bin:$HOME/go/bin:/usr/local/go/bin:$HOME/.fnm:$PATH"
EOF
}

setup_autologin() {
  step "Setting up autologin..."
  local vt=${XDG_VTNR:-1}
  sudo mkdir -p "/etc/systemd/system/getty@tty$vt.service.d"
  sudo tee "/etc/systemd/system/getty@tty$vt.service.d/override.conf" >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF
  info "Autologin configured for user: $USER on tty$vt"
}

# Main execution
main() {
  info "Starting optimized Arch Linux i3 setup..."

  check_privileges
  setup_mirrors
  setup_chaotic_aur
  install_packages_and_update_system

  info "Starting parallel setup of development tools..."
  setup_go_tools &
  local go_pid=$!

  setup_st &
  local st_pid=$!

  setup_node_tools &
  local node_pid=$!

  setup_lazyvim &
  local lazyvim_pid=$!

  info "Applying local configurations..."
  setup_i3
  create_configs

  step "Setting up Docker..."
  sudo usermod -aG docker $USER

  step "Setting up PostgreSQL..."
  sudo -u postgres initdb -D /var/lib/postgres/data

  step "Enabling alsa-state service..."
  sudo systemctl enable alsa-state

  setup_autologin

  step "Waiting for background installations to complete..."
  wait $go_pid $st_pid $node_pid $lazyvim_pid

  step "Reloading systemd daemon..."
  sudo systemctl daemon-reload

  info "COMPLETED!"
  warn "Reboot for autologin, startx, and docker group changes to take effect."
}

main "$@"
