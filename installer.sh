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
    [[ $EUID -eq 0 ]] && { error "Don't run as root. Use regular user with sudo."; exit 1; }
    sudo -v || { error "Sudo access required."; exit 1; }
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
    } | sudo tee -a /etc/pacman.conf > /dev/null
    
    sudo sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
}

# Install packages
install_packages() {
    step "Installing packages..."
    local packages=(
        i3-wm dmenu xorg-server xorg-xinit xorg-xrandr alsa-utils
        xterm openssh wget ttf-firacode-nerd brave-bin git base-devel redshift yay neovim
        visual-studio-code-bin xclip go uv anydesk-bin
    )
    sudo pacman -S --noconfirm --needed "${packages[@]}"
}

# Setup i3 configuration
setup_i3() {
    step "Setting up i3 configuration..."
    mkdir -p ~/.config/i3
    cat > ~/.config/i3/config << 'EOF'
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
    cat > ~/.config/redshift.conf << 'EOF'
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

    # .xinitrc
    cat > ~/.xinitrc << 'EOF'
xrandr --output HDMI-1 --auto --output eDP-1 --off
redshift &
exec i3
EOF
    chmod +x ~/.xinitrc

    # .bash_profile
    cat > ~/.bash_profile << 'EOF'
[[ -f ~/.bashrc ]] && . ~/.bashrc

if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
    exec startx
fi
EOF

    # Append to .bashrc
    cat >> ~/.bashrc << 'EOF'
alias xc='xclip -selection clipboard'
export EDITOR=nvim
export TERMINAL=st
# Keep $HOME/.local/bin at first line for anydesk to work correctly
export PATH="$HOME/.local/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                   # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion
EOF
}

# Setup autologin
setup_autologin() {
    step "Setting up autologin..."
    local vt=${XDG_VTNR:-1}
    sudo mkdir -p "/etc/systemd/system/getty@tty$vt.service.d"
    sudo tee "/etc/systemd/system/getty@tty$vt.service.d/override.conf" > /dev/null << EOF
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
