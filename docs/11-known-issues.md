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
| K49 | `wuia --find-name .` 会**漏掉名字为空的元素**（Edit/ComboBox/容器），拿它当「全部元素」计数会少算 | M9 T16：`ops/map` 的 `actionable` 数与 `--find-name .` 口径差 4，改用 `--find-type .` 后差 0 | 🟢 数元素用 `--find-type .`；`--find-name` 只用于找有名字的控件（docs/20 E15-4 判据已按此修正） |
| K50 | `[Drawing.Image]::FromFile()` 会**锁住图片文件**，随后 `Save()` 到同目录报「GDI+ 中发生一般性错误」，看起来像权限问题 | M9 T16：`win/wannotate.ps1` 首版给截图画像时 Save 必失败 | 🟢 用 `[IO.File]::ReadAllBytes` + `MemoryStream` 读图；写新文件再 `Move-Item -Force` 覆盖 |
| K51 | `SW_RESTORE(9)` 不只是「显示窗口」：对**最大化**窗口它会把窗口打回窗口化，之后的坐标全部失效 | 4f 会话 F3：两次 `ops/hover-menu` 失败后窗口自己从最大化变回窗口化，只能 `wwin set --state max` 抢救 | 🟢 v1.2 起 `Set-WaForeground` 只在 `IsIconic`（最小化）时 RESTORE，其余走 `SW_SHOWNOACTIVATE(4)` + 激活重试链（K43 的延伸） |
| K52 | WPF 子窗的 `Owner` 必须在父窗 `Show()` **之后**赋值，否则 Owner 句柄是 0，「子对话框」退化成两个无关顶层窗，窗口族判定永远失败 | M9 T13：`dialogwin.ps1` 首版先设 Owner 再 Show，probe 实测 `owner(a)=0` | 🟢 先 `$main.Show()` 再 `$child.Owner = $main`；真实应用里父子关系由系统维护，不受影响 |
| K53 | WPF 的 `Left/Top/Width/Height` 是 **DIP**，在 150% 缩放下与物理像素差 1.5 倍：夹具写 `900,420` 实际落在 `1350,630`，按 DIP 算点击坐标必偏 | M9 T13：CHILD-BTN 夹具 DIP 中心与实测物理中心差 225 px | 🟢 一切点击坐标从 `wuia --find-*` 的 `rect`（已经是物理像素）或 `wwin state` 取，**不要**拿夹具/代码里的 DIP 当坐标 |
| K54 | `grep -c pattern file || echo 0` 会输出**两行**（`0` 与 `0`），下一步整数比较报 `integer expression expected` 并让用例悄悄变成 FAIL | M9 T13：`tests/check-m13.sh` 的事件计数断言 | 🟢 写 `grep -c ... || true`，或用 `$(grep -c ...)` 并接受非零退出 |
| K55 | 用 heredoc/模板串一次性写长 bash 或 PowerShell 脚本，容易被 `${...}` 插值、引号配对、多模板拼接打断（报 `Expected ',', got '--'` 之类），而且错误位置在生成端而非目标文件 | M9 T16/T17：写 `ops/map`、`wannotate.ps1`、m11 扩展块时反复触发 | 🟢 拆成多段 `write` 到 `/tmp/x1.txt` 再 `cat` 拼；需要字面 `${` 时用 `§{` 占位后 `sed` 回填 |
| K56 | `tools.edit` 的 `old_string` 必须逐字符匹配（**缩进也是**）：`--verify` 行是 2 空格缩进，写成 3 空格就静默不命中，改完 grep 才发现只有一半改动落地 | M9 T17：给 `ops/click-element` 加头部说明时连续两次失手 | 🟢 编辑失败先 `sed -n 'a,bp'` 看真实文本；批量改动改用 python 脚本 + `assert anchor in s` |
| K57 | `winput type` 用「固定 sleep 后恢复剪贴板」会与目标抢占：目标泵慢时 `Ctrl+V` 在**恢复之后**才被翻译，于是粘出的是旧剪贴板内容，而 JSON 仍 `ok:true` | M10 回归：m9 L5 偶发 `got='aok'`（期望 41 字节敌意文本），同批 L6 `--text-b64` 却 PASS | 🟢 v1.2 起改成「先快照焦点值 → 轮询焦点值变化（≤900 ms）→ 再恢复剪贴板」，JSON 带 `pasteSettled`/`settleMs`；m9 增 L5b 断言 |
| K58 | 夹具窗口会**泄漏**：`*-stop.sh` 只认自己 pid 文件里的 pid，套件被中断或两次运行重叠时旧窗口留在桌面上，与后续夹具坐标重合（症状是「多一个字符」「读回旧文本」） | M10 回归：桌面上一次积了 6 个 `wa-uia` + 3 个 `wa-dialog*`，全压在 `890,335`；m8/m9 组合跑必现怪现象，单跑全绿 | 🟢 新增 `tests/helpers/kill-fixtures.sh`（按标题 `^wa-` 扫顶层窗、只结束夹具 pid），四个 `*-start.sh` 启动前先跑它；回归后核对 `wa-*` 窗口数为 0 |
| K59 | 组合键 `key ctrl+a` 在目标忙时可能退化成**纯 `a`**：`Ctrl` 抬起太早，目标稍后才处理 `WM_KEYDOWN a`，`TranslateMessage` 取到的已是没有 Ctrl 的键盘状态 | M10 回归：m8 K1 `text='aa'`、m9 L5 `got='a'+期望文本`，都是「凭空多一个 a」 | 🟢 `key` 动作改为「修饰键先按下 → ≥60 ms 驻留（JSON 带 `dwellMs`）→ 释放普通键 → 再释放修饰键」；修饰键集合 `0x11/0x12/0x10/0x5B/0x5C` |
| K60 | 用 `ctrl+a`/`ctrl+c` 回读文本框会把**两次输入**注进正被测试的输入路径，自己就是噪声源（配 K59 就是「多一个字符」） | M10 回归：m8/m9 的 `read_edit` 全走剪贴板 | 🟢 回读与清空改走 UIA：`wuia --find-type Edit --get-value` / `--set-value ""`（m8/m9 已改） |
| K61 | `kill-fixtures.sh` 会**误杀本套件刚启动的夹具**，且 pid 文件里的 pid 是 `winps` 的启动器而不是拥有窗口的 WPF 宿主；另在 WSL 里 `kill -0 <Windows pid>` 永远失败，用它判活等于把所有在跑的夹具都当垃圾 | 全表回归：m11 只有 menutwin 的四条 PASS、其余 15 条全 `EXEC_UIA`；m13 的 testwin 用例 `state=hidden` + `ENV_NOT_FOREGROUND`（夹具已被第二个夹具的清扫杀掉了） | 🟢 夹具 `*-start.sh` 改为把**夹具 JSON 里的 `pid`**写进 `$STATE_DIR/<name>.pid`（并给 `dialogwin.ps1` 补 `pid` 字段）；`kill-fixtures.sh` 只清扫「无近期 pid 文件（30 分钟内）」的 `wa-*` 窗口，判活改用 pid 文件时间而不是 `kill -0`；`killed` 计数改 `awk -F,` |
| K62 | `tools.edit` 重写文件会**剥掉 UTF-8 BOM**：含中文的 `.ps1` 被 PowerShell 5.1 按 ANSI(936) 读，字符截断成乱码并报 `表达式或语句中包含意外的标记"2'"`，而文件看起来「刚改过」 | M16 T20：`tests/helpers/deepwin.ps1` 用 `edit` 改完再启动，夹具报 `第 63 行 `$tb1.Text = '第一条文?``（丢 BOM），首版 `add-type` 式写文件则正常 | 🟢 任何「含非 ASCII 的 .ps1」在 `edit`/`write` 之后补 BOM（`python3` 检查 `b'\xef\xbb\xbf'` 再前置；K39 的延伸） |
| K63 | `Start-Process -ArgumentList 'a','b'` 的额外参数必须**写在数组里面**：拼在数组外的 `-Lazy -LazyMs 1500` 会被当成 `Start-Process` 自己的参数，进程根本没起 | M16 T20：`deepwin-start.sh` 首版把 `$xtra` 接在 `-ArgumentList '...'` 之后，返回 `找不到与参数名称"Lazy"匹配的参数`，桌面无窗口、json 不出现，而启动命令 rc=0 | 🟢 `xtra=",'-Lazy','-LazyMs','${LAZYMS}'"` 以逗号起始紧贴前一项拼进数组；空值不带该项 |
| K64 | 「树的深度档位」只有一个开关（find 条件）时，**point-with-target 会拿到 3 层树**：rect-hit 永远只在 Window/Pane 里找，命中恒为 null，而 `--point-mode uia` 又能正常返回——看起来像「几何命中功能坏了」 | M17 T21：`--point 770,689 --point-mode rect` 报 `ENV_NO_HIT scanned=6 depthUsed=3`；同一坐标 `--depth 28` 立刻命中 | 🟢 `win/wuia.ps1` 引入 `$pointModeWanted` 并入 `$findMode`（点探测也走 find 档深度/加深），并且 needMore 判据改为「候选 rect 是否包含该点」而不是「有没有任意匹配节点」 |
| K65 | Chromium 的 a11y 树**保留滚动出视口的节点**，它们带着窗口外的 rect（用户 Edge 实测 `y=-24512`）；按这些坐标点击会点到窗口外、别的程序上，而 JSON 仍可能 `ok:true` | M17 T21 live：`winput click --click-text '.' --expect-hwnd <Edge>` 选到第 0 行（`y=-24512`），一开始会真的向屏幕外注入 | 🟢 `bin/winput` 解析文本行后先比对目标窗口矩形，行中心在窗口外 → rc=3 `ENV_TEXT_OFFSCREEN`（JSON 带 point/window，提示用 `--text-index` 选可见行）；实测同一命令改后 rc=3，不再注入 |
| K66 | jq 的 `//` 把 `false` 也当「空」：`jq -r ".ok // empty"` 对 `{"ok":false}` 输出空串，用 `[ "$(…)" = "false" ]` 断言的测试会**假失败**（幂等重跑仍失败，看起来像功能坏了） | M19 T23：`tests/check-m19.sh` 首轮 9 条失败，实际 JSON 全部符合判据（`pasteSettled:false`、`forced:true` 都在），根因是 `num()` 助手用了 `// empty`，把每个 `false` 读成空串 | 🟢 断言助手改为 `jq -r ".$2"`（缺字段得 "null"），或 `if .$k == null then empty else .$k end`；修后 m19 10/0 |
