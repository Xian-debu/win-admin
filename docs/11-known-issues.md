# 11 · 已知问题（K 系列）

> 规则（照 `docs/08`）：每一条都必须有实测证据，禁止“理论上可能”。
> 修复状态：🔴 未解决 / 🟡 已绕过 / 🟢 已修复（本仓库内已消失）。

| 编号 | 问题 | 证据 | 状态 |
|---|---|---|---|
| K1 | `winps -f` / `winps -`（stdin）模式下 PowerShell 5.1 按 OEM 936 写 stdout，中文变乱码 | `inventory/raw/2026-10-20-fix-verify.txt` V1 | 🟢 载荷首行强制 `[Console]::OutputEncoding=[Text.Encoding]::UTF8` |
| K2 | PowerShell 默认 DPI unaware，取到的是逻辑像素 1707×1067 而非物理 2560×1600 | 同上 V2 | 🟢 `wa-core.ps1` 调用 `SetProcessDpiAwarenessContext([IntPtr]-4)`，失败回退 `SetProcessDPIAware()` |
| K3 | 仓库在 WSL ext4，Windows 的 powershell 读不到 | `docs/02` §3 | 🟡 改为“拷贝到 `C:/Users/Public/win-admin/app/<ver>/` 再执行”（`docs/10` §2） |
| K4 | `winps` 默认临时目录在 Windows 用户 Temp 下，路径随用户/版本漂移 | `/usr/local/bin/winps` 第 26–33 行 | 🟡 部署时 `export WINPS_TMPDIR=/mnt/c/Users/Public/win-admin/tmp` |
| K5 | UIA 遍历整棵桌面树在 Edge 上节点数达数千，单次 `wuia` 可超 10s | 待 M1 实测填数 | 🔴 M1 默认 `--depth 3` + 节点上限 |
| K6 | 未对齐的 `UIA` rect 与截图可能差 1–2px（边框/阴影） | 待 C3 实测 | 🔴 M1 用 Notepad 实测并记录偏差 |
| K7 | Windows 侧载荷若被旧版 `current.txt` 指向已删目录，会“静默不可用” | 安装逻辑设计 | 🟡 `common.sh` 先检查目录存在且含 `MANIFEST.sha256`，否则 `ENV_NOT_INSTALLED` |
| K8 | 中文路径（`/mnt/c/用户/...`）在参数传递时可能被转码 | 未实测 | 🔴 约定所有路径用 ASCII，必要时用 Windows 短路径 |
| K9 | 锁屏/切用户后 UIA 与截图可能“成功但内容是安全桌面” | 待 M3 S3 实测 | 🔴 M3 用 `OpenInputDesktop` 判定，判定失败即拒 |
| K10 | 无 `DISPLAY` 的 WSL 里跑任何 GUI 程序都会失败（不是本仓库问题，但要知道） | `docs/02` §1 | 🟢 设计上不跑 WSL GUI，全部交给 Windows 侧 |
