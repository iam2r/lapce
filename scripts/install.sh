#!/usr/bin/env bash
# 用户级安装: 二进制 + 图标 + 桌面入口（原生 Wayland）
# 用法:
#   scripts/install.sh [二进制路径]   # 默认 target/release/lapce
#   scripts/install.sh --uninstall    # 卸载
set -euo pipefail

APP_ID="dev.lapce.lapce"
BIN_DIR="$HOME/.local/bin"
ICON_BASE="$HOME/.local/share/icons/hicolor"
DESKTOP_DIR="$HOME/.local/share/applications"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit 1; }

if [[ "${1:-}" == "--uninstall" ]]; then
  log "卸载用户级 Lapce ..."
  rm -fv "$BIN_DIR/lapce" "$DESKTOP_DIR/$APP_ID.desktop" \
     "$ICON_BASE"/256x256/apps/"$APP_ID".png \
     "$ICON_BASE"/512x512/apps/"$APP_ID".png 2>/dev/null || true
  command -v update-desktop-database >/dev/null && update-desktop-database "$DESKTOP_DIR" || true
  command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qtf "$ICON_BASE" || true
  log "已卸载 ✓"
  exit 0
fi

SRC="${1:-$REPO_DIR/target/release/lapce}"
[[ -x "$SRC" ]] || die "二进制不可执行: $SRC"
VER="$("$SRC" --version | awk '{print $2}')"

mkdir -p "$BIN_DIR"
install -m755 "$SRC" "$BIN_DIR/lapce"
# 剥离符号表(约减小 26MB); target 里的原始产物保留调试符号
if command -v strip >/dev/null; then strip "$BIN_DIR/lapce"; log "已剥离符号表"; fi
log "二进制 -> $BIN_DIR/lapce (v$VER)"

LOGO="$REPO_DIR/extra/images/logo.png"
[[ -f "$LOGO" ]] || die "找不到图标源: $LOGO"
mkdir -p "$ICON_BASE"/256x256/apps "$ICON_BASE"/512x512/apps
if command -v convert >/dev/null; then
  convert "$LOGO" -resize 256x256 "$ICON_BASE/256x256/apps/$APP_ID.png"
  convert "$LOGO" -resize 512x512 "$ICON_BASE/512x512/apps/$APP_ID.png"
else
  cp "$LOGO" "$ICON_BASE/256x256/apps/$APP_ID.png"
fi
log "图标已安装"

mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_DIR/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Lapce
GenericName=Code Editor
Comment=Lightning-fast and Powerful Code Editor
Exec=$BIN_DIR/lapce %F
TryExec=$BIN_DIR/lapce
Terminal=false
Categories=Development;IDE;
Keywords=editor;ide;code;lapce;
Icon=$APP_ID
StartupNotify=true
StartupWMClass=dev.lapce.lapce
MimeType=text/plain;application/json;application/javascript;text/x-python;text/x-rust;x-scheme-handler/x-lapce;
Actions=new-window;

[Desktop Action new-window]
Name=New Window
Exec=$BIN_DIR/lapce --new %F
EOF
chmod 644 "$DESKTOP_DIR/$APP_ID.desktop"
log "桌面入口 -> $DESKTOP_DIR/$APP_ID.desktop"

command -v update-desktop-database >/dev/null && update-desktop-database "$DESKTOP_DIR" || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qtf "$ICON_BASE" || true

echo
log "✅ Lapce v$VER 安装完成（源码版自带 app_id，任务栏图标正常）"
