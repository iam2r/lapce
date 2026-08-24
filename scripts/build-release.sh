#!/usr/bin/env bash
# 编译带 app_id 修复的 Lapce（floem 补丁随子模块走）
#
# 用法:
#   scripts/build-release.sh          # 增量编译
#   scripts/build-release.sh --clean  # 清理后全量编译
#
# 前置条件:
#   - rustup/cargo
#   - 构建依赖: pkg-config libxkbcommon-dev libwayland-dev libfontconfig1-dev libxcb1-dev
#   - 子模块已拉取: git submodule update --init
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit 1; }

command -v cargo >/dev/null || die "需要 cargo (rustup)"

# ---------- 1. 子模块校验 ----------
[[ -f floem/Cargo.toml ]] || die "floem 子模块未拉取: git submodule update --init"
SUB_HEAD="$(git -C floem rev-parse HEAD)"
log "floem 子模块: $(git -C floem log --oneline -1)"

# ---------- 2. 补丁校验（幂等） ----------
if ! grep -q "WindowAttributesExtWayland" floem/src/app_handle.rs; then
  log "子模块缺少 app_id 补丁，自动应用 ..."
  python3 - floem/src/app_handle.rs <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()
anchor = """            .with_resizable(resizable)
            .with_enabled_buttons(enabled_buttons);
"""
patch = anchor + """
        // Set the application name so desktop environments can associate the
        // window with its .desktop entry (dock icon, window grouping, etc).
        #[cfg(target_os = "linux")]
        {
            use winit::platform::x11::WindowAttributesExtX11;
            window_attributes =
                WindowAttributesExtX11::with_name(window_attributes, "dev.lapce.lapce", "lapce");
        }
        #[cfg(target_os = "linux")]
        {
            use winit::platform::wayland::WindowAttributesExtWayland;
            window_attributes =
                WindowAttributesExtWayland::with_name(window_attributes, "dev.lapce.lapce", "lapce");
        }
"""
assert src.count(anchor) == 1, "anchor not found or ambiguous"
open(path, "w").write(src.replace(anchor, patch))
PYEOF
  log "补丁已应用（仅工作区，未提交）"
else
  log "app_id 补丁已存在 ✓"
fi

# ---------- 3. 依赖路径校验 ----------
grep -q 'floem = { path = "floem"' Cargo.toml || die "Cargo.toml 的 floem 依赖未指向子模块路径"

# ---------- 4. 编译 ----------
[[ "${1:-}" == "--clean" ]] && { log "清理 target/ ..."; cargo clean; }
log "开始 release 编译（首次约 20~40 分钟）..."
# 以 Stable 通道身份构建: 数据目录与官方发布版一致(lapce-stable),
# 版本号无 Nightly 后缀
export RELEASE_TAG_NAME="$(git describe --tags --abbrev=0 2>/dev/null || echo v0.4.6)"
cargo build --release

[[ -x target/release/lapce ]] || die "编译产物不存在"
VER="$(target/release/lapce --version | awk '{print $2}')"
echo
log "✅ 编译完成: v$VER"
log "   安装:   scripts/install.sh"
log "   打 deb: scripts/make-deb.sh"
