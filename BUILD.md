# 本地构建指南（带 app_id 修复的 Lapce）

本分支在官方 v0.4.6 基础上做了两处改动：

1. **floem 子模块**（`iam2r/floem` 分支 `fix/app-id`）：给窗口属性设置
   `with_name("dev.lapce.lapce", "lapce")`，修复 GNOME Wayland 下任务栏
   无图标的问题（上游 issue [lapce#2199](https://github.com/lapce/lapce/issues/2199)）
2. **Cargo.toml**：floem / floem-editor-core 依赖指向仓库内子模块路径

## 快速开始

```bash
git clone --recurse-submodules -b local-build https://github.com/iam2r/lapce
cd lapce

# 构建依赖（Debian/Ubuntu，一次性）
sudo apt install pkg-config libxkbcommon-dev libwayland-dev libfontconfig1-dev libxcb1-dev

scripts/build-release.sh      # 编译（首次约 20~40 分钟）
scripts/install.sh            # 用户级安装: ~/.local/bin + 图标 + 桌面入口
# 或
scripts/make-deb.sh           # 打成 .deb 系统级安装
```

## 脚本一览

| 脚本 | 作用 |
|---|---|
| `scripts/build-release.sh [--clean]` | 校验子模块与补丁（缺失自动重打）→ release 编译 |
| `scripts/install.sh [--uninstall]` | 用户级安装/卸载（原生 Wayland 桌面入口） |
| `scripts/make-deb.sh [二进制]` | 打包 .deb，版本号形如 `0.4.6+appid` |

## 升级到新版 Lapce

```bash
git fetch --tags && git checkout -B local-build v0.4.7   # 换成新 tag
FLOEM_REV=$(grep -oP 'floem", rev = "\K[0-9a-f]+' Cargo.toml)  # 新版锁定的 floom rev
cd floem && git fetch origin && git checkout -B fix/app-id "$FLOEM_REV" && cd ..
# 在 floem 里重新应用 scripts/build-release.sh 内嵌的补丁（脚本会自动打）
git add -A && git commit -m "rebase app_id patch onto new floem rev" && git push origin fix/app-id
cd .. && git add -A && git commit -m "update to v0.4.7" && git push origin local-build
scripts/build-release.sh
```

## 与用户级安装的关系

`.deb` 安装到 `/usr/bin/lapce`；用户级安装在 `~/.local/bin/lapce`。
PATH 中 `~/.local/bin` 优先，两者共存时实际运行的是用户级版本——建议二选一。

## 为什么不用官方包？

官方预编译包存在 lapce#2199：floem 未调用 winit 的 `with_name()`，
Wayland 窗口没有 app_id，GNOME 无法把窗口匹配到桌面文件 → 任务栏显示无图标。
该 issue 已被上游关闭但代码层修复至今未合入，故维护此本地构建分支。
