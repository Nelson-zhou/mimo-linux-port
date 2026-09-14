#!/bin/bash
set -euo pipefail

# mimo-linux-port: One-click installer for Xiaomi MiMo Desktop on Linux
# Features:
# - Auto-downloads official package from Xiaomi CDN if not found locally (0 copyright risk)
# - Unpacks ASAR archive and copies official bundled Electron runtime
# - Applies viewport scroll-lock and focus-stealing patches
# - Configures FreeDesktop launcher, Hi-Res icons, and Wayland/X11 IME support

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
    $SUDO apt-get install -y -qq libsecret-1-0 libxtst6 python3 || true
  fi
fi

TMP_WORK=$(mktemp -d /tmp/mimo-install-XXXXXX)
trap 'rm -rf "$TMP_WORK"' EXIT

# 1. Detect local package or download from official Xiaomi CDN
SOURCE_PKG=""
CANDIDATES=(
  "${1:-}"
  "./XiaomiMiMo-x64.deb"
  "./XiaomiMiMo.deb"
  "/home/${SUDO_USER:-$USER}/xiaomi-mimo-desktop-26.909.91205-linux-x64-fixed.deb"
  "$HOME/xiaomi-mimo-desktop-26.909.91205-linux-x64-fixed.deb"
  "/home/${SUDO_USER:-$USER}/.config/XiaomiMiMoDesktop/updates/XiaomiMiMo-26.909.91205-x64.deb"
  "$HOME/.config/XiaomiMiMoDesktop/updates/XiaomiMiMo-26.909.91205-x64.deb"
)

for cand in "${CANDIDATES[@]}"; do
  if [ -n "$cand" ] && [ -f "$cand" ]; then
    SOURCE_PKG="$cand"
    echo -e "${GREEN}[+] Detected local package: $SOURCE_PKG${NC}"
    break
  fi
done

if [ -z "$SOURCE_PKG" ]; then
  echo -e "${BLUE}[*] 本地未找到安装包，正在从小米官方 CDN 自动获取最新版本...${NC}"
  MANIFEST_URL="https://mimocode-cdn.xiaomimimo.com/mimocode/mimodesktop/manifest.json"
  OFFICIAL_URL=$(curl -sSL "$MANIFEST_URL" | grep -o 'https://[^"]*x64\.deb' | head -n 1 || true)
  if [ -z "$OFFICIAL_URL" ]; then
    OFFICIAL_URL="https://mimocode-cdn.xiaomimimo.com/mimocode/mimodesktop/XiaomiMiMo-26.909.91205-x64.deb"
  fi
  echo -e "${GREEN}[+] 官方下载直链: $OFFICIAL_URL${NC}"
  SOURCE_PKG="$TMP_WORK/XiaomiMiMo-upstream.deb"
  echo -e "${BLUE}[*] 正在下载官方安装包 (约 240MB)...${NC}"
  curl -# -fSL -o "$SOURCE_PKG" "$OFFICIAL_URL"
fi

# 2. Unpack package
echo -e "${BLUE}[*] Unpacking $SOURCE_PKG...${NC}"
dpkg-deb -x "$SOURCE_PKG" "$TMP_WORK/pkg"

$SUDO mkdir -p "$INSTALL_DIR"

# 3. Handle official vs community package layout
OFFICIAL_OPT="$TMP_WORK/pkg/opt/Xiaomi MiMo"
if [ -d "$OFFICIAL_OPT" ]; then
  echo -e "${BLUE}[*] Processing official Xiaomi package structure...${NC}"
  ASAR_FILE="$OFFICIAL_OPT/resources/app.asar"
  if [ -f "$ASAR_FILE" ]; then
    echo -e "${BLUE}[*] Extracting application bundle from ASAR...${NC}"
    $SUDO python3 "$PROJECT_ROOT/scripts/unpack_asar.py" "$ASAR_FILE" "$INSTALL_DIR"
  fi

  if [ -d "$OFFICIAL_OPT/resources/app.asar.unpacked/node_modules" ]; then
    echo -e "${BLUE}[*] Merging native binary addons...${NC}"
    $SUDO cp -r "$OFFICIAL_OPT/resources/app.asar.unpacked/node_modules/"* "$INSTALL_DIR/node_modules/" || true
  fi

  # Copy bundled official Electron runtime to bin/
  echo -e "${BLUE}[*] Setting up official Electron runtime...${NC}"
  $SUDO mkdir -p "$INSTALL_DIR/bin"
  $SUDO cp "$OFFICIAL_OPT/xiaomi-mimo-desktop" "$INSTALL_DIR/bin/"
  $SUDO cp -r "$OFFICIAL_OPT"/*.so* "$INSTALL_DIR/bin/" 2>/dev/null || true
  $SUDO cp -r "$OFFICIAL_OPT"/*.bin "$INSTALL_DIR/bin/" 2>/dev/null || true
  $SUDO cp -r "$OFFICIAL_OPT"/*.pak "$INSTALL_DIR/bin/" 2>/dev/null || true
  $SUDO cp -r "$OFFICIAL_OPT"/*.dat "$INSTALL_DIR/bin/" 2>/dev/null || true
  $SUDO chmod +x "$INSTALL_DIR/bin/xiaomi-mimo-desktop"
elif [ -d "$TMP_WORK/pkg/opt/mimo-desktop-cn" ]; then
  echo -e "${BLUE}[*] Installing application files to $INSTALL_DIR...${NC}"
  $SUDO cp -r "$TMP_WORK/pkg/opt/mimo-desktop-cn/"* "$INSTALL_DIR/"
else
  $SUDO cp -r "$TMP_WORK/pkg/"* "$INSTALL_DIR/"
fi

# 4. Apply Linux scroll & focus patches
echo -e "${BLUE}[*] Applying Linux scroll & focus patches...${NC}"
THREAD_VIEW=$(find "$INSTALL_DIR/out/renderer/assets" -name "ThreadView-*.js" 2>/dev/null | head -n 1 || true)
if [ -n "$THREAD_VIEW" ] && [ -f "$THREAD_VIEW" ]; then
  $SUDO node "$PROJECT_ROOT/scripts/patch.js" "$THREAD_VIEW"
else
  echo -e "${YELLOW}[WARN] ThreadView bundle not found, skipping JS patch.${NC}"
fi

# 5. Install launcher and system integration
echo -e "${BLUE}[*] Installing launcher and system integration...${NC}"
$SUDO install -Dm755 "$PROJECT_ROOT/scripts/start.sh" "$INSTALL_DIR/start.sh"
$SUDO ln -sf "$INSTALL_DIR/start.sh" /usr/bin/xiaomi-mimo-desktop

# Install FreeDesktop desktop entry
$SUDO install -Dm644 "$PROJECT_ROOT/assets/xiaomi-mimo-desktop.desktop" /usr/share/applications/xiaomi-mimo-desktop.desktop

# Install FreeDesktop system icons (48px ~ 512px)
ICON_SRC=""
if [ -f "$INSTALL_DIR/assets/icon.png" ]; then
  ICON_SRC="$INSTALL_DIR/assets/icon.png"
elif [ -f "$INSTALL_DIR/assets/icon-mac.png" ]; then
  ICON_SRC="$INSTALL_DIR/assets/icon-mac.png"
elif [ -f "$INSTALL_DIR/assets/logo.png" ]; then
  ICON_SRC="$INSTALL_DIR/assets/logo.png"
fi

if [ -n "$ICON_SRC" ]; then
  $SUDO install -Dm644 "$ICON_SRC" /usr/share/icons/hicolor/512x512/apps/xiaomi-mimo-desktop.png
  $SUDO install -Dm644 "$ICON_SRC" /usr/share/pixmaps/xiaomi-mimo-desktop.png 2>/dev/null || true
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    $SUDO gtk-update-icon-cache -f -t /usr/share/icons/hicolor/ >/dev/null 2>&1 || true
  fi
fi

# 6. Set proper ownership
TARGET_USER="${SUDO_USER:-$USER}"
$SUDO chown -R "$TARGET_USER:$TARGET_USER" "$INSTALL_DIR"

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}  ✓ Installation Complete!                            ${NC}"
echo -e "${GREEN}  Launch via Application Menu or run in terminal:      ${NC}"
echo -e "${GREEN}    xiaomi-mimo-desktop                               ${NC}"
echo -e "${GREEN}======================================================${NC}"
