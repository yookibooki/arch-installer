#!/usr/bin/env bash
set -euo pipefail
info()  { echo -e "\033[32m[INFO]\033[0m $1"; }
warn()  { echo -e "\033[33m[WARN]\033[0m $1"; }
error() { echo -e "\033[31m[ERROR]\033[0m $1" >&2; }
step()  { echo -e "\033[34m[STEP]\033[0m $1"; }
trap 'error "Script failed at line $LINENO"; exit 1' ERR

# WARNING about piping remote scripts
warn "You are running a remotely-hosted script. Make sure you trust the source (https://arch.yooki.workers.dev)."

# ---- helpers ----
timestamp() { date +%Y%m%d%H%M%S; }

# Backup a file or directory. Uses sudo when necessary.
backup_path() {
  local path=$1
  if [[ ! -e $path ]]; then
    return 0
  fi
  local now
  now=$(timestamp)
  local dest="${path}.bak.${now}"
  if [[ -w $path || -w $(dirname "$path") ]]; then
    mv -f "$path" "${dest}"
    info "Moved $path -> ${dest}"
  else
    # fallback to sudo copy-and-remove for root-owned paths
    sudo cp -a "$path" "${dest}"
    sudo rm -rf "$path"
    info "Copied (sudo) $path -> ${dest} and removed original"
  fi
}

# Backup a system file with sudo-friendly copying if needed
backup_file() {
  local f=$1
  if [[ ! -e $f ]]; then
    return 0
  fi
  local now
  now=$(timestamp)
  local dest="${f}.bak.${now}"
  if [[ -w $f || -w $(dirname "$f") ]]; then
    cp -a "$f" "${dest}"
    info "Backed up $f -> ${dest}"
  else
    sudo cp -a "$f" "${dest}"
    info "Backed up (sudo) $f -> ${dest}"
  fi
}

# ensure yay (AUR helper) installed
ensure_yay() {
  if ! command -v yay &>/dev/null; then
    step "Installing yay (AUR helper)..."
    sudo pacman -S --noconfirm --needed git base-devel || true
    tmpdir=$(mktemp -d)
    git clone --depth 1 https://aur.archlinux.org/yay.git "$tmpdir/yay"
    (cd "$tmpdir/yay" && makepkg -si --noconfirm)
    rm -rf "$tmpdir"
    if ! command -v yay &>/dev/null; then
      error "Failed to install yay. Please install it manually and re-run."
      exit 1
    fi
  else
    info "yay already installed."
  fi
}

# ---- privilege check ----
check_privileges() {
  [[ $EUID -eq 0 ]] && {
    error "Don't run as root. Use a regular user with sudo."
    exit 1
  }
  if ! sudo -v; then
    error "Sudo access required."
    exit 1
  fi
}

# ---- mirror setup (idempotent) ----
setup_mirrors() {
  step "Configuring pacman mirrors..."
  local mirrorlist="/etc/pacman.d/mirrorlist"
  sudo curl -fsSo "$mirrorlist" \
    "https://archlinux.org/mirrorlist/?country=all&protocol=https&ip_version=4&use_mirror_status=on"
  sudo sed -i 's/^#Server/Server/' "$mirrorlist"

  if ! sudo grep -q 'mirror.dc.uz' "$mirrorlist"; then
    sudo sed -i '1iServer = http://mirror.dc.uz/arch/$repo/os/$arch' "$mirrorlist"
    info "Added mirror.dc.uz to mirrorlist"
  else
    info "mirror.dc.uz already present"
  fi

  # remove duplicate lines
  sudo awk '!seen[$0]++' "$mirrorlist" | sudo tee "$mirrorlist" >/dev/null
}

# ---- chaotic aur (idempotent) ----
setup_chaotic_aur() {
  step "Setting up Chaotic AUR..."
  if sudo grep -q '^\[chaotic-aur\]' /etc/pacman.conf 2>/dev/null; then
    warn "Chaotic AUR already configured, skipping."
    return
  fi

  if ! sudo pacman-key --list-keys | grep -q 3056513887B78AEB; then
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com || true
    sudo pacman-key --lsign-key 3056513887B78AEB || true
  else
    info "Chaotic key present"
  fi

  sudo pacman -Sy --noconfirm --needed curl ca-certificates || true

  if ! pacman -Qi chaotic-keyring &>/dev/null; then
    sudo pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' || warn "Could not install chaotic-keyring"
  fi
  if ! pacman -Qi chaotic-mirrorlist &>/dev/null; then
    sudo pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' || warn "Could not install chaotic-mirrorlist"
  fi

  if ! sudo grep -q '^Include = /etc/pacman.d/chaotic-mirrorlist' /etc/pacman.conf; then
    {
      echo ""
      echo "[chaotic-aur]"
      echo "Include = /etc/pacman.d/chaotic-mirrorlist"
    } | sudo tee -a /etc/pacman.conf >/dev/null
    info "Added chaotic-aur to /etc/pacman.conf"
  fi

  sudo sed -i "/\[multilib\]/,/Include/ s/^#//" /etc/pacman.conf || true
}

# ---- packages (idempotent) ----
install_packages_and_update_system() {
  step "Updating system and installing packages..."
  ensure_yay

  local pacman_pkgs=( base-devel go alsa-utils arch-wiki-lite btop dmenu docker docker-compose git i3-wm intel-ucode iwd linux-firmware neovim noto-fonts-emoji openssh postgresql redshift tmux ttf-firacode-nerd unzip uv xclip xorg-server xorg-xinit xorg-xrandr anydesk-bin brave-bin visual-studio-code-bin )
  local aur_pkgs=( koreader-bin windsurf )

  sudo pacman -Syy --noconfirm
  sudo pacman -S --noconfirm --needed "${pacman_pkgs[@]}"

  yay -S --noconfirm --nodiffmenu --needed "${aur_pkgs[@]}"
}

# ---- go tools (idempotent-ish) ----
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
  export PATH="$HOME/go/bin:$PATH"
  for p in "${go_pkgs[@]}"; do
    go install "$p" || warn "go install failed for $p"
  done
  info "Go tools installation complete."
}

# ---- st (force-replace with backup) ----
setup_st() {
  step "Setting up st (will overwrite /opt/st after backup)..."
  if [[ -d /opt/st ]]; then
    backup_path /opt/st
  fi
  sudo mkdir -p /opt/st
  curl -fsL https://dl.suckless.org/st/st-0.9.3.tar.gz | sudo tar -xz --strip-components=1 -C /opt/st
  sudo chown -R "$USER:$USER" /opt/st
  info "st installed to /opt/st (previous /opt/st moved to .bak.* if it existed)"
}

# ---- node & gemini (idempotent) ----
setup_node_tools() {
  step "Installing Node.js and Gemini CLI..."
  (
    if ! command -v fnm &>/dev/null; then
      curl -fsSL https://fnm.vercel.app/install | bash
    fi
    export PATH="$HOME/.fnm:$PATH"
    eval "$(fnm env)" 2>/dev/null || true

    fnm install 24 || true

    if ! npm list -g @google/gemini-cli >/dev/null 2>&1; then
      npm install -g @google/gemini-cli || warn "Failed to npm install @google/gemini-cli"
    else
      info "gemini-cli already installed."
    fi
  )
  info "Node.js and Gemini CLI installation complete."
}

# ---- lazyvim (idempotent) ----
setup_lazyvim() {
  step "Installing LazyVim (will overwrite .config/nvim after backup if present)..."
  if [[ -d "${HOME}/.config/nvim" ]]; then
    backup_path "${HOME}/.config/nvim"
  fi
  git clone --depth 1 https://github.com/LazyVim/starter "${HOME}/.config/nvim"
  rm -rf "${HOME}/.config/nvim/.git" || true
  info "LazyVim installed (previous .config/nvim moved to .bak.* if it existed)"
}

# ---- i3 config (force overwrite with backup) ----
setup_i3() {
  step "Installing i3 config (will overwrite user i3 config after backup)..."
  mkdir -p "${HOME}/.config/i3"
  local i3conf="${HOME}/.config/i3/config"
  if [[ -f $i3conf ]]; then
    backup_file "$i3conf"
  fi
  cat >"$i3conf" <<'EOF'
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
  info "i3 config written to $i3conf (previous was backed up if present)"
}

# ---- create configs (force overwrite with backups) ----
create_configs() {
  step "Creating configuration files (will overwrite with backups)..."
  mkdir -p "${HOME}/.config" "${HOME}/.gemini" "${HOME}/.config/tmux"

  # redshift (force)
  local rconf="${HOME}/.config/redshift.conf"
  if [[ -f $rconf ]]; then
    backup_file "$rconf"
  fi
  cat >"$rconf" <<'EOF'
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
  info "Wrote $rconf (backed up previous if existed)"

  # gemini settings (force)
  local gconf="${HOME}/.gemini/settings.json"
  if [[ -f $gconf ]]; then
    backup_file "$gconf"
  fi
  cat >"$gconf" <<'EOF'
{
  "selectedAuthType": "oauth-personal",
  "mcpServers": {
    "context7": {
      "httpUrl": "https://mcp.context7.com/mcp"
    }
  }
}
EOF
  info "Wrote $gconf (backed up previous if existed)"

  # tmux (force)
  local tconf="${HOME}/.config/tmux/tmux.conf"
  if [[ -f $tconf ]]; then
    backup_file "$tconf"
  fi
  cat >"$tconf" <<'EOF'
set -g mouse on
set -g status off
bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "xclip -sel clip -i"
set -g base-index 1
setw -g pane-base-index 1
unbind C-b
set -g prefix C-a
bind C-a send-prefix
EOF
  info "Wrote $tconf (backed up previous if existed)"

  # .xinitrc (force)
  local xinit="${HOME}/.xinitrc"
  if [[ -f $xinit ]]; then
    backup_file "$xinit"
  fi
  cat >"$xinit" <<'EOF'
xrandr --output HDMI-1 --auto --output eDP-1 --off
redshift &
exec i3
EOF
  chmod +x "$xinit"
  info "Wrote $xinit (backed up previous if existed)"

  # .bash_profile (force)
  local bprofile="${HOME}/.bash_profile"
  if [[ -f $bprofile ]]; then
    backup_file "$bprofile"
  fi
  cat >"$bprofile" <<'EOF'
[[ -f ~/.bashrc ]] && . ~/.bashrc
if [ -z "$DISPLAY" ] && [ "${XDG_VTNR:-1}" = 1 ]; then
    exec startx
fi
EOF
  info "Wrote $bprofile (backed up previous if existed)"

  # .bashrc: remove previous block between markers if present, then write new block
  local bashrc="${HOME}/.bashrc"
  local marker_start="# >>> setup-script additions >>>"
  local marker_end="# <<< setup-script additions <<<"
  if [[ -f $bashrc ]]; then
    # backup original
    backup_file "$bashrc"
    # remove old block if exists
    if grep -qF "$marker_start" "$bashrc"; then
      awk -v s="$marker_start" -v e="$marker_end" '{
        if ($0 ~ s) {skip=1}
        if (!skip) print $0
        if ($0 ~ e) {skip=0; next}
      }' "$bashrc" > "${bashrc}.tmp" || true
      mv -f "${bashrc}.tmp" "$bashrc"
    fi
  else
    : >"$bashrc"
  fi

  # append new block
  cat >>"$bashrc" <<EOF

${marker_start}
# Local additions by setup script
alias xc='xclip -selection clipboard'
export EDITOR=nvim
export TERMINAL=st
export PATH="\$HOME/.local/bin:\$HOME/go/bin:/usr/local/go/bin:\$HOME/.fnm:\$PATH"
${marker_end}
EOF
  info "Rewrote $bashrc (previous backed up)"
}

# ---- autologin (idempotent write) ----
setup_autologin() {
  step "Setting up autologin..."
  local vt=${XDG_VTNR:-1}
  local dir="/etc/systemd/system/getty@tty${vt}.service.d"
  local conf="${dir}/override.conf"
  sudo mkdir -p "$dir"
  local body
  read -r -d '' body <<'EOF' || true
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${USER} --noclear %I \$TERM
EOF
  # backup conf if exists
  if sudo test -f "$conf"; then
    backup_file "$conf"
  fi
  sudo tee "$conf" >/dev/null <<EOF
${body}
EOF
  info "Autologin configured for user: ${USER} on tty${vt} (previous conf backed up if existed)"
}

# ---- main ----
main() {
  info "Starting idempotent-with-backups Arch/i3 setup (force-overwrite mode)..."
  check_privileges

  setup_mirrors
  setup_chaotic_aur
  install_packages_and_update_system

  sudo journalctl --vacuum-size=50M || true
  sudo journalctl --vacuum-time=3d || true

  info "Starting parallel setup..."
  setup_go_tools &
  go_pid=$!

  setup_st &
  st_pid=$!

  setup_node_tools &
  node_pid=$!

  setup_lazyvim &
  lazyvim_pid=$!

  info "Applying local configurations (force-overwrite with backups)..."
  setup_i3
  create_configs

  step "Setting up Docker group..."
  if command -v docker &>/dev/null; then
    if ! id -nG "$USER" | grep -qw docker; then
      sudo usermod -aG docker "$USER"
      info "Added $USER to docker group"
    else
      info "$USER already in docker group"
    fi
  else
    warn "docker not installed or not in PATH; skipping docker group change"
  fi

  step "Setting up PostgreSQL (initdb if needed)..."
  if [[ ! -d /var/lib/postgres/data || -z "$(ls -A /var/lib/postgres/data 2>/dev/null)" ]]; then
    sudo -u postgres initdb -D /var/lib/postgres/data
    info "PostgreSQL initialized"
  else
    warn "PostgreSQL data directory already initialized; skipping initdb"
  fi

  step "Enabling alsa-state service..."
  if systemctl list-unit-files | grep -q '^alsa-state'; then
    sudo systemctl enable --now alsa-state || warn "Failed enabling alsa-state"
  else
    warn "alsa-state unit not found; skipping"
  fi

  setup_autologin

  step "Waiting for background installations to complete..."
  wait "${go_pid}" "${st_pid}" "${node_pid}" "${lazyvim_pid}" || true

  step "Reloading systemd daemon..."
  sudo systemctl daemon-reload || true

  info "COMPLETED! All overwritten files were backed up with .bak.<timestamp> suffixes."
  warn "Reboot for autologin, startx, and docker group changes to take effect."
}

main "$@"
