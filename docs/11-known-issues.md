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
| K19 | Linux 环境变量不会传给 WSL 启动的 Windows 进程，靠 env 传测试开关永远无效 | M3：`WA_TESTING=1` 在 payload 里读到空字符串 | 🟢 改走 Windows 可见的文件钩子 `tmp/force-desktop.txt`（D21/SG-0002） |
| K20 | `winput` 的 guard 拒绝路径曾绕过审计（直接 `exit`，EXIT trap 未设 result），S5 会少数一行 | M3 自查：第一条审计只记了 payload 路径 | 🟢 所有早退路径先 `WA_AUDIT_RESULT=...`，EXIT trap 统一落账（D22） |
| K21 | UAC/锁屏的拒绝码依赖输入桌面名文案（`Winlogon`/`Secure`），Windows 大版本可能改文案 | 机制实测 `Default` 正常；改名后映射会退回 `SESSION_LOCKED`（仍然是拒绝，但码不准） | 🟡 保守默认「拒绝」而非「放行」；升级 Windows 后重跑 `tests/check-m3.sh` |
| K22 | 审计与 grant 都存放在同用户可写的 `~/.dsh/win-admin/`，同用户进程可删改/伪造 | D23 的设计限制（签名只防误改，key 同用户可读） | 🔴 真隔离需独立账户或系统服务（G4），本轮明确不做 |
| K23 | 全屏像素比对不可用：桌面有动画元素，两张相隔 1s 的截图差 8185 px | M3：S1 初版全屏 diff 失败 | 🟢 `pixdiff.py --rect` 只比动作会影响的区域，S1 diff=0 |
| K24 | 显示配置会变（M2 时 2560×1600，M3 时 1920×1080，且出现两块活动面板），任何写死坐标的脚本都会点错 | M3 环境快照：内屏 CSW1656 + 外接 TCL03D4 | 🟡 一切坐标从 `wdiag.screen` / `wwin info` 动态取；多屏负坐标场景仍未覆盖（Q3） |
| K25 | `jq --argjson` 不接受 `0x` 十六进制：hwnd 原样传入直接 `invalid JSON text` | M4：ops 首次跑通即报 | 🟢 每个 ops 在解析后 `H=$((H))` 先转十进制 |
| K26 | `H="$(op_resolve_hwnd ...)" \|\| exit $?` 会把失败 JSON 吞进变量，调用方只看到空 `code` | M4 N5 首跑：rc=3 但 code 为空 | 🟢 捕获后显式 `printf` 再按 rc 退出（ops/find-and-click、ops/fill） |
| K27 | PowerShell 多行 `param()` 每一行（最后一个除外）必须以逗号结尾，否则 `参数列表缺少右括号` | M4：waopen.ps1 首版第 2 行报错 | 🟢 单行 param 或逐行加逗号 |
| K28 | 改了 `win/*.ps1` 而没重跑 bootstrap，Windows 侧仍是旧载荷，症状是「没输出/行为没变」 | M4：多次 `no JSON from payload` | 🟢 改载荷后必须 `bash scripts/bootstrap.sh --force`；`wdiag` 报 payload 版本 |
| K29 | Win11 记事本单进程多标签：再开一个文件是同一 hwnd 增 Tab，标题会变（`a.txt` → `*b.txt`），按 pid 找新窗口会失败 | M4 C8：hwnd 4919256 标题从 `c8-a.txt - Notepad` 变 `*c8-e2e.txt - Notepad` | 🟡 按标题匹配；把窗口当可复用容器（D25 相关） |
| K30 | 记事本「是否保存」模态框是**子窗口**：UIA 树里可见（depth 4–5 的 Button），`wwin list` 看不到 | M4：`ops/find-and-click --name '^不保存$'` 成功关闭；`wwin list` 无该窗口 | 🟢 等对话框用 `ops/wait-for --uia-name`，点按钮走同 hwnd（D25） |
| K31 | alt+F4 用合成按键只弹出保存提示，不等于关闭；行为随应用而异 | M4 实测 | 🟢 关闭统一走 `wwin close`（PostMessage WM_CLOSE），存不存交给应用 |
| K32 | `jq '.desktop.secured // true'` 在 `secured=false` 时也返回 `true`：jq 的 `//` 把 `false` 当空值 | M5：`tests/check-m5.sh` 明明解锁却连两次 SKIP E8 | 🟢 布尔字段直接读，缺失才 fail-closed 当 true |
| K33 | `tests/check-m4.sh` 的 N5（找不到控件）原先放在开窗之前，实际拿到的是 `ENV_NO_WINDOW` | M4 首次跑：N5 假阴性 | 🟢 阴性用例同样有前置条件；N5 移到 C8-1 之后 |
| K34 | 测试套件可能把自己的授权令牌留在 `~/.dsh/win-admin/grant.json`（清理逻辑依赖 `HAD_GRANT` 分支，备份缺失时 `mv` 失败就静默留下） | M5 收尾：发现一个 30 分钟有效的残留令牌（note 指向 check-m2） | 🟢 cleanup 改成「有备份就还原，没备份就删」，并在 `check-m5` 加 E5 残留断言 |
| K35 | `tests/check-m4.sh` 的 N1 用例把授权令牌暂存在 `$GB`（m4-bak），而恢复条件写成 `HAD_GRANT=1`：套件**自己**签发令牌时 `HAD_GRANT=0`，N1 之后令牌就再也不回来 → 全后续用例 rc=4 | 补上 K34 清理后 m4 首次独立运行 9 项 FAIL（`N2 rc=4 GUARD_NO_GRANT`）；此前一直靠 m3 遗留的令牌侥幸通过 | 🟢 N1 改用独立暂存路径 `grant.json.m4-n1`，无条件还原；阴性用例不得复用 cleanup 的备份槽 |
| K36 | 窗口最小化后 UIA 的 `BoundingRectangle` 为 null（rect 变成 -32000 之类），「最小化」与「几何变了」在 UIA 层不可区分 | M8：m1 的 C3 在用户桌面留下的最小化记事本上失败 | 🟢 m1 C3 对最小化目标改判 SKIP；判最大化必须用 `GetWindowPlacement().showCmd`（K43） |
| K37 | `type --text '…'` 里含半角单引号时，shell 抢先截断命令，`winput` 静默失败（无 JSON 输出），看起来像「点了没反应」 | 真实投稿会话：标题 `ARC'26` 输入 6 次全空 | 🟢 v1.1 提供 `--stdin` / `--text-b64` / `--text-file` 彻底免引号；空文本现在 rc=2 `ARG_EMPTY_TEXT` |
| K38 | WPF `TextBlock` 不暴露 TextPattern，`--get-text` 会直接 `ENV_NO_PATTERN` | M8：m10 首次对 LBL-TITLE 取文本失败 | 🟢 `--get-text` 回落 `Name`（输出 `via:"name"`），调用方据此知道来源 |
| K39 | UTF-8 **无 BOM** 的 `.ps1` 被 PowerShell 5.1 按 ANSI 读，中文字面量变乱码（`删除` → `鍒犻櫎`），危险名正则/UIA 名字全对不上 | M8：m11 的危险名用例明明按钮叫「删除」却匹配不到 | 🟢 含中文的 `.ps1` 必须 UTF-8 with BOM（`tests/helpers/uiawnd.ps1` 已加）；纯 ASCII 脚本不受影响 |
| K40 | `wuia` 的 find 分支缺 `-not $Action` 条件：只要带了 find 参数，`--invoke` 等动作从未执行，命令却 exit 0 返回节点 | M8：m10 的 A1 第一次跑，计数按钮点了不涨 | 🟢 分支条件补全；动作类用例一律断言**动作后的回读状态**而非退出码 |
| K41 | 用 heredoc/编辑器写测试脚本时混进 NUL 字节，文件被判定为二进制，后续读取/编辑全部失败 | M8：`tests/check-m10.sh` 里 `TXT='A1 中文 …'` 行尾带了一个 NUL | 🟢 写脚本后 `python3 -c "open(p,'rb').read().count(b'\x00')"` 验一遍；已清除 |
| K42 | UIA 的 TogglePattern 不触发 WPF `CheckBox.Click` 事件，夹具按 Click 记日志会「动作成功但日志为空」 | M8：m10 的 A4 首次跑，ToggleState 变了但事件文件没写 | 🟢 WPF 夹具用 `Add_Checked`/`Add_Unchecked` 记录；断言同时看 ToggleState 与日志 |
| K43 | 最大化窗口的 `GetWindowRect` 返回 `-11,-11,2582,1622`（越界边框），与屏幕尺寸不等，**几何判不出是否最大化** | M8：m6 的 N1 最初用 rect 比较，「最大化」被判定失败 | 🟢 判据固定为 `GetWindowPlacement().showCmd == 3`；`wwin set` 里「先还原再缩放」也是为此 |
| K44 | 夹具停掉后 `uiawnd.json` 里的 hwnd 变成陈旧值，`wwin info` / `wshot --hwnd` 直接 `ENV_NO_WINDOW`，容易被误读成「截图坏了」 | M8：m12 首次跑 `--hwnd` 用例 | 🟢 验 `--hwnd` 前先 `tests/helpers/uiawnd-start.sh` 并重新读 json 里的 hwnd |
| K45 | `git ls-files` 默认把非 ASCII 路径输出成 C 风格引号串（`"missions/…/s5-\346\267…xlsx"`），`tar` 直接 `Cannot stat`，发布包静默少文件 | M8 T10：`build-release.sh` 报两条 `Cannot stat`，tar 仍产出归档（漏了 missions 里两个 .xlsx） | 🟢 改 `git -c core.quotepath=false ls-files -z` + `tar --null -T`；发布前核对文件数 |
| K46 | Win11 记事本单实例多标签的延伸：用户已有记事本窗口时，`notepad <file>` 是在**该窗口里开一个标签页**，`WM_CLOSE` 只关标签页、共享窗口仍在 → 「close 后 hwnd 消失」是错误判据 | M8：m4 的 C8-6 与 E8 三轮全判 `close:window-still-open`，但文件内容其实已保存正确 | 🟢 断言改成「窗口标题里不再含我们的前缀」（`tests/helpers/e2e.sh`、`tests/check-m4.sh`）；测试用独立前缀区分 |
| K47 | 两个验收套件**并行**跑会互相污染：`winps-*.ps1` 临时文件成了对方的「新残留」（E5 FAIL），且 m9 出现过一次 `FAIL=1`（单独复跑 7/0 全绿） | M8 收尾回归：全表后台跑的同时手动插了一次 `check-m1.sh`，当场 E5 报 `new residue: winps-1278074.ps1` | 🟢 套件**串行**跑；跑套件期间不要在同一个 Windows 临时目录上做别的操作；报告里附「单独复跑」结果 |
| K48 | `check-m1.sh` 的 `skip` 计数包含 14 条「not M1」占位（其余里程碑的判据行），`skip=15` ≠ 15 项被跳过 | M8：报告一度写成「m1 16/0 + 1 SKIP（C3）」，实际输出是 `pass=16 fail=0 skip=15` | 🟢 文档口径写全：`m1 16/0（skip=15：C3 最小化窗口 + 14 条非本里程碑占位）` |
