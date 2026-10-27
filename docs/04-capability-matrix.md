# 04 · 能力矩阵（现状 / 缺口 / 归属里程碑）

> 采集依据：`docs/02-environment.md` 的实测 + `inventory/raw/` 原始输出。
> 状态标记：**✅ 实测通过** / **⚠️ 实测通过但有限制** / **🧪 待验** / **❌ 不可行** / **⛔ 不做（红线）**

## 0. 分层视角

"接管 PC"不是一种能力，是四层能力的叠加。缺任何一层，整条链路都是假的：

```
L4 视觉反馈    ← 我看见了结果，能判断成败
L3 GUI 交互    ← 我能点、能打、能等
L2 文件与数据  ← 我能读写要处理的物料
L1 命令与系统  ← 我能跑程序、查状态
```

## 1. L1 · 命令与系统（最成熟的一层）

| 能力 | 状态 | 证据 | 缺口 | 里程碑 |
|---|---|---|---|---|
| 执行任意 PowerShell | ✅ | `winps -c '...'` 返回 JSON，PS 5.1.26100.4061 | 无 | M1 |
| 执行 Windows Python | ✅ | `python.exe -c` 3.11.9 | 无 | M1 |
| 查询进程 / 窗口 / 会话 | ✅ | `Get-Process`；`(Get-Process -Id $PID).SessionId`=1 | 无 | M1 |
| 读写环境变量 / 注册表（只读） | ✅ | `HKCU:` 可枚举 | 写要过 G3 | M1 |
| 启动 / 结束进程 | ✅ | 权限充足 | 结束用户进程要过 G5 | M2 |
| 服务 / 计划任务 / 自启（写） | ⚠️ | 有权限 | **G3 门控**，非用户当次批准不做 | — |
| 提权执行（UAC） | ⛔ | 安全桌面 | 不做，见红线 1 | — |

## 2. L2 · 文件与数据

| 能力 | 状态 | 证据 | 缺口 | 里程碑 |
|---|---|---|---|---|
| WSL 内文件读写 | ✅ | 原生 | 无 | M0 |
| `/mnt/c` 读写 | ✅ | 已挂载，可写 `C:\Users\Public\` | 个人目录受红线 2 约束 | M0 |
| 跨侧路径/编码转换 | ✅ | UTF-8 BOM + `iconv` 已验证 | 中文路径要小心（见 §5 坑） | M1 |
| 大文件搬运 | ⚠️ | 双向都通 | 速度受 9P 影响，>1GB 走 G2 | — |
| Office 文档内容处理 | 🧪 | 未测（`python-docx` 等未装） | 需要时装 + G1 | M4 |

## 3. L3 · GUI 交互（本项目的主战场）

| 能力 | 状态 | 证据 | 缺口 | 里程碑 |
|---|---|---|---|---|
| 枚举窗口（含标题/坐标/进程） | ✅ | `wwin list` 14 窗口 712–743 ms，8 个中文标题完整（K1 已修） | — | M1 ✅ 2026-10-21 |
| 读取控件树（语义定位） | ✅ | `wuia --title Notepad --depth 2` 9 节点 0.5 s；rect 与 `GetWindowRect` 偏差 0,0,0,0 | 默认 `--depth 3` + 400 节点上限防刷屏 | M1 ✅ 2026-10-21 |
| 窗口激活 / 最大化 / 移动 | ✅ | v1.0：`winput --focus` 10/10；**v1.1**：`wwin state`/`wwin set` 用 `GetWindowPlacement` 判最大化、`SetWindowPos` 移动缩放、回读 `before/after`，m6 N1–N10 全绿 | 系统前台锁仍可能拒绝（已降级为显式报错） | M2 ✅ / M8 ✅ 2026-10-24 |
| 鼠标移动 / 单击 / 双击 | ✅ | 10/10 次点击全部命中：命令 ok 10/10 且窗口侧计数器 10/10；`SetCursorPos` 后回读坐标一致 | — | M2 ✅ 2026-10-21 |
| 鼠标拖拽 | ✅ | 拖 (300,150) px，窗口 rect 位移恰为 (300,150)，误差 (0,0) px；步进 `SetCursorPos`+15 ms 间隔，起终点都校验根窗口 | — | M2 ✅ 2026-10-21 |
| 键盘单键 / 组合键 | ✅ | `winput key ctrl+v` 路径已在 C5 中实测生效；`Get-Vk` 映射字母/数字/F1–F24/方向/修饰键 | IME 候选窗未覆盖 | M2 ✅ 2026-10-21 |
| 中文输入 | ✅ | `Hello 世界 — 中文输入 ✅ line2` 经剪贴板 + `Ctrl+V` 粘贴，`wuia --value` 回读逐字节一致，测试窗落盘文本亦一致 | 仅 WPF TextBox 验证；部分应用拒收粘贴（M4 复合操作里再遇） | M2 ✅ 2026-10-21 |
| 等待窗口出现（轮询） | ✅ | `wwait` 100 ms 轮询：目标出现后 47 ms 内返回（要求 ≤200 ms）；超时 exit 3 `ENV_WAIT_TIMEOUT` | 只等"窗口出现"，不等"内容变化"（M4 需要时加谓词） | M2 ✅ 2026-10-21 |
| 语义点击（找到控件直接 Invoke） | ✅ | v1.1：`wuia --find-* + --invoke/--select/--toggle/--expand/--set-value`，每次动作返回回读状态；`ops/click-element` 优先 Invoke（不移动光标、遮挡可用），m10 17/0、m11 13/0 | Chromium 的部分自定义控件不暴露 Pattern，回落坐标点击 | M8 ✅ 2026-10-24 |
| 锁屏 / 断开检测 | ✅ | `Get-WaDesktopInfo` 用 `OpenInputDesktop`+`GetUserObjectInformation`（实测 `secured:false, desktop:"Default"`）；S3 用**只能更严格**的文件钩子断言 → `winput` exit 3 `SESSION_LOCKED`（SG-0002） | 真实锁屏不可自测（红线：无法解锁） | M3 ✅ 2026-10-21 |
| UAC / 安全桌面拒绝 | ✅ | 同一检测路径，桌面名命中 `Winlogon|Secure` → exit 3 `UAC_SECURE_DESKTOP`；`wshot` 同样拒绝 | 拒绝码映射依赖桌面名，新版本 Windows 需回归（K21） | M3 ✅ 2026-10-21 |
| 无授权不点 | ✅ | 无/过期/撤销/scope 不含 → exit 4；S1 目标按钮区域像素 diff = 0（真的没动） | — | M3 ✅ 2026-10-21 |
| 软急停 | ✅ | `pause.flag` → exit 4 `GUARD_PAUSED`；`grant.sh pause/resume` 一条命令 | 手离开键盘时需另一台设备或语音，本轮不做 | M3 ✅ 2026-10-21 |
| 审计账本 | ✅ | S5：20 个动作 → 20 行 `audit/YYYY-MM-DD.jsonl`，含 ts/tool/args/result/duration_ms；写失败则动作 exit 5 | 同用户可改删（事后证据，非防篡改） | M3 ✅ 2026-10-21 |
| 全局急停热键 | ⛔ | 用户确认「急停就按你说的」，只做软通道（Q4 关闭） | 需要常驻进程（G4），收益不抵风险 | 不做（D7） |

## 4. L4 · 视觉反馈（决定"能不能自己判断做没做成"）

| 能力 | 状态 | 证据 | 缺口 | 里程碑 |
|---|---|---|---|---|
| 全屏截图 | ✅ | `wshot` 2560×1600 物理像素 PNG，312–374 KB，544 ms；python3 独立读 IHDR 一致（C1） | — | M1 ✅ 2026-10-21 |
| 区域截图 | ✅ | `wshot --rect 100,100,400,300` → 400×300 PNG，8424 B | — | M1 ✅ 2026-10-21 |
| 图像像素级处理（PIL） | ✅ | PIL 12.2.0 | numpy 未装（纯 PIL 够用） | M1 |
| 图像**语义**理解（视觉模型） | **✅** | 2560×1600 截图读回后能读出标签页标题、地址栏、模型徽标等具体文字（`inventory/raw/2026-10-20-q1-vision.txt`） | 小字/精确对齐不可靠，C3 仍须程序判定 | M1 |
| 变化检测（前后帧 diff） | 🧪 | 纯 PIL 可实现 | 阈值需实测标定 | M2 |
| 文字提取（OCR） | ❌ | Windows 无 tesseract；`Windows.Media.Ocr` 需 WinRT 桥 | 建议不引入，改用 UIA 读文本 | — |

**关键判断（Q1 已答：支持）**：视觉通道可用，但**不改变 UIA 优先**的定位（D5）——
视觉擅长"整体局面判断 + 给人看证据"，像素级精度（≤2px）仍必须由 `wuia` 的 rect 提供，
并由程序（PIL 取色/叠框）验证，不靠模型肉眼。

## 5. 已知的坑（每条都够翻车一次）

| 坑 | 现象 | 对策 | 依据 |
|---|---|---|---|
| DPI 双坐标系 | 1707 逻辑 vs 2560 物理，混用点击偏移 1.5× | 所有原语 per-monitor v2 DPI aware，**对外只暴露物理像素** | 02 §2 |
| 中文输出乱码 | PS 5.1 默认 GBK，管道被当 UTF-16 | 脚本首行 `[Console]::OutputEncoding=UTF8`；复杂脚本走 `winps -`；统一 `ConvertTo-Json` | 02 §4.2 |
| 前台锁 | 窗口激活被系统拒绝，输入打到错误窗口 | 输入前校验前台窗口 == 目标窗口，否则 exit 3 `ENV_NOT_FOREGROUND`（不硬打）；`--focus` 会重试一次 | 已实现（M2） |
| 输入法抢键 | 中文 IME 吃掉按键 | 长文本一律"剪贴板 + Ctrl+V"，已实测一致 | 已实现（M2） |
| 相对鼠标移动无效 | `mouse_event(MOVE)` 不动 | 只用绝对 `SetCursorPos` | 技能库经验 |
| UIA 树超大 | 浏览器窗口几千节点 | `TreeScope.Children` 分层 + 条件过滤（控件类型/名称） | 实测（Edge） |
| 会话锁屏 | 锁屏后截图全黑、输入丢失 | `OpenInputDesktop`+`GetUserObjectInformation` 检测（`wdiag.desktop`）→ 直接报错 | 已实现（M1），S3 断言待 M3 |
| 中文路径 | bash 里拼路径被转义吃掉 | 脚本文件传参，不在命令行拼中文 | 待验（M1） |

## 6. 汇总：距"彻底接管"还差什么

| 差距 | 性质 | 归属 |
|---|---|---|
| ~~输入注入未复测（鼠标/键盘/拖拽）~~ | 已解决：C4–C7 实测通过 | ✅ 2026-10-21 |
| ~~视觉语义通道未知（Q1）~~ | 已解决：视觉可用 | ✅ 2026-10-20 |
| ~~只读通道未验收（C1–C3）~~ | 已解决：17/17 绿 | ✅ 2026-10-21 |
| ~~锁屏检测方法未定（Q2）~~ | 已解决：S3/S4 断言通过（钩子路径） | ✅ 2026-10-21 |
| ~~无守卫层（授权/急停/审计）~~ | 已解决：S1–S8 20/0 绿 | ✅ 2026-10-21 |
| ~~无一键式组合操作（"打开X并点Y"）~~ | 已解决：`ops/` 四件 + `SKILL.md`，C8 13/0 | ✅ 2026-10-21 |

**结论（2026-10-21 更新）**：L1/L2 齐备；L4 的"看得见"已验收（C1/C1b，物理像素 + 语义可读）；
L3 的"看得懂"已验收（C2/C3，hwnd 与 rect 精确对齐）；L3 的"点得中/打得进/等得到"已验收（C4–C7，2026-10-21）。
剩下的真正工作量已经不在"能不能跑起来"，而在 M5（稳定化、24 条全表回归、性能合批）与 M6（发布包、干净环境复演）。

已知硬限制：单次原语经 winps 桥 600–750 ms，所以"接管"必须靠复合操作（M4 的 `ops/`）把多次动作压进一次会话，而不是让 agent 逐步调原语。

## 7. L2.5 · 复合操作层（M4，2026-10-21 实测）

单次原语 600–750 ms，真实任务必须把多步压进一次 ops 调用。下面是 M4 落地的四个复合操作与两个窗口控制动作。

| 操作 | 状态 | 实测 | 备注 |
|---|---|---|---|
| `ops/open` 启动并等窗口 | ✅ | 记事本 564 ms 返回 hwnd（进程 pid 或标题两种匹配） | 只认「已出现的顶层窗口」，不猜 |
| `ops/find-and-click` 语义找控件并点中心 | ✅ | 20 次点击 20 次命中（C4 见 docs/07） | 点前强制 `wwin focus`；被遮挡则拒绝 |
| `ops/fill` 点击+全选+粘贴+读回 | ✅ | 48 字节中文+emoji 逐字符一致（matches=true） | 不匹配即失败，不假装成功 |
| `ops/wait-for` 等窗口或 UIA 控件 | ✅ | 控件出现后 606 ms 命中（轮询 200 ms） | 模态对话框只能用它等（子窗口） |
| `wwin focus` 激活窗口 | ✅ | 后台进程也能抢到前台（双线程 attach） | 纯 Win32，不产生合成输入 |
| `wwin close` 优雅关闭 | ✅ | 发 WM_CLOSE，脏文档由应用自己弹保存框 | 绝不替用户选"不保存" |

已知限制：

- 遮挡必须先激活：`winput` 的 S7 断言不允许点击"看起来在那儿但顶层不是它"的点。
- UIA 树巨大的应用（浏览器）默认 depth 8 / max 2000，深层控件要显式加深并接受更慢。
- 复合操作全部默认 dry-run，`--yes` 才注入；全部过 guard，全部写审计。
## 8. v1.1 语义层（2026-10-24 实测，M8）

v1.0 的四条绕路（窗口最大化写 PowerShell、悬停菜单靠坐标猜、滚轮/长按缺失、引号截断导致输入静默失败）
在 v1.1 全部变成一条命令。逐项证据见 `tests/reports/2026-10-24-m8.md`。

| 能力 | 状态 | 实测 | 测试 |
|---|---|---|---|
| 窗口状态 `wwin state/set` | ✅ | max→showCmd=3；restore 精确回原 rect；move 偏差 0 px；topmost 往返一致 | m6 N1–N10 |
| 悬停可判定 `winput hover` | ✅ | 返回落点元素，且 element.rect 包含悬停点（±2 px） | m7 N1–N3 |
| 滚轮 `winput wheel` | ✅ | 垂直/水平滚动后 ScrollPattern 读回位置变化 | m7 N4–N6 |
| 键盘长按/成对 `key --hold` `keydown/keyup/releaseall` | ✅ | held.json 记录按下集合，releaseall 后清空；故意不释放会告警 | m8 K1–K7 |
| 免引号输入 `type --stdin/--text-b64` | ✅ | 敌意文本 41 字节逐字节一致；空文本 rc=2 | m9 L1–L7 |
| UIA 语义查找 `wuia --find-*` | ✅ | 按 name/type/aid/class/enabled/on-screen/index 定位；`--point` 返回元素与祖先链 | m10 F1–F8 |
| 元素动作 `wuia --invoke/--select/--toggle/--expand/--set-value/--get-text` | ✅ | 动作后回读：计数 +1、选中项、ToggleState、Expanded、回读值与写入一致 | m10 A1–A11 |
| 复合：`click-element` / `wait-uia` / `hover-menu` | ✅ | 语义动作 + 必备校验；谓词等待 660 ms 命中；hover 菜单点到二级项 | m11 N15–N26 |
| 截图辅助 `wshot --hwnd/--grid` | ✅ | 窗口矩形精确一致；网格只改线附近像素（diff 2.7%），格心不变；sha256 与文件一致 | m12 N24–N29 |
| 危险名默认拒绝（S9） | ✅ | 名字含「删除」的节点 rc=3 `ENV_DANGEROUS_ACTION`，`--allow-danger` 才动手 | m11 N24/N24b |
| 网页整页正文（UIA TextPattern） | ✅ | `--find-aid RootWebArea --get-text` 347 字符，含 input/textarea 当前值，剔除 display:none（`docs/18`） | 手工实测（spike） |
| 网页内元素读写点 | ✅ | 页面按钮 depth 13、`patterns:["Invoke"]`；点后标题变化可判定；`--set-value` 经 CDP 交叉验证为真 DOM 值 | 手工实测（spike） |
| 网页深层自动加深 | ✅ | 网页内容在 depth 12–13，默认 depth 10 会误报找不到；`click-element`/`wait-uia` 首次落空自动加深一次并标 `deepened` | m11 N27 |

新增硬限制（实测得出，不是猜测）：

- 最大化窗口的 `GetWindowRect` 是 `-11,-11` 的越界边框，**几何判不出最大化**，必须读 `showCmd`（K43 记入 docs/11）。
- WPF `TextBlock` 不暴露 TextPattern，`--get-text` 回落 `Name`（K38）。
- 含中文的 `.ps1` 必须 **UTF-8 with BOM**，否则 PS 5.1 按 ANSI 读、中文变乱码（K39）。
- Chromium 的二级 hover 菜单不保证进 UIA 树：`hover-menu` 失败即 `ENV_MENU_NOT_SHOWN`，此时只选一级项并在交付报告写明。
- Chromium 的 a11y 树是**异步**长出来的：刚出窗口时只有 chrome（279 节点/707 名字字符），稍后才是 318 节点/1051 字符且含页面内容——读网页要用 `ops/wait-uia` 轮询，别一次性 find（`docs/18`）。
- 读网页正文**不需要 CDP**：CDP 只快 13 倍（0.11 s vs 1.50 s），但要求调试端口，而用户真实 Edge 没开——重启它属红线。CDP 只用于 cdp-hub 自起的受管一次性实例。

## 9 · v1.2 语义层补强（T12–T17）

| 能力 | 可用 | 判据（实测） | 验收 |
|---|---|---|---|
| 焦点不改状态 `wwin focus` / `ops/*` | ✅ | 最大化窗口 focus 前后 `showCmd=3`、rect 逐值不变；最小化窗口回到最小化前状态；成功 JSON `statePreserved:true` | m13 N1–N6 |
| 窗口族匹配 `--allow-related` | ✅ | 子对话框默认 mismatch，带 flag 点击落地并标 `matched:"related"`；无关窗带 flag 仍 mismatch 且报错带 hit 描述 | m13 N7–N12 |
| 输入可回读 `type --verify` | ✅ | WSL/Windows/相对路径都可；`exact`/`contains` 两模式；读不到/空/不符三码分离 | m14 N1–N11 |
| 原生路径 `wclip set --native-path` | ✅ | `/mnt/c/a/b` → `C:\a\b`，与 `--text/--text-file` 互斥 | m14 N9/N11 |
| 坐标契约 `wshot --box/--clip` | ✅ | `--box` 尺寸=右下−左上；越界提示含两条改法；`scale=1.5`；形态错误 `ARG_BAD_RECT` | m12 N30–N38 |
| 元素地图 `ops/map` | ✅ | 一次 UIA dump 出编号清单 + 红框图；编号按 (y,x) 稳定；`--text` 零截图；只需 `shot,uia` | m15 N1–N8 |
| 结果断言 `--expect-gone/--expect-alive` | ✅ | 消失/出现各自 ok + `waited_ms`；不成立 → `ENV_EXPECT_FAILED`；与 `--verify` 冲突 rc=2 | m11 N28–N31b |

新增硬限制：

- **`SW_RESTORE` 会改窗口状态**（K51）：凡是「只想把窗口提到前台」的代码，都不许无条件调 `ShowWindow(9)`；判据是 `IsIconic` + `GetWindowPlacement().showCmd`。
- **数元素用 `--find-type .`**（K49）：`--find-name .` 会漏掉无名控件（Edit/ComboBox），拿它做覆盖率会少算。
- **DIP ≠ 物理像素**（K53）：150% 缩放下差 1.5 倍；坐标一律取 UIA `rect` 或 `wwin state`，不要用界面代码里的 DIP。
- **`ops/map` 的编号只在同一次调用内稳定**：界面变化后要重新 `map`，不要跨截图复用 idx。

## 10 · v1.3 命中与正文（T20–T25）

| 能力 | 可用 | 判据（实测） | 验收 |
|---|---|---|---|
| 冷暖树自适配 `wuia` 默认深度 | ✅ | 冷进程首查 **542 节点 / depth 20 / 1545 ms**（v1.2 只有 chrome 约 279）；落空自动加深到 28 并重试；输出 `passes/warmMs/warmRetries/depthUsed/deepened` | m16 N1–N11 |
| 文本行索引 `--find-text RE` | ✅ | 行含 `text/rect/depth/actionable/clickable`，按 y 升序；无匹配 `total:0` 且 ok:true；真实页面 `--limit 120` 得 174 total / 120 几何行 / 2743 ms | m17 N1–N3、m21 N1 |
| 几何命中 `--point` | ✅ | FromPoint 直命 `via:"uia-point"`；命中容器/空时暖树 rect-hit 回退 `via:"rect-hit"`；空白点 `ENV_NO_HIT` rc=3 | m17 N4–N6、m21 N3 |
| 点击回报 `hit` | ✅ | 注入**之前**取 `hit{name,type,aid,rect,depth,actionable,clickable,raw}`；未命中 `hit:null`+`hitReason`；叶节点不可点时换成可点祖先并把原件放 `hit.raw` | m18 N1/N3/N4 |
| 点击效果断言 `--expect-change` | ✅ | `title` 实测 50–64 ms 命中；空白点 1000 ms 超时 `ENV_NO_EFFECT` rc=3 并附 `before/after/observed/elapsedMs`；只认 `title`/`rect` | m18 N1/N2/N8/N10 |
| 坐标 hit-test `ops/click-element` | ✅ | 落点属于别的窗口 → `ENV_HIT_MISMATCH` rc=3 且不注入；`--strategy click` 归一 `coords`；判断不了（容器节点）时放行 | m18 N5–N7 |
| 按文本点 `winput click --click-text` | ✅ | 取第 N 行中心注入，JSON 带 `hit`；夹具窗口标题由 `wa-deep` 变 `clicked:deep-btn` | m17 N7、m18 N1 |
| 输入落点契约 `type` | ✅ | 焦点不可编辑 → `ENV_NO_FOCUS`（`injected:false`）；粘贴未落地 → `ENV_NO_EFFECT`（`pasteSettled:false`、`before==after`）；`--force` 越过并回显 `forced:true` | m19 N1–N8 |
| 正文一条命令 `ops/read-text` | ✅ | UIA 取回 **173067 字符**（真实 Edge）；`source:"uia"`；`--force-clip` 走剪贴板并还原（`clipRestored:true`）；`--no-fallback` 空文本 `ENV_NO_TEXT` | m20 N3–N6、m21 |
| 输出路径 `wshot --out` | ✅ | `/tmp/x.png` → `mapped:true`、`path` 为 Windows 落点、`wsl_path` 原样、sha256 与文件一致；`/mnt/c` 目标不中转 | m20 N1/N2 |

新增硬限制：

- **先定窗再取样带**（K70）：Chromium 树里滚出视口的内容 `rect.y` 是 `-48412` 级负数，工具栏行 depth 7–8。按「`y>0` 且 `depth>=8`」取首行在真实页面会全军覆没，要按窗口 rect 取 `y ∈ [top+30, bottom-30]` 的带。
- **`hit` 是 a11y 语义不是像素**：FromPoint 常落在按钮内部的 `TextBlock`（`actionable:false`），所以 `hit.name` 可能为空、`hit.actionable` 需要看 `clickable` 或祖先；它不是「像素上颜色变了」的证据，像素证据请配合 `--expect-change rect` 或 `wshot` 前后对比。
- **`--expect-change` 只认 `title`/`rect`**：不认文本、不认颜色、不认 DOM；要断言「出现/消失」用 `ops/click-element --expect-gone/--expect-alive`，要断言文本落地用 `type --verify`。
- **冷进程首查 2–3 s 是正常的**：a11y 树异步生长，默认会预热+重试；批量读网页请在**一次调用**里多取，而不是每步起一个新进程（每次冷启动都要付费）。
- **`--find-text` 的行是 a11y 树视图内的行**：视口外的行 rect 为负，click-by-text 会拒绝（`ENV_HIT_MISMATCH`/`ENV_NO_HIT`）而不是盲点；要滚到位再点。

## 11 · v1.4 滚动与复合录入（T28–T31）

v1.4 的主题是「把一个点放进可滚动容器里、证明容器真的滚了、滚到目标可见再点」——docs/23 里 16 次盲滚的根因。

| 能力 | 状态 | 判据/证据 | 验收 |
| --- | --- | --- | --- |
| 滚动容器与状态 `wuia --scroll-info` | ✅ | 返回 `chain`（逐级祖先）+ `container{rect,scroll{percentX,percentY,viewWidth,viewHeight}}` + `via:scroll-pattern\|rect\|none`；WPF 夹具上 `opt-28` 走 pattern、被 `ClipToBounds` 裁掉的文本走几何兜底 | m22 F19-1..4 |
| 滚到可见 `ops/reveal` | ✅ | 每步重查 `ScrollPercent`，变了才算移动；pattern 快路 + wheel 主路 + hover 重试；收尾用 `wuia --point` 证明落点命中目标；滚不动 `ENV_SCROLL_NOT_MOVED`、步数用尽 `ENV_NOT_REVEALED`、已是可见 `steps:0` 且不注入 | m23 F20-1..6 |
| 滚动 + 点击一条命令 `winput click --reveal` | ✅ | 内部调 `ops/reveal` 并用它证明过的点注入，JSON 同时带 `reveal` 与 `hit`；与 X Y / `--click-text` 互斥、必须 `--expect-hwnd` | m23 F20-7 |
| 选择类控件 `ops/select-option` | ✅ | `panel`（页内展开）与 `native`（独立顶层弹层，`GW_OWNER` 是主窗）双路径，`mode:"auto"` 先 native 后 panel；`--expect-value` 读回见证元素，不符 `ENV_NO_EFFECT`；失败 `ENV_NO_OPTION` 带 `tried` | m24 F21-1..5 |
| 串行录入三件套 | ✅ | `ops/chip-add`（chip 数 +1 且内容相等且输入框清空，Enter 被吞自动 `enter-again`）、`ops/rich-write`（点击+全选+粘贴+前缀回读，指定 verify 目标时不退回整窗正文）、`ops/wait-ready`（存在且已布局，`lastCount` 区分没出现/没布局） | m25 F22-1..4 |
| 弹层发现 `wwin list --owned-by/--include-empty` | ✅ | 空标题但 `GW_OWNER` 非零的可见顶层窗 = 弹层；每次展开句柄都会变，所以按 owner 现查而不是缓存 | m24 F21-2 |

新增硬限制：

- **`via` 只说这次是怎么判断的，不说谁对**：`scroll-pattern` 是 UIA 实现（能拿到百分比），`rect` 是几何兜底（只能判断「越界了」）。两者都没有 = `none`，此时 `ops/reveal` 会直接拒绝而不是盲滚。
- **点必须落在目标窗口内**：`wuia --point` 先 `SetForegroundWindow` 再 `FromPoint`；夹具窗口被别的窗压住时命中的是压在上面的窗，`ops/reveal` 因此内置 `op_focus`。
- **默认 dry-run**：`ops/reveal` / `ops/select-option` / `ops/chip-add` / `ops/rich-write` 都要 `--yes`；dry-run 只报计划（滚几步、点哪里、预期值），不注入、不需要 input grant。
- **每一步都要正面证据**：`ScrollPercent` 必须变、「见证值」必须变、chip 数必须 +1；`ok:true` 只代表注入了，不代表生效了。
- **`hit` 仍是 a11y 语义**：`ENV_HIT_MISMATCH` 是「证明不了落点属于目标」，不是像素断言失败。
