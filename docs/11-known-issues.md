# 11 · 已知问题（K 系列）

> 规则（照 `docs/08`）：每一条都必须有实测证据，禁止“理论上可能”。
> 修复状态：🔴 未解决 / 🟡 已绕过 / 🟢 已修复（本仓库内已消失）。

| 编号 | 问题 | 证据 | 状态 |
|---|---|---|---|
| K1 | `winps -f` / `winps -`（stdin）模式下 PowerShell 5.1 按 OEM 936 写 stdout，中文变乱码 | `inventory/raw/2026-10-20-fix-verify.txt` V1 | 🟢 载荷首行强制 `[Console]::OutputEncoding=[Text.Encoding]::UTF8` |
| K2 | PowerShell 默认 DPI unaware，取到的是逻辑像素 1707×1067 而非物理 2560×1600 | 同上 V2 | 🟢 `wa-core.ps1` 调用 `SetProcessDpiAwarenessContext([IntPtr]-4)`，失败回退 `SetProcessDPIAware()` |
| K3 | 仓库在 WSL ext4，Windows 的 powershell 读不到 | `docs/02` §3 | 🟡 改为“拷贝到 `C:/Users/Public/win-admin/app/<ver>/` 再执行”（`docs/10` §2） |
| K4 | `winps` 默认临时目录在 Windows 用户 Temp 下，路径随用户/版本漂移 | `/usr/local/bin/winps` 第 26–33 行 | 🟡 部署时 `export WINPS_TMPDIR=/mnt/c/Users/Public/win-admin/tmp` |
| K5 | UIA 遍历整棵桌面树在 Edge 上节点数达数千，单次 `wuia` 可超 10s | 实测：不做限制时 474 窗口 × `Get-Process` 耗时 12.4 s | 🟢 默认 `--depth 3` + 400 节点上限 + 廉价预筛 → 0.5–0.74 s |
| K6 | 未对齐的 `UIA` rect 与截图可能差 1–2px（边框/阴影） | C3 实测 Notepad：uia `285 285 2145 1008` = `GetWindowRect` 同值，偏差 0px | 🟢 无需修正；仍保留 ≤2px 判据兜底 |
| K7 | Windows 侧载荷若被旧版 `current.txt` 指向已删目录，会“静默不可用” | 安装逻辑设计 | 🟡 `common.sh` 先检查目录存在且含 `MANIFEST.sha256`，否则 `ENV_NOT_INSTALLED` |
| K8 | 中文路径（`/mnt/c/用户/...`）在参数传递时可能被转码 | 未实测 | 🔴 约定所有路径用 ASCII，必要时用 Windows 短路径 |
| K9 | 锁屏/切用户后 UIA 与截图可能“成功但内容是安全桌面” | 机制已实现并实测正常桌面返回 `secured:false`；锁屏态未测 | 🟡 `wdiag.desktop` 用 `OpenInputDesktop`+`GetUserObjectInformation`，S3 真实锁屏断言待 M3 |
| K10 | 无 `DISPLAY` 的 WSL 里跑任何 GUI 程序都会失败（不是本仓库问题，但要知道） | `docs/02` §1 | 🟢 设计上不跑 WSL GUI，全部交给 Windows 侧 |
| K11 | `winps -f` 收的是 **WSL 路径**，传 `C:\…` 会得到 `cat: no such file` | M1 的 B1 | 🟢 `wa_run` 只传 Linux 路径；`-Core` 才用 Windows 路径 |
| K12 | `DllImport` 不写 `CharSet.Unicode` 时，`*W` API 的 UTF-16 缓冲被按 ANSI 读 → 标题乱码、类名只剩一个字母 | M1 的 B2 | 🟢 所有 `*W` 导入显式 `CharSet = CharSet.Unicode`（D16） |
| K13 | 经 `winps -f` 执行的脚本 `$PSScriptRoot` 是 Windows 临时目录，不是载荷目录 | M1 的 B1/B3 排查 | 🟢 载荷一律显式收 `-Core`（D15） |
| K14 | `EnumWindows` 在本机返回 474 个顶层窗口，逐个构造信息（含 `Get-Process`）会把 `wwin` 拖到 12 s | M1 的 B4 | 🟢 先 `IsWindowVisible` + 标题非空预筛，再构造信息 → 743 ms |
| K15 | `Out-Plan \| Out-Null` 把 dry-run 的 JSON 整块吞掉，命令"成功"但输出全 null | M2 的 B1 | 🟢 输出 JSON 的函数一律不接管道；dry-run 分支直接 `Out-Json` |
| K16 | 事件处理器（Loaded/TextChanged/KeyDown）里访问外层局部变量全是 `$null` | M2 的 B3 | 🟢 跨回调状态一律 `$script:xxx`（D20）；测试窗已改 |
| K17 | WinForms `TextBox` 既无 ValuePattern 也无 TextPattern，`wuia --value` 会报 `ENV_NO_VALUE_PATTERN` | M2 的 B4 | 🟡 判据优先选 WPF 控件；遇到 WinForms 改走「Ctrl+A Ctrl+C + wclip get」兜底 |
| K18 | 陈旧测试窗实例共用同一 JSON 路径，读到空/旧数据 | M2 的 B5 | 🟢 `testwin-stop.sh` 按 JSON 里的 pid 精确杀，起窗前先 stop |
