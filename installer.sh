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
    sudo curl -so /etc/pacman.d/mirrorlist \
        "https://archlinux.org/mirrorlist/?country=all&protocol=http&ip_version=4&use_mirror_status=on"
    sudo sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist
    
    # Prioritize local mirror
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
        kitty openssh wget ttf-firacode-nerd brave-bin git base-devel redshift yay neovim
        visual-studio-code-bin xclip nodejs npm go uv
    )
    sudo pacman -S --noconfirm --needed "${packages[@]}"
}

# Setup i3 configuration
setup_i3() {
    step "Setting up i3 configuration..."
    mkdir -p ~/.config/i3
    cat > ~/.config/i3/config << 'EOF'
set $mod Mod4
font pango:FiraCode Nerd Font Mono 14

# Window appearance
default_border pixel 2
default_floating_border pixel 2
hide_edge_borders smart

# Auto-start applications
exec --no-startup-id redshift

# Application assignments
assign [class="Brave-browser"] 1
assign [class="kitty"] 2
assign [class="Code"] 3

# Key bindings
bindsym $mod+d exec --no-startup-id dmenu_run
bindsym $mod+b exec brave; workspace number 1
bindsym $mod+Return exec kitty; workspace number 2
bindsym $mod+c exec code; workspace number 3
bindsym $mod+Shift+q kill

# Display mode
set $mode_display Display: (l)aptop, (e)xternal
mode "$mode_display" {
    bindsym l exec xrandr --output eDP-1 --auto --output HDMI-1 --off; mode "default"
    bindsym e exec xrandr --output HDMI-1 --auto --output eDP-1 --off; mode "default"
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+x mode "$mode_display"

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

# i3 controls
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

export EDITOR=nvim
export TERMINAL=kitty
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
