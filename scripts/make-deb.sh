#!/usr/bin/env bash
# 把编译产物打包成 .deb（系统级安装: /usr/bin/lapce）
#
# 用法:
#   scripts/make-deb.sh [二进制路径]   # 默认 target/release/lapce
# 输出:
#   ./lapce_<版本>_amd64.deb
# 安装: sudo apt install ./lapce_*.deb
# 注意: 与用户级 ~/.local/bin/lapce 共存时，PATH 优先命中后者，建议二选一。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${1:-$REPO_DIR/target/release/lapce}"
OUT_DIR="$REPO_DIR"
WORK="$(mktemp -d /tmp/lapce-deb.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -x "$BIN" ]] || die "找不到二进制: $BIN (先跑 scripts/build-release.sh)"

VER="$("$BIN" --version | awk '{print $2}' | cut -d'+' -f1)"
GIT_HASH="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
# 时间戳前缀保证版本号单调递增(避免被 apt 判定为降级), 哈希提供溯源
PKGVER="${VER}+appid.$(date +%Y%m%d%H%M).g${GIT_HASH}"
STAGE="$WORK/lapce_${PKGVER}_amd64"
APP_ID="dev.lapce.lapce"

log "打包 Lapce v$PKGVER ..."

# ---------- 目录结构 ----------
install -Dm755 "$BIN" "$STAGE/usr/bin/lapce"
command -v strip >/dev/null && strip "$STAGE/usr/bin/lapce" || true
mkdir -p "$STAGE/usr/share/icons/hicolor/256x256/apps" \
         "$STAGE/usr/share/icons/hicolor/512x512/apps" \
         "$STAGE/usr/share/applications" \
         "$STAGE/DEBIAN"

# ---------- 图标（仓库自带的官方 logo） ----------
LOGO="$REPO_DIR/extra/images/logo.png"
[[ -f "$LOGO" ]] || die "找不到图标源: $LOGO"
if command -v convert >/dev/null; then
  convert "$LOGO" -resize 256x256 "$STAGE/usr/share/icons/hicolor/256x256/apps/$APP_ID.png"
  convert "$LOGO" -resize 512x512 "$STAGE/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"
else
  cp "$LOGO" "$STAGE/usr/share/icons/hicolor/256x256/apps/$APP_ID.png"
fi

# ---------- 桌面入口 ----------
cat > "$STAGE/usr/share/applications/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Lapce
GenericName=Code Editor
Comment=Lightning-fast and Powerful Code Editor
Exec=/usr/bin/lapce %F
TryExec=/usr/bin/lapce
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
Exec=/usr/bin/lapce --new %F
EOF

# ---------- 控制文件 ----------
cat > "$STAGE/DEBIAN/control" <<EOF
Package: lapce
Version: $PKGVER
Section: devel
Priority: optional
Architecture: amd64
Maintainer: iamrazo <bestwishtous@gmail.com>
Depends: libc6 (>= 2.35)
Recommends: libwayland-client0, libxkbcommon0, libxkbcommon-x11-0, libx11-6, libxcb1
Suggests: git
Description: Lightning-fast and Powerful Code Editor (local build with app_id fix)
 Lapce is a lightning-fast, open-source code editor written in Rust.
 .
 Locally rebuilt from https://github.com/iam2r/lapce (branch local-build)
 with a floem patch that sets the window application name, fixing
 dock/taskbar icons under GNOME Wayland (lapce#2199).
EOF

# ---------- 文档: 版权 + 变更日志 (lintian 要求) ----------
DOCDIR="$STAGE/usr/share/doc/lapce"
mkdir -p "$DOCDIR"
[[ -f "$REPO_DIR/LICENSE" ]] && cp "$REPO_DIR/LICENSE" "$WORK/upstream-license" || true
cat > "$DOCDIR/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: lapce
Source: https://github.com/lapce/lapce

Files: *
Copyright: 2022-2026 Lapce contributors
License: Apache-2.0

Files: debian/*
Copyright: 2026 iamrazo <bestwishtous@gmail.com>
License: MIT
EOF
cat > "$WORK/changelog" <<EOF
lapce ($PKGVER) unstable; urgency=medium

  * Local rebuild with window app_id fix for upstream lapce#2199
    (dock/taskbar icon under GNOME Wayland).
  * Based on upstream v$VER.

 -- iamrazo <bestwishtous@gmail.com>  $(date -R)
EOF
gzip -9n -c "$WORK/changelog" > "$DOCDIR/changelog.gz"

# ---------- man 手册页 ----------
MANDIR="$STAGE/usr/share/man/man1"
mkdir -p "$MANDIR"
cat > "$WORK/lapce.1" <<EOF
.TH LAPCE 1 "August 2026" "lapce $VER" "User Commands"
.SH NAME
lapce \- Lightning\-fast and Powerful Code Editor
.SH SYNOPSIS
.B lapce
.RI [ options ]
.RI [ files ...]
.SH DESCRIPTION
Lapce is a lightning\-fast, open\-source code editor written in Rust,
featuring built\-in LSP support, modal editing and remote development.
.PP
This build carries a window app_id fix for GNOME Wayland dock icons
(upstream lapce#2199); self\-update is disabled.
EOF
gzip -9n -c "$WORK/lapce.1" > "$MANDIR/lapce.1.gz"

# ---------- 权限规范化 (lintian) ----------
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/usr/bin/lapce"

# ---------- 维护脚本 ----------
cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null && update-desktop-database /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
EOF
cat > "$STAGE/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null && update-desktop-database /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
EOF
chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"

# ---------- 构建 ----------
cd "$WORK"
dpkg-deb --build --root-owner-group "$STAGE" >/dev/null
OUT="$OUT_DIR/lapce_${PKGVER}_amd64.deb"
mv "$WORK/lapce_${PKGVER}_amd64.deb" "$OUT"
ls -lh "$OUT"
# 家目录通常 750, apt 沙箱用户 _apt 无法穿越 → 安装时会有 unsandboxed 警告;
# 拷到 /tmp 即可消除
cp "$OUT" /tmp/
log "✅ 完成！安装(无警告): sudo apt install /tmp/$(basename "$OUT")"
