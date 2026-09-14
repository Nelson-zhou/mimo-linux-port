#!/bin/bash
set -euo pipefail

# mimo-linux-port: Automated Debian package builder for Xiaomi MiMo Desktop
# Unpacks upstream package, applies scroll & IME patches, and repacks clean deb.

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}      Xiaomi MiMo Desktop .deb Package Builder        ${NC}"
echo -e "${BLUE}======================================================${NC}"

INPUT_PKG="${1:-}"
OUTPUT_DEB="${2:-}"

# 1. Discover input package if not specified
if [ -z "$INPUT_PKG" ]; then
  CANDIDATES=(
    "./XiaomiMiMo-x64.deb"
    "./xiaomi-mimo-desktop.deb"
    "$HOME/xiaomi-mimo-desktop-26.909.91205-linux-x64-fixed.deb"
    "$HOME/.config/XiaomiMiMoDesktop/updates/XiaomiMiMo-26.909.91205-x64.deb"
  )
  for cand in "${CANDIDATES[@]}"; do
    if [ -f "$cand" ]; then
      INPUT_PKG="$cand"
      echo -e "${GREEN}[+] Detected input package: $INPUT_PKG${NC}"
      break
    fi
  done
fi

if [ -z "$INPUT_PKG" ] || [ ! -f "$INPUT_PKG" ]; then
  echo -e "${RED}[ERROR] Input package not found!${NC}"
  echo "Usage: $0 <path-to-upstream.deb> [output-path.deb]"
  exit 1
fi

# 2. Prepare temporary build workspace
BUILD_TMP=$(mktemp -d /tmp/mimo-deb-build-XXXXXX)
trap 'rm -rf "$BUILD_TMP"' EXIT

PKG_ROOT="$BUILD_TMP/pkg"
mkdir -p "$PKG_ROOT"

echo -e "${BLUE}[*] Unpacking upstream package: $INPUT_PKG...${NC}"
dpkg-deb -x "$INPUT_PKG" "$PKG_ROOT"

# Extract control information if available
if dpkg-deb -e "$INPUT_PKG" "$PKG_ROOT/DEBIAN" 2>/dev/null; then
  echo -e "${GREEN}[+] Extracted DEBIAN control scripts.${NC}"
else
  mkdir -p "$PKG_ROOT/DEBIAN"
fi

# 3. Detect version from control or default
VERSION="26.909.91205"
if [ -f "$PKG_ROOT/DEBIAN/control" ]; then
  DETECTED_VER=$(grep -E "^Version:" "$PKG_ROOT/DEBIAN/control" | awk '{print $2}' || true)
  if [ -n "$DETECTED_VER" ]; then
    VERSION="$DETECTED_VER"
  fi
fi

if [ -z "$OUTPUT_DEB" ]; then
  OUTPUT_DEB="$PROJECT_ROOT/xiaomi-mimo-desktop_${VERSION}-linux-x64.deb"
fi

# Ensure /opt/mimo-desktop-cn structure
OPT_DIR="$PKG_ROOT/opt/mimo-desktop-cn"
if [ ! -d "$OPT_DIR" ] && [ -d "$PKG_ROOT/out" ]; then
  mkdir -p "$PKG_ROOT/opt/mimo-desktop-cn"
  mv "$PKG_ROOT/out" "$OPT_DIR/"
  [ -d "$PKG_ROOT/assets" ] && mv "$PKG_ROOT/assets" "$OPT_DIR/"
  [ -d "$PKG_ROOT/node_modules" ] && mv "$PKG_ROOT/node_modules" "$OPT_DIR/"
  [ -f "$PKG_ROOT/package.json" ] && mv "$PKG_ROOT/package.json" "$OPT_DIR/"
fi

# 4. Apply JavaScript patches
echo -e "${BLUE}[*] Applying compatibility patches...${NC}"
THREAD_VIEW=$(find "$OPT_DIR/out/renderer/assets" -name "ThreadView-*.js" 2>/dev/null | head -n 1 || true)
if [ -n "$THREAD_VIEW" ] && [ -f "$THREAD_VIEW" ]; then
  node "$PROJECT_ROOT/scripts/patch.js" "$THREAD_VIEW"
else
  echo -e "${YELLOW}[WARN] ThreadView bundle not found; skipping JS patch.${NC}"
fi

# 5. Install launcher & FreeDesktop integration
echo -e "${BLUE}[*] Installing start.sh launcher and desktop entry...${NC}"
install -Dm755 "$PROJECT_ROOT/scripts/start.sh" "$OPT_DIR/start.sh"

mkdir -p "$PKG_ROOT/usr/bin"
ln -sf "/opt/mimo-desktop-cn/start.sh" "$PKG_ROOT/usr/bin/xiaomi-mimo-desktop"

mkdir -p "$PKG_ROOT/usr/share/applications"
install -Dm644 "$PROJECT_ROOT/assets/xiaomi-mimo-desktop.desktop" "$PKG_ROOT/usr/share/applications/xiaomi-mimo-desktop.desktop"

# 6. Setup icons
echo -e "${BLUE}[*] Setting up application icons...${NC}"
ICON_SRC=""
if [ -f "$OPT_DIR/assets/icon.png" ]; then
  ICON_SRC="$OPT_DIR/assets/icon.png"
elif [ -f "$OPT_DIR/assets/icon-mac.png" ]; then
  ICON_SRC="$OPT_DIR/assets/icon-mac.png"
elif [ -f "$OPT_DIR/assets/logo.png" ]; then
  ICON_SRC="$OPT_DIR/assets/logo.png"
fi

if [ -n "$ICON_SRC" ]; then
  # Install 512x512 and pixmaps
  mkdir -p "$PKG_ROOT/usr/share/pixmaps"
  install -Dm644 "$ICON_SRC" "$PKG_ROOT/usr/share/pixmaps/xiaomi-mimo-desktop.png"

  # Generate/copy standard icon sizes
  SIZES=(48 64 128 256 512 1024)
  for sz in "${SIZES[@]}"; do
    DEST_DIR="$PKG_ROOT/usr/share/icons/hicolor/${sz}x${sz}/apps"
    mkdir -p "$DEST_DIR"
    if python3 -c "from PIL import Image; img=Image.open('$ICON_SRC'); img.resize(($sz,$sz), Image.Resampling.LANCZOS).save('$DEST_DIR/xiaomi-mimo-desktop.png')" 2>/dev/null; then
      ln -sf "xiaomi-mimo-desktop.png" "$DEST_DIR/xiaomi-mimo.png"
    else
      cp "$ICON_SRC" "$DEST_DIR/xiaomi-mimo-desktop.png"
      ln -sf "xiaomi-mimo-desktop.png" "$DEST_DIR/xiaomi-mimo.png"
    fi
  done
fi

# 7. Write / Update Control metadata
cat > "$PKG_ROOT/DEBIAN/control" <<EOF
Package: xiaomi-mimo-desktop
Version: ${VERSION}
Architecture: amd64
Maintainer: Xiaomi MiMo Community Linux Team
Section: utils
Depends: libc6 (>= 2.31), libnotify4, xdg-utils, libsecret-1-0, libnss3, libasound2 | libasound2t64, libxtst6, libxrandr2
Recommends: libgtk-3-0, zenity
Description: Xiaomi MiMo Desktop Client (Linux Port)
 Xiaomi MiMo Desktop AI assistant for Linux x64 with scroll-lock,
 focus-stealing, and Wayland IME compatibility fixes.
EOF

# Maintainer scripts
cat > "$PKG_ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ -x "$(command -v gtk-update-icon-cache)" ]; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
fi
if [ -x "$(command -v update-desktop-database)" ]; then
    update-desktop-database /usr/share/applications 2>/dev/null || true
fi
chmod +x /opt/mimo-desktop-cn/start.sh 2>/dev/null || true
EOF
chmod 755 "$PKG_ROOT/DEBIAN/postinst"

cat > "$PKG_ROOT/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ -x "$(command -v gtk-update-icon-cache)" ]; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
fi
if [ -x "$(command -v update-desktop-database)" ]; then
    update-desktop-database /usr/share/applications 2>/dev/null || true
fi
EOF
chmod 755 "$PKG_ROOT/DEBIAN/postrm"

# Fix permissions
find "$PKG_ROOT" -type d -exec chmod 755 {} +
chmod 755 "$PKG_ROOT/DEBIAN"
chmod 755 "$OPT_DIR/start.sh"

# 8. Repack Debian package
echo -e "${BLUE}[*] Packaging into $OUTPUT_DEB...${NC}"
dpkg-deb --build --root-owner-group "$PKG_ROOT" "$OUTPUT_DEB"

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}  ✓ Package built successfully!                        ${NC}"
echo -e "${GREEN}  File: $OUTPUT_DEB${NC}"
echo -e "${GREEN}  Size: $(du -h "$OUTPUT_DEB" | cut -f1)${NC}"
echo -e "${GREEN}  SHA256: $(sha256sum "$OUTPUT_DEB" | awk '{print $1}')${NC}"
echo -e "${GREEN}======================================================${NC}"
