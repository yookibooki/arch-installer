#!/bin/bash
set -euo pipefail

# Logging functions
info() { echo -e "\033[32m[INFO]\033[0m $1"; }
warn() { echo -e "\033[33m[WARN]\033[0m $1"; }
error() { echo -e "\033[31m[ERROR]\033[0m $1" >&2; }
step() { echo -e "\033[34m[STEP]\033[0m $1"; }

# Error handling
trap 'error "Script failed at line $LINENO"' ERR

# Privilege checks
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
  sudo sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist
  sudo sed -i '/mirror\.dc\.uz/d' /etc/pacman.d/mirrorlist
  sudo sed -i '1iServer = http://mirror.dc.uz/arch/$repo/os/$arch' /etc/pacman.d/mirrorlist
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

# Install packages
install_packages() {
  step "Installing packages..."
  local pacman_pkgs=(
    alsa-utils arch-wiki-lite btop dmenu docker docker-compose git i3-wm intel-ucode iwd linux-firmware neovim noto-fonts-emoji openssh postgresql redshift tmux ttf-firacode-nerd unzip uv xclip xorg-server xorg-xinit xorg-xrandr anydesk-bin brave-bin visual-studio-code-bin yay
  )
  local aur_pkgs=(
    koreader-bin windsurf
  )
  sudo pacman -S --noconfirm --needed "${pacman_pkgs[@]}"
  yay -S --noconfirm --nodiffmenu --needed "${aur_pkgs[@]}"
}

# Setup i3 configuration
setup_i3() {
  step "Setting up i3 configuration..."
  mkdir -p ~/.config/i3
  cat >~/.config/i3/config <<'EOF'
set $mod Mod4

# Menu for Displays & Power
mode "x"{
    bindsym l exec xrandr --output eDP-1 --auto --output HDMI-1 --off; mode "default"
    bindsym e exec xrandr --output HDMI-1 --auto --output eDP-1 --off; mode "default"
    bindsym p exec sudo systemctl poweroff; mode "default"
    bindsym r exec sudo systemctl reboot; mode "default"
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+x mode "x"

# Appearance
focus_follows_mouse no
default_border none 
hide_edge_borders smart
focus_on_window_activation smart

# Workspace assignments
assign [class="^Brave-browser$"] 1
assign [class="^st$"] 2
assign [class="^Windsurf$"] 3
assign [class="^code$"] 3

# Apps
bindsym $mod+b workspace number 1; exec brave
bindsym $mod+Return workspace number 2; exec st -e tmux new -A -s main
bindsym $mod+w workspace number 3; exec windsurf
bindsym $mod+c workspace number 3; exec code
bindsym $mod+d exec --no-startup-id dmenu_run
bindsym $mod+q kill

# Quake-style scratchpad
for_window [title="^Scratchpad$"] move to scratchpad
bindsym $mod+Shift+Return exec st -t Scratchpad -e tmux new -A -s main
bindsym $mod+minus scratchpad show

# Splits
bindsym $mod+Shift+v split v
bindsym $mod+Shift+h split h

# Focus (Vim-style)
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right

# Workspaces
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

# Move Workspaces
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

# Reload/Restart i3
bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart
EOF
}

# Create configuration files
create_configs() {
  step "Creating configuration files..."

  # Redshift config
  mkdir -p ~/.config
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

  # Gemini CLI config
  mkdir -p ~/.gemini
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

  # Tmux config
  mkdir -p ~/.config/tmux
  cat >~/.config/tmux/tmux.conf <<'EOF'
# Enable Mouse
set -g mouse on

# Disable Status Bar
set -g status off

# Copy to System Clipboard with y
bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "xclip -sel clip -i"

# Start Window/Pane Numbering at 1
set -g base-index 1
setw -g pane-base-index 1

# Change Prefix to Ctrl-a
unbind C-b
set -g prefix C-a
bind C-a send-prefix
EOF

  # .xinitrc
  cat >~/.xinitrc <<'EOF'
xrandr --output HDMI-1 --auto --output eDP-1 --off
redshift &
exec i3
EOF
  chmod +x ~/.xinitrc

  # .bash_profile
  cat >~/.bash_profile <<'EOF'
[[ -f ~/.bashrc ]] && . ~/.bashrc

if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
    exec startx
fi
EOF

  # Append to .bashrc
  cat >>~/.bashrc <<'EOF'
alias xc='xclip -selection clipboard'
export EDITOR=nvim
export TERMINAL=st
export PATH="$HOME/.local/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"
EOF
}

# Setup autologin
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
  info "Starting Arch Linux i3 setup..."

  check_privileges
  setup_mirrors

  step "Updating system packages..."
  sudo pacman -Syu --noconfirm

  setup_chaotic_aur
  sudo pacman -Syu --noconfirm

  install_packages
  setup_i3

  step "Setting up st..."
  curl -L https://dl.suckless.org/st/st-0.9.3.tar.gz | sudo tar -xz --strip-components=1 -C /opt/st
  sudo chown -R $USER /opt/st

  step "go install things..."
  go install github.com/cosmtrek/air@latest
  go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
  go install golang.org/x/tour@latest
  go install golang.org/x/tools/cmd/goimports@latest
  go install golang.org/x/tools/gopls@latest
  go install honnef.co/go/tools/cmd/staticcheck@latest

  step "Setting up Docker..."
  sudo usermod -aG docker $USER

  step "Installing Node.js..."
  curl -o- https://fnm.vercel.app/install | bash
  export PATH="$HOME/.fnm:$PATH"
  eval "$(fnm env --shell bash)"
  fnm install 24

  step "Installing Gemini CLI..."
  npm install -g @google/gemini-cli

  step "Installing LazyVim..."
  git clone --depth 1 https://github.com/LazyVim/starter ~/.config/nvim
  rm -rf ~/.config/nvim/.git

  step "Setting up PostgreSQL..."
  sudo -u postgres initdb -D /var/lib/postgres/data

  step "Enabling alsa-state service..."
  sudo systemctl enable alsa-state

  create_configs
  setup_autologin

  step "Reloading systemd daemon..."
  sudo systemctl daemon-reload

  info "COMPLETED!"
  warn "Reboot for autologin and startx to take effect."
}

main "$@"
