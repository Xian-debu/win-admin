# 06 · 决策记录（D 系列）

> 格式：**决策 / 依据 / 备选与为何否 / 何时该推翻**。
> 推翻任何一条都要单独提交，并在这里加 `D-N 的推翻说明`，不许悄悄改。

---

## D1 · 不采纳网上那个"管理员插件"

- **决策**：不装 `@local/dsh-admin-mode`，只借鉴其授权 UX。
- **依据**：`docs/03` §2（admin 档 == 内置 danger-full-access，零增益）、§3（cua 需 Windows 侧 Electron，本机无 DISPLAY）、§4（ESC 假急停）。
- **备选**：装上去看看。**否**：装它要改 profile `package.json` + 覆盖权限预设表（R2），
  为一个零增益的东西引入配置漂移，不划算。
- **该推翻时**：DSH 官方推出 Windows 侧官方电脑操作能力，且我们在 Windows 装了桌面端。

## D2 · 不做第二套 Windows 侧 Electron DSH

- **决策**：DSH 继续跑在 WSL2，Windows 侧只放"无状态脚本"。
- **依据**：用户现有 DSH + 全部技能/记忆都在 WSL 侧；另起一套 = 会话割裂、要重装环境、
  历史记录分裂。且 `cua-driver` 的 Windows 包需要 Electron 主机，等于把整个 agent 搬到 Windows。
- **备选**：Windows 侧装 Electron 桌面端，走官方 computer use。**否（暂时）**：迁移成本远大于自建原语的成本，
  且官方包仍标 experimental。
- **该推翻时**：官方 Windows 桌面端成熟、且需要高频桌面操作（>100 次/天）时才划算。

## D3 · Windows 侧只允许无状态、可删除的落地物

- **决策**：Windows 侧产物只能落 `C:\Users\Public\win-admin\`（截图、ps1、日志），不含常驻服务、不装驱动。
- **依据**：`AGENTS.md` §1；用户随时可以"把那个目录删了"就回到干净状态。
- **代价**：每次调用 ~300ms 启动开销（`docs/05` §2 已论证可接受）。
- **该推翻时**：M3 急停热键需要 `RegisterHotKey`（那时单独走 G4，且进程独立可杀）。

## D4 · 唯一坐标 = 物理像素，所有进程 per-monitor v2 DPI aware

- **决策**：对外 API 只暴露物理像素；每个原语启动时声明 DPI 感知。
- **依据**：2560×1600 物理 / 1707×1067 逻辑（150%），混用偏移 1.5×（`docs/02` §2）。
- **备选**：用逻辑像素。**否**：逻辑像素随缩放设置改变，用户的显示器设置一改全崩；
  物理像素是显卡层面的稳定量。
- **验证方式**：M1 的 `wdiag` 必须回显 `scale`，M2 用"截图上画十字 → 点它 → 复截确认"闭环校准。

## D5 · UIA 语义定位优先，坐标点击兜底

- **决策**：能拿到控件（名称/类型/InvokePattern）就语义点击；拿不到才用 `wuia` 给的 rect 中心点坐标点。
- **依据**：坐标点击对 UI 改版、DPI、动画零容忍；语义定位天然抗这些。L4 视觉语义悬于 Q1（`docs/04` §4），
  不能把成败押在未验证的通道上。
- **代价**：UIA 树对某些自绘 UI（游戏、Chromium 的部分控件）不可靠 → 必须有兜底，否则能力残缺。

## D6 · 授权用"会话级令牌"，不用"全局开关"

- **决策**：`grant.json` 带 `expires`（默认 30 分钟）+ `scope` + 用户原话摘录；删除即撤销。
- **依据**：本会话已是 `danger-full-access`，系统层没有旋钮可用（`docs/02` §5）；
  真正有价值的边界是"时间的、范围的、可撤销的"。
- **备选**：每次点击都问用户。**否**：一次"导出表格"要点十几下，用户会累到永久放行——
  那才是真正的危险。窗口期 + 事后审计是工程上唯一可持续的方案。
- **该推翻时**：出现用户"离开电脑但令牌未过期"的事故 → 加 `idle` 检测自动失效。

## D7 · 急停双通道：`pause.flag`（软，M3 前就有）+ F12 热键（硬，M3，需 G4/G3）

- **决策**：所有输入原语第一件事检查 `pause.flag`；热键作为 M3 的增量。
- **依据**：软通道零依赖、零常驻、用户敲一行就能停；热键要常驻进程（G4）且可能冲突（Q4）。
- **不接受**："ESC 取消"这种只关提示层的东西（`docs/03` §4 的反面教材）。

## D8 · 审计一行一动作，只追加

- **决策**：`~/.dsh/win-admin/audit/YYYY-MM.jsonl`，输入类动作必写（含拒绝），只读类折叠。
- **依据**：事后复盘是唯一能判断"agent 到底做了什么"的证据；
  `.jsonl` 可 `jq`、可增量、不会因为并发写坏整份文件。
- **代价**：几十毫秒 IO。可忽略。

## D9 · 永不自动点 UAC / 提权

- **决策**：检测到 UAC 窗口（`Consent.exe` / 安全桌面）→ 立即报错退出，不尝试任何按键。
- **依据**：红线 1。安全桌面是内核级隔离，任何"绕过"都是提权漏洞利用行为。
- **该推翻时**：永不。

## D10 · UTF-8 强制 + 复杂脚本走文件

- **决策**：所有 PS 脚本首行 `[Console]::OutputEncoding=UTF8`；含中文/嵌套引号的脚本落盘后 `winps -f`。
- **依据**：PS 5.1 默认 GBK，`winps` 只 iconv UTF-16 流，中文经管道必乱（`docs/02` §4.2 实测）。
- **规则**：bash 里出现的 `powershell.exe -Command '...'` 只允许纯 ASCII 单行。

## D11 · 视觉通道先验证再依赖（Q1）——**已验证通过**

- **决策**：M1 第一步就给用户发一张截图，让他确认"我看得见"；确认前不设计任何"靠图像判断成败"的流程。
- **依据**：当前会话模型是否收图未验证。若不支持，L4 只剩"给人看的证据"作用，`wuia` 必须顶上来。
- **影响**：这条决定 M1 验收的两个分支（见 `docs/07` C1 的两个子项）。
- **验证结果（2026-10-20 23:47）**：✅ 支持。读回 2560×1600 截图后能读出标签页标题、
  地址栏 URL、模型徽标等具体文字，证据见 `inventory/raw/2026-10-20-q1-vision.txt`。
  ⇒ L4 语义通道成立；但 D5 不变（UIA 仍首选），且 C3 的 ≤2px 对齐必须程序判定。

## D12 · Windows Python 只用 Pillow；UIA 与输入一律 PowerShell

- **决策**：不 `pip install` pywin32/comtypes/uiautomation/pyautogui/numpy。
- **依据**：这些包在 Windows 侧全缺，装要过 G1；而 PowerShell 内置 `UIAutomationClient` +
  `Add-Type` P/Invoke 已覆盖 UIA 与 `SendInput`。少一层 pip 依赖 = 少一类环境漂移。
- **代价**：PS 里写 C# 片段略啰嗦；用 `winps -f` 落盘解决可读性问题。
- **该推翻时**：需要复杂图像算法（模板匹配外）时，装 numpy/opencv，走 G1 单独评估。

## D13 · 脚本规模阈值与产物路径

- **决策**：≤10 行且纯 ASCII → `winps -c` 内联；否则落 `/mnt/c/Users/Public/win-admin/ps1/` 再 `winps -f`。
- **依据**：多层引号是 bash→PS 最常见的坏源（`docs/04` §5 "中文路径"坑）。
- **清理**：该目录保留最近 50 个脚本，其余由 `wdiag --clean` 清（M2）。

## D14 · M1 通过前，仓库里不许出现输入注入代码

- **决策**：M1（只读）验收通过前，`bin/` 不允许有 `winput`，也不允许 `SendInput/keybd_event/mouse_event` 字样。
- **依据**：`AGENTS.md` §4。先证明"看得见、认得准"，再谈"点得中"；
  否则必然演变成"先能点，安全之后补"，然后永远补不上。
- **执行**：`tests/` 有一条 `grep -r 'SendInput\|mouse_event\|keybd_event' bin/ ops/` 必须为空的守卫测试。

## D15 · 载荷一律显式传 `-Core`，不依赖 `$PSScriptRoot`

- **决策**：`bin/*` 调载荷时同时传 `-f <WSL 路径>` 与 `-Core <Windows 绝对路径>`。
- **依据**：`winps -f` 把脚本 `cat` 进 Windows 临时目录再 `-File` 执行，`$PSScriptRoot` 指向 temp，
  按它找 `lib/wa-core.ps1` 必然失败（M1 的 B1/B3 排查中实测）。
- **代价**：多一个参数；**收益**：脚本放哪都能跑，不被 temp 路径绑架。

## D16 · 所有 `*W` Win32 导入必须声明 `CharSet = CharSet.Unicode`

- **决策**：`GetWindowTextW`/`GetClassNameW`/`GetUserObjectInformation` 等一律带 `CharSet.Unicode`。
- **依据**：默认 `CharSet.Ansi` 时 .NET 按 ANSI 封送 `StringBuilder`，UTF-16 内容被截成单字母
  （M1 实测：标题乱码、类名 `C`）。修复后标题完整、类名 `Chrome_WidgetWin_1`。
- **执行**：`docs/08` 原语模板里写死这条；`check-release.sh` 不做静态检查（易误报），靠 C2/C3 回归守。

## D17 · 残留检测比对"跑前/跑后"，不比对"是否存在"

- **决策**：E5 改为快照 `tmp/` 跑前跑后差集，只有新增才算泄漏。
- **依据**：早期 `-k` 留下的旧 `winps-*.ps1` 让 E5 假红；把"历史脏物"和"本次泄漏"混在一起，
  会让测试失去意义（也叫"测试自己制造失败"）。

## D18 · 验收一律使用仓库自带的 WPF 测试窗，绝不在用户窗口里做实验

- **决策**：`tests/helpers/testwin.ps1` 是仓库自带的 WPF 窗口（一个 TextBox + 一个 CLICK-TARGET 按钮），输入类验收全部打在它身上；用户自己的记事本/浏览器只读不写。
- **依据**：M1 期间本机记事本里放着用户正在编辑的文本（hwnd 0x108c6，pid 27396）；一次"顺手 type 一下"就能毁掉用户的工作。验收需要可控、可复现、可反复破坏的对象，用户窗口三条都不满足。
- **执行**：测试窗自己落盘三类证据——输入文本（testwin-text.txt）、按键（testwin-keys.txt）、点击计数（testwin-clicks.txt），使 C4/C5 的判据不完全依赖 agent 自己的返回值。

## D19 · C5 的回读判据优先用 UIA ValuePattern，其次 TextPattern

- **决策**：`wuia --value` 先找 ValuePattern，没有则退到 TextPattern（`DocumentRange.GetText`）。
- **依据**：WinForms 的 TextBox 在本机实测**两种模式都没有**（只有 MSAA Name），拿它当判据会误判"输入失败"；WPF TextBox 有 ValuePattern，回读 23 字符完全一致。判据必须建立在真实可用的模式上。
- **执行**：`wuia --value` 的返回带 `via` 字段（value/text）；两种都没有时报 `ENV_NO_VALUE_PATTERN`（exit 3），不返回空串假装成功。

## D20 · WPF 事件处理器里只用 `$script:` 变量

- **决策**：事件脚本块（`Add_Loaded` / `Add_TextChanged` / `Add_KeyDown`）里访问的跨回调状态，一律 `$script:xxx`。
- **依据**：M2 实测，处理器 scriptblock 看不到外层函数的局部变量——`$win` / `$h` / `$timer` 在回调里全是 `$null`，表现为"窗口起来了但 JSON 是空的""计数器永远是 1"。此坑排查了三轮。
- **执行**：`tests/helpers/testwin.ps1` 已全部改为 `$script:`；新写任何带 UI 事件的脚本沿用。

## D21 · 锁屏/UAC 判据用"只能更严格"的文件钩子

- **决策**：`Get-WaDesktopInfo` 在真实检测之前先看 `C:/Users/Public/win-admin/tmp/force-desktop.txt`；文件存在且内容不是 `Default` 时，直接视为"已锁定/安全桌面"。
- **依据**：锁屏会把我自己关在门外（无密码可解锁，红线），而自动点 UAC 是绝对红线——两者都不能真做。WSL 启动的 Windows 进程**收不到** Linux 环境变量（实测 `WA_TESTING=1` 在 payload 里读到空），所以钩子必须走 Windows 可见的文件通道。
- **安全性**：钩子只能让系统**更严格**（声明一个非 Default 桌面名），永远不会把真实锁屏/安全桌面覆盖成可用；因此它不能成为绕过手段。记录为 SG-0002。
- **执行**：仅 `tests/check-m3.sh` 使用；用完 trap 删除。

## D22 · 审计一行一动作，写失败即失败（fail closed）

- **决策**：`lib/audit.sh` 提供 `wa_audit_init` / `wa_audit_flush`；`bin/winput` 用 EXIT trap 保证**每条退出路径**都落一行。审计写失败且动作原本成功时，退出码强制为 5。
- **依据**：S5 要求"20 个动作 20 行"，任何绕过记账的 exit 都会让账本失去证据价值；M3 第一版就漏了 guard 拒绝路径。
- **限制**：账本是"事后证据"，不防删除/改写（同用户）；真正防篡改需要外部存储或独立账户，超出本轮范围（docs/11）。

## D23 · grant 令牌签名：挡事故，不挡"同用户恶意进程"

- **决策**：`sig = sha256(secret + jq -cS 规范化字段)`，secret 在 `~/.dsh/win-admin/.grantkey`（600）；`guard/check.sh` 先验签再信任任何字段，缺 key/缺 sig/不匹配一律 `GUARD_TAMPERED`（exit 4）。
- **依据**：误编辑、脚本事故、旧版无签名 grant 都会被静默接受，是真实风险；签名把这些变成显式错误。
- **不夸大**：同一 Linux 用户下的进程能读 key，所以签名**不是**权限边界。真正的隔离需要独立账户或系统服务（G4），本轮不做，写进 docs/11。

## D24 · 前台激活用"双线程 attach"，且 ops 必须先激活再点击

- **决策**：`Set-WaForeground` 在直接 `SetForegroundWindow` 失败后，own 线程同时 attach 到前台线程与目标窗口线程，然后再设置；`ops/find-and-click`、`ops/fill` 在点击前必调 `wwin focus`，失败即 `ENV_NOT_FOREGROUND`。
- **依据**：实测后台进程仅 `SetForegroundWindow` 返回 false；只 attach 前台线程仍失败；双 attach 成功（2026-10-21，fg=0x4b0fd8）。被遮挡时 `winput` 的 S7 断言会拒绝点击——**不弱化断言**，而是让 ops 负责先激活。
- **限制**：用户正在主动操作的窗口会被抢焦点；因此每条激活都写审计，且只在前置 dry-run 通过后发生。

## D25 · 模态对话框当作"子窗口"处理

- **决策**：等待对话框用 `ops/wait-for --uia-name`（轮询 UIA），不用 `wwin list`；对话框内的按钮用同 hwnd 的 UIA 定位后点击。
- **依据**：记事本"是否保存"提示在 UIA 树里是 depth 4–5 的 Text/Button，但**没有独立顶层窗口**（`wwin list` 看不到）。`WindowFromPoint` 的根仍是主窗口，所以 S7 断言依然成立。
- **限制**：不同程序对话框实现差异大（有的确实是独立顶层窗口）；两种路径都要能用，先试 UIA，再退回 wwin。

## D26 · 复合操作默认 dry-run，真实注入必须 `--yes` 且全程记审计

- **决策**：`ops/open|fill|find-and-click` 无 `--yes` 时只输出计划（含将点击的 point / 将匹配的控件），不产生任何副作用；真实动作必须 `--yes`，且先过 `op_pause_gate`，结束时写 `WA_AUDIT_RESULT`。
- **依据**：agent 的坐标推断可能错，用户需要一次"先看再点"的机会；同时给用户一个不注入也能审查动作的通道。
- **限制**：dry-run 的 point 仍可能因窗口在两步之间移动而失效——真实点击时 `winput` 会重新校验 hwnd。

## D27 · 复合操作的成功判据是"读回/落盘"，不是"动作已发出"

- **决策**：`ops/fill` 以 UIA `--value` 读回与输入逐字符相同为成功（`matches:true`），`ops/open` 以窗口出现为准，端到端以落盘字节一致为准；只报 `injected:true` 不算成功。
- **依据**：M2 已证明"发出了"与"打进去了"是两件事（IME、焦点、遮挡都可能吞掉输入）。
- **限制**：读回依赖目标控件暴露 ValuePattern/TextPattern；自定义控件取不到时要显式返回 `verify:"unavailable"` 并降级为截图核对。

---

## 待定（等用户或等验证）

| 编号 | 待定项 | 卡在哪 |
|---|---|---|
| ~~Q1~~ | ~~会话模型是否收图~~ | ✅ 已实测支持（2026-10-20，`inventory/raw/2026-10-20-q1-vision.txt`） |
| ~~Q2~~ | ~~锁屏检测方法~~ | ✅ 机制已实现并在 S3/S4 断言（钩子路径，SG-0002） |
| ~~Q4~~ | ~~F12 热键冲突~~ | ✅ 已作废：用户确认"急停就按你说的"，只做 `pause.flag` 软通道，不常驻 |
| Q3 | 多显示器坐标模型 | 2026-10-21 实测出现两块活动面板（内屏 CSW1656 + 外接 TCL03D4），但虚拟屏仍是单坐标空间 1920x1080，全部判据按 `wdiag.screen` 动态取；真正的多屏负坐标场景仍未覆盖，接管前需补测 |
| — | 是否需要"操作前征询"档位（每次点前问一句） | 用户偏好，M4 问 |
