#!/bin/bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CHROME_DESKTOP="xiaomi-mimo-desktop.desktop"
export ELECTRON_FORCE_IS_PACKAGED=1
export QWENWORK_APP_ID="xiaomi-mimo-desktop"
export MIMO_LINUX_AUTOUPDATE=0

unset ELECTRON_RUN_AS_NODE

# In Linux Wayland sessions (especially GNOME 46 / Ubuntu 24.04),
# Electron native Wayland mode has known upstream issues with IBus/Fcitx Chinese input.
# Defaulting to x11 (XWayland) guarantees 100% working IME, accurate candidate box positioning,
# and full GPU hardware acceleration via Mesa.
# Users who explicitly prefer native Wayland can export MIMO_OZONE_PLATFORM=wayland.
DEFAULT_OZONE="x11"
OZONE_PLATFORM="${MIMO_OZONE_PLATFORM:-$DEFAULT_OZONE}"

OZONE_FLAGS=(
  "--ozone-platform=$OZONE_PLATFORM"
)

if [ "$OZONE_PLATFORM" = "wayland" ]; then
  OZONE_FLAGS+=(
    "--enable-wayland-ime"
    "--wayland-text-input-version=3"
  )
fi

# Look for isolated Electron binary or system electron
if [ -x "$APP_DIR/bin/xiaomi-mimo-desktop" ]; then
  ELECTRON_BIN="$APP_DIR/bin/xiaomi-mimo-desktop"
elif [ -x "$APP_DIR/electron" ]; then
  ELECTRON_BIN="$APP_DIR/electron"
elif command -v electron >/dev/null 2>&1; then
  ELECTRON_BIN="$(command -v electron)"
else
  ELECTRON_BIN="/usr/lib/node_modules/electron/dist/electron"
fi

exec "$ELECTRON_BIN" \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu-sandbox \
  "${OZONE_FLAGS[@]}" \
  "$APP_DIR/out/main/launch.mjs" \
  "$@"
