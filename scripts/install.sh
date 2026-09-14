#!/bin/bash
set -euo pipefail

# mimo-linux-port: One-click installer for Xiaomi MiMo Desktop on Linux
# Tested on Ubuntu 24.04, Debian 12+, Arch Linux, Fedora

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}     Xiaomi MiMo Desktop Linux Compatibility Port     ${NC}"
echo -e "${BLUE}======================================================${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="/opt/mimo-desktop-cn"

# Require sudo for system installation
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}[!] This installation requires root privileges.${NC}"
  SUDO="sudo"
else
  SUDO=""
fi

# Ensure critical shared libraries are present
if command -v apt-get >/dev/null 2>&1; then
  echo -e "${BLUE}[*] Checking system dependencies...${NC}"
  if ! /sbin/ldconfig -p 2>/dev/null | grep -q "libsecret-1.so.0"; then
    echo -e "${YELLOW}[!] Installing libsecret-1-0 and libxtst6...${NC}"
    $SUDO apt-get update -qq || true
    $SUDO apt-get install -y -qq libsecret-1-0 libxtst6 || true
  fi
fi

# 1. Detect source package
SOURCE_PKG=""
CANDIDATES=(
  "/home/$SUDO_USER/xiaomi-mimo-desktop-26.909.91205-linux-x64-fixed.deb"
  "$HOME/xiaomi-mimo-desktop-26.909.91205-linux-x64-fixed.deb"
  "/home/$SUDO_USER/.config/XiaomiMiMoDesktop/updates/XiaomiMiMo-26.909.91205-x64.deb"
  "$HOME/.config/XiaomiMiMoDesktop/updates/XiaomiMiMo-26.909.91205-x64.deb"
  "./XiaomiMiMo-x64.deb"
)

for cand in "${CANDIDATES[@]}"; do
  if [ -f "$cand" ]; then
    SOURCE_PKG="$cand"
    echo -e "${GREEN}[+] Found local package: $SOURCE_PKG${NC}"
    break
  fi
done

TMP_WORK=$(mktemp -d /tmp/mimo-install-XXXXXX)
trap 'rm -rf "$TMP_WORK"' EXIT

if [ -n "$SOURCE_PKG" ]; then
  echo -e "${BLUE}[*] Unpacking from $SOURCE_PKG...${NC}"
  dpkg-deb -x "$SOURCE_PKG" "$TMP_WORK"
else
  echo -e "${YELLOW}[!] No local cached package found. Please specify or download official package.${NC}"
  exit 1
fi

echo -e "${BLUE}[*] Installing application files to $INSTALL_DIR...${NC}"
$SUDO mkdir -p "$INSTALL_DIR"
if [ -d "$TMP_WORK/opt/mimo-desktop-cn" ]; then
  $SUDO cp -r "$TMP_WORK/opt/mimo-desktop-cn/"* "$INSTALL_DIR/"
else
  $SUDO cp -r "$TMP_WORK/"* "$INSTALL_DIR/"
fi

echo -e "${BLUE}[*] Applying Linux scroll & focus patches...${NC}"
THREAD_VIEW=$(find "$INSTALL_DIR/out/renderer/assets" -name "ThreadView-*.js" | head -n 1)
if [ -f "$THREAD_VIEW" ]; then
  $SUDO node "$PROJECT_ROOT/scripts/patch.js" "$THREAD_VIEW"
else
  echo -e "${YELLOW}[WARN] ThreadView bundle not found, skipping JS patch.${NC}"
fi

echo -e "${BLUE}[*] Installing launcher and system integration...${NC}"
$SUDO install -Dm755 "$PROJECT_ROOT/scripts/start.sh" "$INSTALL_DIR/start.sh"
$SUDO ln -sf "$INSTALL_DIR/start.sh" /usr/bin/xiaomi-mimo-desktop

# Install FreeDesktop desktop entry
$SUDO install -Dm644 "$PROJECT_ROOT/assets/xiaomi-mimo-desktop.desktop" /usr/share/applications/xiaomi-mimo-desktop.desktop

# Install FreeDesktop system icon for docks & app drawers
if [ -f "$INSTALL_DIR/assets/icon.png" ]; then
  $SUDO install -Dm644 "$INSTALL_DIR/assets/icon.png" /usr/share/icons/hicolor/512x512/apps/xiaomi-mimo-desktop.png
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    $SUDO gtk-update-icon-cache -f -t /usr/share/icons/hicolor/ >/dev/null 2>&1 || true
  fi
fi

# Set proper ownership
TARGET_USER="${SUDO_USER:-$USER}"
$SUDO chown -R "$TARGET_USER:$TARGET_USER" "$INSTALL_DIR"

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}  ✓ Installation Complete!                            ${NC}"
echo -e "${GREEN}  Launch via Application Menu or run in terminal:      ${NC}"
echo -e "${GREEN}    xiaomi-mimo-desktop                               ${NC}"
echo -e "${GREEN}======================================================${NC}"
