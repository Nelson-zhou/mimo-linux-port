#!/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CHROME_DESKTOP="xiaomi-mimo-desktop.desktop"
export ELECTRON_FORCE_IS_PACKAGED=1
export QWENWORK_APP_ID="xiaomi-mimo-desktop"
export MIMO_LINUX_AUTOUPDATE=0

unset ELECTRON_RUN_AS_NODE

# -----------------------------------------------------------------------------
# 1. Self-Healing: Clean up orphaned / stale SingletonLock
# -----------------------------------------------------------------------------
# If a previous MiMo instance crashed or was killed, a stale SingletonLock
# symlink causes app.requestSingleInstanceLock() to return false, triggering
# an immediate silent app.exit(0) (fake crash / 闪退).
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/XiaomiMiMoDesktop"
if [ -L "$CONFIG_DIR/SingletonLock" ]; then
  LOCK_TARGET="$(readlink "$CONFIG_DIR/SingletonLock" 2>/dev/null || true)"
  LOCK_PID="${LOCK_TARGET##*-}"
  if [ -n "$LOCK_PID" ] && [[ "$LOCK_PID" =~ ^[0-9]+$ ]]; then
    if ! kill -0 "$LOCK_PID" 2>/dev/null; then
      echo "[mimo-launcher] Cleaning up stale SingletonLock from terminated PID: $LOCK_PID"
      rm -f "$CONFIG_DIR"/Singleton*
    fi
  else
    # Non-numeric or broken symlink
    rm -f "$CONFIG_DIR"/Singleton*
  fi
fi

# -----------------------------------------------------------------------------
# 2. Pre-flight Check: Essential Shared Libraries
# -----------------------------------------------------------------------------
check_lib() {
  local lib="$1"
  if /sbin/ldconfig -p 2>/dev/null | grep -q "$lib" || ldconfig -p 2>/dev/null | grep -q "$lib"; then
    return 0
  fi
  if [ -f "/lib/x86_64-linux-gnu/$lib" ] || [ -f "/usr/lib/x86_64-linux-gnu/$lib" ] || [ -f "/usr/lib/$lib" ] || [ -f "/usr/lib64/$lib" ]; then
    return 0
  fi
  return 1
}

MISSING_LIBS=()
if ! check_lib "libsecret-1.so.0"; then
  MISSING_LIBS+=("libsecret-1.so.0 (Keytar / 登录密钥凭据存储依赖)")
fi

if [ ${#MISSING_LIBS[@]} -gt 0 ]; then
  echo -e "\033[1;33m[WARN] 检测到系统可能缺失以下关键运行库，可能导致应用闪退：\033[0m"
  for m in "${MISSING_LIBS[@]}"; do
    echo -e "  - \033[0;31m$m\033[0m"
  done
  echo -e "推荐解决方案："
  echo -e "  Ubuntu / Debian: \033[0;32msudo apt install -y libsecret-1-0 libxtst6\033[0m"
  echo -e "  Arch Linux:      \033[0;32msudo pacman -S libsecret libxtst\033[0m"
  echo -e "  Fedora / RHEL:   \033[0;32msudo dnf install -y libsecret libXtst\033[0m"
  echo ""
fi

# -----------------------------------------------------------------------------
# 3. Display Server & IME Configuration
# -----------------------------------------------------------------------------
# Defaulting to x11 (XWayland) guarantees 100% working IME candidate box positioning
# and prevents blank white screens caused by Wayland GPU/canvas pipeline desync.
# Set MIMO_OZONE_PLATFORM=wayland to force native Wayland.
DEFAULT_OZONE="x11"
OZONE_PLATFORM="${MIMO_OZONE_PLATFORM:-$DEFAULT_OZONE}"

OZONE_FLAGS=(
  "--ozone-platform=$OZONE_PLATFORM"
)

PREFS_FILE="$CONFIG_DIR/preferences.json"

if [ "$OZONE_PLATFORM" = "wayland" ]; then
  OZONE_FLAGS+=(
    "--enable-wayland-ime"
    "--wayland-text-input-version=3"
  )
else
  # x11 / XWayland mode:
  # 26.914+ introduced C4() which auto-detects Wayland via env vars and overrides
  # the CLI --ozone-platform flag. Scrub Wayland hints from the environment so
  # C4("x11") correctly returns "x11" instead of falling back to "wayland".
  unset WAYLAND_DISPLAY
  export XDG_SESSION_TYPE=x11

  # Also patch all known preferences.json locations to pin displayServer=x11.
  # Electron may read from "XiaomiMiMoDesktop", "Xiaomi MiMo", or "Electron" dirs.
  for PREFS_FILE in \
    "$CONFIG_DIR/preferences.json" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/Xiaomi MiMo/preferences.json" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/Electron/preferences.json"; do
    if [ -f "$PREFS_FILE" ]; then
      sed -i -E 's/"displayServer"[[:space:]]*:[[:space:]]*"(auto|wayland)"/"displayServer": "x11"/g' \
        "$PREFS_FILE" 2>/dev/null || true
    fi
  done
fi

# -----------------------------------------------------------------------------
# 4. Locate Electron Runtime Binary
# -----------------------------------------------------------------------------
ELECTRON_BIN=""
if [ -x "$APP_DIR/bin/xiaomi-mimo-desktop" ]; then
  ELECTRON_BIN="$APP_DIR/bin/xiaomi-mimo-desktop"
elif [ -x "$APP_DIR/xiaomi-mimo-desktop" ]; then
  ELECTRON_BIN="$APP_DIR/xiaomi-mimo-desktop"
elif [ -x "$APP_DIR/electron" ]; then
  ELECTRON_BIN="$APP_DIR/electron"
elif command -v electron >/dev/null 2>&1; then
  ELECTRON_BIN="$(command -v electron)"
elif [ -x "/usr/lib/node_modules/electron/dist/electron" ]; then
  ELECTRON_BIN="/usr/lib/node_modules/electron/dist/electron"
fi

if [ -z "$ELECTRON_BIN" ] || [ ! -x "$ELECTRON_BIN" ]; then
  MSG="错误: 未找到可执行的 Electron 运行时二进制文件。\n请确保安装完整或安装全局 electron。"
  echo -e "\033[0;31m$MSG\033[0m"
  if command -v zenity >/dev/null 2>&1; then
    zenity --error --text="$MSG" 2>/dev/null || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "小米 MiMo 启动错误" "$MSG" || true
  fi
  exit 1
fi

# -----------------------------------------------------------------------------
# 5. Launch with Sandbox & GPU Flags
# -----------------------------------------------------------------------------
ENTRY_TARGET="$APP_DIR"
if [ ! -f "$APP_DIR/package.json" ] && [ -f "$APP_DIR/out/main/launch.mjs" ]; then
  ENTRY_TARGET="$APP_DIR/out/main/launch.mjs"
fi

exec "$ELECTRON_BIN" \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu-sandbox \
  "${OZONE_FLAGS[@]}" \
  "$ENTRY_TARGET" \
  "$@"
