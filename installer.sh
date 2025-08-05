#!/bin/bash

# Arch Linux i3 Setup Installer
# This script installs and configures i3 window manager with various applications

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
    exit 1
fi

print_status "Starting Arch Linux i3 Setup..."

# Update system
print_step "Updating system packages..."
sudo pacman -Syu --noconfirm

# Install pacman packages
print_step "Installing packages from pacman..."
PACMAN_PACKAGES=(
    "i3-wm"
    "dmenu"
    "xorg-xinit"
    "redshift"
    "neovim"
    "git"
    "base-devel"
    "ttf-nerd-fonts-symbols"
    "otf-font-awesome"
    "xterm"
    "xorg-xrandr"
    "xorg-xset"
)

sudo pacman -S --noconfirm "${PACMAN_PACKAGES[@]}"

# Install AUR helper (yay) if not present
print_step "Checking for AUR helper..."
if ! command -v yay &> /dev/null; then
    print_status "Installing yay AUR helper..."
    cd /tmp
    git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    makepkg -si --noconfirm
    cd ~
else
    print_status "yay is already installed"
fi

# Install AUR packages
print_step "Installing packages from AUR..."
AUR_PACKAGES=(
    "brave-bin"
    "visual-studio-code-insiders-bin"
)

yay -S --noconfirm "${AUR_PACKAGES[@]}"

# Create necessary directories
print_step "Creating configuration directories..."
mkdir -p ~/.config/i3
mkdir -p ~/.config
mkdir -p /tmp/systemd-override
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d

# Create i3 configuration
print_step "Creating i3 configuration..."
cat > ~/.config/i3/config << 'EOF'
set $mod Mod4

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
bindsym $mod+c exec code-insiders; workspace number 3

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

# Create redshift configuration
print_step "Creating redshift configuration..."
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

# Create Xresources configuration
print_step "Creating Xresources configuration..."
cat > ~/.Xresources << 'EOF'
! - Copy/Paste
XTerm.vt100.translations: #override \
    Shift Ctrl<Key>V: insert-selection(CLIPBOARD)\n\
    Shift Ctrl<Key>C: copy-selection(CLIPBOARD)

! — GENERAL
! XTerm*faceName:             Something Nerd Font Mono
XTerm*faceSize:             16
XTerm*allowBold:            true
! XTerm*boldFont:             xft:Something Nerd Font Mono:bold:size=16

! disable blinking and audible bell
XTerm*blinkMode:            disabled
XTerm*bellIsUrgent:         false
XTerm*visualBell:           true

! scrollbar on the right, 10px wide
XTerm*scrollBar:            true
XTerm*rightScrollBar:       true
XTerm*scrollBarThumb:       grey60
XTerm*scrollBarWidth:       10

! — COLORS (warm, low-contrast palette)
! background and foreground
XTerm*background:           #2e2626    ! very dark, warm gray
XTerm*foreground:           #f0e0c0    ! soft off-white

! ANSI colors (0-7)
XTerm*color0:               #2e2626    ! black
XTerm*color1:               #cc6666    ! red
XTerm*color2:               #b5bd68    ! green
XTerm*color3:               #f0c674    ! yellow
XTerm*color4:               #81a2be    ! blue
XTerm*color5:               #b294bb    ! magenta
XTerm*color6:               #8abeb7    ! cyan
XTerm*color7:               #deebff    ! white

! Bright ANSI (8-15)
XTerm*color8:               #555249
XTerm*color9:               #ff3334
XTerm*color10:              #b5bd68
XTerm*color11:              #ffd24a
XTerm*color12:              #81a2be
XTerm*color13:              #cc7acc
XTerm*color14:              #8abeb7
XTerm*color15:              #ffffff

! — CURSOR
XTerm*cursorBlink:          false
XTerm*cursorColor:          #f0e0c0
XTerm*pointerColor:         #f0e0c0

! — MISC
XTerm*saveLines:            10000      ! scrollback
XTerm*utf8:                 2          ! enable UTF-8
XTerm*translations:         #override \n\
    Shift <Key>Page_Up: scroll-back(1,page)\n\
    Shift <Key>Page_Down: scroll-forw(1,page)
EOF

# Create xinitrc
print_step "Creating xinitrc configuration..."
cat > ~/.xinitrc << 'EOF'
xset led 2
exec i3
EOF

# Create bash_profile
print_step "Creating bash_profile configuration..."
cat > ~/.bash_profile << 'EOF'
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
  exec startx
fi
EOF

# Create systemd override for autologin
print_step "Creating systemd autologin configuration..."
cat > /tmp/systemd-override/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin x --noclear %I $TERM
EOF

sudo cp /tmp/systemd-override/override.conf /etc/systemd/system/getty@tty1.service.d/override.conf

# Update bashrc with environment variables
print_step "Updating bashrc with environment variables..."
if ! grep -q "export EDITOR=nvim" ~/.bashrc; then
    echo "export EDITOR=nvim" >> ~/.bashrc
fi

if ! grep -q "export TERMINAL=xterm" ~/.bashrc; then
    echo "export TERMINAL=xterm" >> ~/.bashrc
fi

# Make xinitrc executable
chmod +x ~/.xinitrc

# Reload systemd daemon
print_step "Reloading systemd daemon..."
sudo systemctl daemon-reload

# Merge Xresources
print_step "Merging Xresources..."
if command -v xrdb &> /dev/null; then
    xrdb -merge ~/.Xresources 2>/dev/null || print_warning "Could not merge Xresources (X server not running)"
else
    print_warning "xrdb not available, Xresources will be loaded on next X session"
fi

print_status "Installation completed successfully!"
print_status "Configuration summary:"
echo "  - i3 window manager installed and configured"
echo "  - Applications: Brave browser, VS Code Insiders, Neovim"
echo "  - Auto-login configured for user 'x'"
echo "  - Redshift configured for Tashkent location"
echo "  - XTerm configured with custom colors and fonts"
echo ""
print_status "Key bindings:"
echo "  - Mod+d: Application launcher (dmenu)"
echo "  - Mod+Return: Terminal"
echo "  - Mod+b: Brave browser"
echo "  - Mod+c: VS Code Insiders"
echo "  - Mod+x: Display switching mode"
echo "  - Mod+1-10: Switch workspaces"
echo "  - Mod+Shift+q: Close window"
echo "  - Mod+Shift+r: Restart i3"
echo ""
print_warning "Please reboot your system to activate autologin and start the graphical session."

# Clean up
rm -rf /tmp/systemd-override

print_status "Script execution completed!"