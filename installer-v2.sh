#!/bin/bash
set -e 

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "Don't run as root. Use a regular user with sudo privileges."
    exit 1
fi

# Check for sudo privileges
if ! sudo -v; then
    print_error "Sudo access required. Run as user with sudo privileges."
    exit 1
fi

print_status "Starting Arch Linux i3 setup..."

# Mirrorlist
print_step "Configuring pacman mirrors..."
sudo curl -o /etc/pacman.d/mirrorlist "https://archlinux.org/mirrorlist/?country=all&protocol=http&ip_version=4&use_mirror_status=on"
sudo sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist
print_status "Prioritizing mirror.dc.uz at top of mirrorlist..."
sudo sed -i '/mirror\.dc\.uz/d' /etc/pacman.d/mirrorlist
sudo sed -i '1iServer = http://mirror.dc.uz/arch/$repo/os/$arch' /etc/pacman.d/mirrorlist

# Update system
print_step "Updating system packages..."
sudo pacman -Syu --noconfirm

# Chaotic AUR Install
print_step "Checking for Chaotic AUR repository..."
if ! grep -q "\[chaotic-aur\]" /etc/pacman.conf; then
    print_status "Setting up Chaotic AUR..."
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
    echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf
    sudo sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
    sudo pacman --noconfirm -Syu
else
    print_warning "Chaotic AUR already configured, skipping."
fi

# Packages
print_step "Installing packages from pacman..."
PACMAN_PACKAGES=(
    "i3-wm"
    "dmenu"
    "xorg-server"
    "xorg-xinit"
    "xorg-xrandr"
    "alsa-utils"
    "kitty"
    "wget"
    "brave-bin"
    "git"
    "base-devel"
    "redshift"
    "yay"
    "neovim"
    "visual-studio-code-bin"
    "xclip"
    "nodejs"
    "npm"
    "go"
    "uv"
)
sudo pacman -S --noconfirm --needed "${PACMAN_PACKAGES[@]}"

# i3 Config
print_step "Setting up i3..."
mkdir -p ~/.config/i3
cat > ~/.config/i3/config << 'EOF'
set $mod Mod4
font pango:YourFontName 16

# Window appearance
default_border pixel 1
default_floating_border pixel 1
hide_edge_borders smart

# Auto-start applications
exec --no-startup-id redshift

# Application assignments
assign [class="Brave-browser"] 1
assign [class="UXTerm"] 2
assign [class="Code"] 3

# Application launchers
bindsym $mod+d exec --no-startup-id dmenu_run
bindsym $mod+b exec brave; workspace number 1
bindsym $mod+Return exec i3-sensible-terminal; workspace number 2
bindsym $mod+c exec code; workspace number 3

# Display switching
set $mode_display display

mode "$mode_display" {
    # Laptop-only (eDP-1), then return to default mode
    bindsym l exec --no-startup-id \
        xrandr --output eDP-1 --auto --output HDMI-1 --off; \
        mode "default"

    # External-only (HDMI-1), then return to default mode
    bindsym e exec --no-startup-id \
        xrandr --output HDMI-1 --auto --output eDP-1 --off; \
        mode "default"

    # Exit display mode
    bindsym Return mode "default"
    bindsym Escape mode "default"
}

# Bind Mod+x to enter display-switching mode
bindsym $mod+x mode "$mode_display"


# Window controls
bindsym $mod+Shift+q kill

# Workspace navigation
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

# ALSA
print_step "Enabling alsa-state..."
sudo systemctl enable alsa-state

# Redshift Config
print_step "Creating ~/.config/redshift.conf..."
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

# ~/.xinitrc Config
print_step "Creating ~/.xinitrc..."
cat > ~/.xinitrc << 'EOF'
exec i3
EOF
chmod +x ~/.xinitrc

# ~/.bash_profile Config
print_step "Creating ~/.bash_profile..."
cat > ~/.bash_profile << 'EOF'
# Source bashrc if it exists (common practice)
[[ -f ~/.bashrc ]] && . ~/.bashrc

# Auto-start X11 on tty1
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
  exec startx
fi
EOF

# TTY --autologin
echo "Setting up Auto-Login..."
VT=${XDG_VTNR:-1}
sudo mkdir -p /etc/systemd/system/getty@tty$VT.service.d
sudo tee /etc/systemd/system/getty@tty$VT.service.d/override.conf > /dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF
echo "Autologin configured for user: $USER on tty$VT"

# ~/.bashrc Config
print_step "Creating ~/.bashrc..."
cat >> ~/.bashrc << 'EOF'
export EDITOR=nvim
export TERMINAL=kitty
echo "Today is $(date '+%A, %B %d, %Y')"
uptime
EOF

# Reload daemon
print_step "Reloading systemd daemon..."
sudo systemctl daemon-reload

print_status "COMLETED!"
print_warning "Reboot for autologin and startx."