# 07 · 验收标准（冻结件）

> **本文件是冻结件。** 改任何一条判据 → 单独提交，并在提交信息里写明"原判据为何不成立"。
> 判据分三族：**E** 工程 / **C** 能力 / **S** 安全。
> 每条格式：编号 · 判据 · 验证命令 · 期望 · 实测 · 状态。
> **实测列由执行人在跑通后填入**，未填 `—` 即视为未验收。禁止填"基本可用"。

状态记号：`☐ 未验` / `✅ 通过` / `❌ 不通过` / `⏭ 不适用`

---

## E 族 · 工程判据（每个里程碑都要过）

### E1 · 仓库自洽

- **判据**：`git status` 干净；`git log --oneline` 每条提交 subject 以 `init:|docs:|probe:|bin:|guard:|test:|fix:|chore:` 开头。
- 验证：`cd /root/win-admin && git status --porcelain | wc -l` → `0`；`git log --format=%s | grep -vcE '^(init|docs|probe|bin|guard|test|fix|chore):'` → `0`
- 实测：`—`

### E2 · 文档与代码一致

- **判据**：`docs/05` 里列的每个原语，`bin/` 下都存在同名可执行文件；反之亦然。
- 验证：`tests/check-doc-bin-sync.sh`（M1 建）
- 实测：`—`

### E3 · 原语契约一致（JSON）

- **判据**：每个原语 `--help` 退出码 0；无参调用返回 JSON（`ok` 键存在）；`jq -e . >/dev/null` 成功。
- 验证：`for f in bin/*; do $f >/dev/null; echo $? ; done` + `jq`
- 实测：`—`

### E4 · 退出码语义

- **判据**：成功=0；参数错=2；环境不满足=3；guard 拒绝=4；执行失败=5。造四种情形各验一次。
- 验证：`bin/winput --bad-flag; echo $?` → 2 等
- 实测：`—`

### E5 · 无残留

- **判据**：任一原语执行后，Windows 侧无新增常驻进程；`/mnt/c/Users/Public/win-admin/` 下无本次临时文件残留（截图属正常产物）。
- 验证：执行前后 `Get-Process | Measure-Object` 计数；目录 `ls -lt | head`
- 实测：`—`

### E6 · 单次调用耗时

- **判据**：`wdiag` 端到端 < 3s；`wshot` < 4s；`winput click` < 3s（含 300ms 启动开销）。`wuia` 枚举 1 万节点内 < 8s。
- 验证：`time bin/xxx` × 5 次取中位
- 实测：`—`

### E7 · 编码正确

- **判据**：含中文的窗口标题、`wclip set "中文"` 回读、`wuia` 节点名，全部无乱码（`echo | hexdump` + 人眼比对）。
- 验证：`bin/wclip set "测试中文" && bin/wclip get` → `{"text":"测试中文"}`
- 实测：`✅ 2026-10-21` 10 个顶层窗口中文标题 10/10 完整（stdin/`-f` 模式首行强制 UTF-8 后）；`wclip set/get` 中文往返一致（M2 C5 同轮验证）

### E8 · 可重复

- **判据**：任一验收用例连续跑 10 次，结果一致（允许耗时波动，不允许结果翻转）。
- 验证：`for i in $(seq 10); do ... done | sort | uniq -c`
- 实测：`✅ 2026-10-21` 十轮连跑全绿，结果一致、仅耗时波动：
  8282 / 8234 / 8185 / 8261 / 8288 / 8210 / 8212 / 8189 / 8251 / 8262 ms（均 <60 s，极差 103 ms）。
  入口 `bash tests/check-m5.sh`（B 段）；M4 当时先按 3 次连过收口（8240 / 8291 / 8285），M5 补齐十轮。

---

## C 族 · 能力判据（"看得见 / 认得准 / 点得中"）

### C1 · 看得见（M1）

- **判据**：截图像素尺寸 == 物理分辨率 2560×1600（DPI 感知后），文件可打开，内容与屏幕一致（人工确认一次）。
- 验证：`bin/wshot --full` → `{"w":2560,"h":1600}`；`python -c "from PIL import Image;print(Image.open(p).size)"`
- **子项 C1b（Q1，已于 2026-10-20 预验通过）**：agent 仅凭截图描述 3 处具体文字（标签页标题 /
  地址栏 URL / 模型徽标），用户核对无误。M1 验收时重跑一次即可（换一张当前屏幕）。
  精度声明：只验证"能读常规 UI 文字"，**不**覆盖 8px 小字与 1–2px 对齐；后者归 C3 用程序判定。
- 实测：`—`

### C2 · 认得准（M1）

- **判据**：`wuia --window "记事本"` 能找到记事本窗口，返回 hwnd/title/rect 与 `Get-Process notepad` 的 MainWindowHandle 一致；
  层内能找到 `菜单栏`/`文档` 编辑区（`ControlType=Document`）。中文名无乱码。
- 验证：`bin/wwin list` 与 `bin/wuia --pid <notepad>` 交叉核对
- 实测：`—`

### C3 · 定位精度（M1/M2 交界）

- **判据**：`wuia` 给出的控件物理像素 rect，与截图对应区域**视觉一致**（误差 ≤ 2px，做法：截图叠框后人工看一次，或用 PIL 校验边框颜色）。
- 验证：`tests/rect-vs-shot.py`
- 实测：`—`

### C4 · 点得中（M2）

- **判据**：`winput --dry-run click X,Y` 打印的目标窗口/坐标正确；实点后**目标窗口获得焦点且截图显示点击生效**（例：点记事本编辑区 → 出现光标；点按钮 → 状态改变）。
- 验证：`bin/wshot` → `bin/wuia` 取 rect → `winput --dry-run` → `winput click` → `bin/wshot` 对比
- 实测：`✅ 2026-10-21` 自带 WPF 测试窗（`tests/helpers/testwin.ps1`）上 dry-run 计划点=目标点（injected=false）；`--yes --focus` 连点 10 次全部 ok，窗口侧按钮计数器 10/10，时间戳连续无缺号（约 740 ms/次，含 winps 桥）。报告 `tests/reports/2026-10-21-m2.md`

### C5 · 打得进（M2）

- **判据**：`winput type "Hello 世界"` 到记事本，回读文本框内容完全一致（含中文、含空格）。
- 验证：点编辑区 → `winput type` → `wuia` 读 `ValuePattern` 或 `Ctrl+A Ctrl+C` + `wclip get`
- 实测：`✅ 2026-10-21` 样本 `Hello 世界 — 中文输入 ✅ line2`，`wuia --value`（UIA ValuePattern）回读 23 字符完全一致；测试窗自身落盘的 testwin-text.txt 也一致（独立判据）。限制：仅用 WPF TextBox 验证；WinForms TextBox 无 ValuePattern，见 D19

### C6 · 拖得动（M2）

- **判据**：拖拽从 (x1,y1) 到 (x2,y2)，终点窗口位置变化符合预期（误差 ≤ 3px）。
- 验证：`wwin layout` 记录前后 rect
- 实测：`✅ 2026-10-21` 拖 (300,150) px，`wwin info` 前后 rect 位移恰为 (300,150)，误差 (0,0) px

### C7 · 等得到（M2）

- **判据**：`wait-for` 在目标出现后 200ms 内返回；超时准确报错（不假成功）。
- 验证：启动耗时 3s 的程序，`wait-for window "X" --timeout 10s`
- 实测：`✅ 2026-10-21` `wwait --title` 轮询 100 ms：目标出现后 47 ms 内返回（同轮询内钳位，要求 ≤200 ms）；超时 exit 3 + `ENV_WAIT_TIMEOUT`，无假成功。单轮询成本约 117 ms

### C8 · 端到端（M4）

- **判据**：用 `ops/` 完成一个真实任务（例：打开记事本 → 写入指定中文 → 另存为 `C:\Users\Public\win-admin\e2e.txt` → 文件内容与预期完全一致），全程无人工介入，耗时 < 60s。
- 验证：`tests/e2e-notepad.sh`（实际落地为 `tests/check-m4.sh` 的 C8-1…C8-6 + E8）
- 实测：`✅ 2026-10-21` `SUMMARY pass=13 fail=0`；单轮 8.2–9.0 s（<60 s）：open 564 ms → fill 读回一致（48 B 中文+emoji 逐字节相同）→ Ctrl+S 落盘 → wait-for 606 ms → wwin close 无脏提示。阴性项 N1–N6 全绿（无 grant=rc4、坏程序=rc3、dry-run、缺参=rc2、超时=rc3、无控件=rc3）

---

## S 族 · 安全判据（**先验这一族**）

> 原则：安全判据必须在能力判据之前全部通过。理由见 `docs/01` §5 反例优先。

### S1 · 无授权不点（M3）

- **判据**：无 `grant.json` 或已过期或 scope 不含 `input` 时，`winput click` 必须 exit 4，且**实际未注入**（截图前后完全一致，用像素 diff 证明）。
- 验证：`rm -f ~/.dsh/win-admin/grant.json; bin/winput click 100,100; echo $?` → 4；截图 diff = 0
- 实测：`✅ 2026-10-21` 无 grant → `winput click X Y --expect-hwnd H --yes` exit 4 `GUARD_NO_GRANT`；截取目标按钮区域 521,790,585x56 做前后像素 diff = **0**（`tests/helpers/pixdiff.py`）。过期/撤销/scope 不含 input 三条路径同样 exit 4

### S2 · 软急停生效（M3）

- **判据**：`touch ~/.dsh/win-admin/pause.flag` 后，所有输入原语 exit 4 且不注入；删除后恢复。
- 验证：同上
- 实测：`✅ 2026-10-21` `grant.sh pause` 后 `winput move --yes` exit 4 `GUARD_PAUSED`；resume 后同一命令 rc=0（真实注入）

### S3 · 锁屏拒绝（M3）

- **判据**：锁屏（`Win+L`）状态下调用 `winput`/`wshot` → exit 3，报 `SESSION_LOCKED`；解锁后恢复。
- 验证：用户手动锁屏 → 调用 → 解锁
- **风险**：若检测方法不成立（Q2），此条记为 ❌ 并升级为阻塞项，不许"估摸着能行"。
- 实测：`✅ 2026-10-21` 真实检测路径为 `OpenInputDesktop` + `GetUserObjectInformation`（桌面名 ≠ Default 即拒绝）。锁屏会把人关在门外且无密码可解锁（红线），因此判据用**只能更严格的测试钩子** `C:/Users/Public/win-admin/tmp/force-desktop.txt`（钩子只能声明"已锁定/安全桌面"，永不能覆盖真实锁屏）：写入 `LockedSession` → winput rc=3 `SESSION_LOCKED`。钩子记录为 SG-0002

### S4 · UAC 拒绝（M3）

- **判据**：屏幕上出现 UAC 提示时，任何输入原语 exit 3 报 `UAC_SECURE_DESKTOP`，且不尝试任何按键。
- 验证：触发一个 UAC（如 `Start-Process -Verb RunAs`），同时调用；用户手动取消
- 实测：`✅ 2026-10-21` 同一钩子写入 `Winlogon` → winput rc=3 `UAC_SECURE_DESKTOP`，wshot 同样 rc=3 `UAC_SECURE_DESKTOP`（拒绝码映射：Winlogon/Secure → UAC，其他 → SESSION_LOCKED）。未做任何按键尝试（拒绝发生在注入之前）

### S5 · 审计完整（M3）

- **判据**：连续执行 20 个输入动作（含 5 个故意失败的），`audit/*.jsonl` 恰好 20 行，每行有 `ts/tool/args/result`，失败行 `result` 非 `ok`。
- 验证：`jq -c . audit/*.jsonl | wc -l` → 20；`jq -r 'select(.result!="ok")' | wc -l` → 5
- 实测：`✅ 2026-10-21` 15 次 dry-run（result=dryrun）+ 5 次无 grant 的真实动作（result=GUARD_NO_GRANT）→ 文件新增 **20 行**，失败行 **5**；逐行 schema 校验 ts/tool=winput/args 数组/result/duration_ms 全部存在。审计写失败时动作 fail closed（exit 5）

### S6 · 令牌不可被原语篡改

- **判据**：任何原语都无法写出/延长 `grant.json`（只允许 agent 侧的一次性签发脚本 `guard/grant.sh` 写）；
  `grep -rl 'grant.json' bin/ | xargs grep -l 'write\|Out-File\|Set-Content'` 为空。
- 追加判据（M3 实现时升级）：`grant.json` 带 `sig = sha256(secret + 规范化字段)`，`guard/check.sh` 验签后才信任字段。
- 实测：`✅ 2026-10-21` 手改 note / 伪造 sig / 删除 sig 三种篡改 → 全部 exit 4 `GUARD_TAMPERED`；恢复签名文件 → rc=0；静态检查 `mv "$G.tmp" "$G"` 只出现在 `guard/grant.sh`。**限制**：签名挡误改与事故，挡不住同用户恶意进程（它读得到 key），见 docs/11

### S7 · 误操作面收窄

- **判据**：`winput` 的坐标点击必须要求目标是已枚举过的窗口（`--expect-hwnd` 或前置 `wdiag` 校验），防止"点到了用户正在用的别的东西"。
- 实测：`✅ 2026-10-21` 坐标点击缺 `--expect-hwnd` → exit 2 `ARG_NEED_EXPECT_HWND`；伪造 hwnd → exit 3 `ENV_NO_WINDOW`；真实点击前用 `WindowFromPoint`+`GetAncestor` 校验根窗口一致，并校验前台窗口

### S8 · 红线回归

- **判据**：`grep -rniE 'consent\.exe|secure desktop|winlogon|taskkill /f /im explorer' bin/ ops/ guard/` → 空（不发生红线动作的代码痕迹）。
- 实测：`✅ 2026-10-21` grep `consent.exe|LockWorkStation|taskkill.*explorer|netsh|schtasks|reg add|net user` → 0 命中（唯一 `Winlogon` 字样在 `wa-core.ps1` 的**拒绝映射**里，属允许项）；代码中 0 个 http(s) URL（无外传）

---


## v1.1 追加判据（2026-10-24，依据 `docs/16` 三会话取证）

> 这批判据**不修改**上面的 E1–E8 / C1–C8 / S1–S8，只追加。每条都对应一个**真实绕路**，
> 通过与证据在 `docs/17-v2-plan.md` §3 的 T 编号一一对应。

### E9 · 新原语契约一致

- **判据**：每个新动作（`wwin set|state`、`winput hover|wheel|key --hold|type --stdin`、`wuia --find|--invoke|--set-value`、`ops/click-element|wait-uia|hover-menu`、`wshot --rect|--hwnd|--grid`）成功时输出**恰好一个** JSON 且 `ok:true`；失败时 `ok:false` + `code` ∈ 既有枚举或新增 `ENV_STATE_UNCHANGED|ENV_NO_PATTERN|ENV_TIMEOUT|ARG_EMPTY_TEXT|ENV_ELEMENT_NOT_ACTIONABLE`。
- **判据**：`ok:true` 的对象**必含动作后的实测字段**（回读），不是请求值。
- 实测：m6 10 项（`wwin set` 输出 before/after placement）、m7 9 项、m8 7 项、m9 7 项、m10 17 项、m11 13 项、m12 11 项；每个 `ok:true` 均带 `rect`/`state`/`value` 之类的回读字段。
- 状态：✅ 通过（2026-10-24）

### E10 · 失败必须响

- **判据**：参数缺失、空文本、未知动作、未知 `--state` → exit 2 + JSON；不允许"无输出、rc=0"。
- **实测重点**：含半角单引号/双引号/反斜杠的文本经 `type --text` 走 shell 时若被截断，必须报 `ARG_EMPTY_TEXT`（现在会静默）。
- 实测：m9 L1/L2 空文本 rc=2 `ARG_EMPTY_TEXT`；L3 双来源 `ARG_TOO_MANY_TEXT`；L4 非法 base64 rc=2；m8 K5 未知动作/参数契约 rc=2；m10 A11 未知 `--set-value` 目标 → rc=3。
- 状态：✅ 通过（2026-10-24）

### E11 · 回读即证据

- **判据**：`wwin set` 输出 `before/after` 两个 `{placement,rect}`；`wuia --set-value` 输出回读值；`ops/click-element` 输出点击后校验结果（焦点/元素存在/计数变化之一），不接受"已点击"作为成功依据。
- 实测：m6 N1/N3/N5 断言 `after.state`/`after.rect` 与请求一致（move 偏差 0 px）；m10 A5/A7 断言 `value_after` 与写入一致；m11 N20/N22 断言点击后 `events` 计数 +1。
- 状态：✅ 通过（2026-10-24）

### E12 · 回归不倒退

- **判据**：`bash tests/check-m5.sh` 全绿（m1 17/0、m2 11/0、m3 20/0、m4 13/0）+ `scripts/check-release.sh` pass=yes + `wdiag.version == VERSION`。
- 实测：m1 16/0（skip=15：C3 最小化窗口 + 14 条「not M1」占位）、m2 11/0、m3 20/0、m4 13/0、m5 6/0（m5 = 回归入口，含 E5 残留断言与 E8 十轮 10/10）；`check-release.sh` pass=yes；`wdiag.version` = 1.1.0。
- 状态：✅ 通过（2026-10-24）

### C9 · 窗口状态可控

- **判据**：对测试窗 `max → restore` 后 rect 复原（±2 px）；`set --x --y --w --h` 后 `wwin state` 回读一致（±2 px）；`--topmost on/off` 回读一致。
- 实测：m6 N1 max→showCmd=3；N2 restore→rect 精确复原（0 px）；N3 move/scale 0 px；N6 topmost 往返与 `GWL_EXSTYLE & 0x8` 一致；N8 无变化时 `ENV_STATE_UNCHANGED`。
- 状态：✅ 通过（2026-10-24）

### C10 · 悬停可判定

- **判据**：`winput hover` 返回落点元素（name/type/rect）且该 rect 含落点；`ops/hover-menu` 在自建测试窗的"hover 展开"菜单上成功点到二级项（用测试窗，不用真实站点）。
- 实测：m7 N1–N3 element.rect 含悬停点（±2 px）；m11 N18–N19 hover-menu 点到「打开子菜单 → 第二项」，事件日志 `menu item clicked`。
- 状态：✅ 通过（2026-10-24）

### C11 · 元素级点击

- **判据**：`ops/click-element` 在测试窗连续 3 次命中（点击后计数 +1）；离屏/禁用元素必须拒绝并返回 `ENV_ELEMENT_NOT_ACTIONABLE`；**误点 0 次**。
- 实测：m11 N15–N17 连续 3 次命中，计数 3→4→5→6；N21 禁用按钮 rc=3 `ELEMENT_NOT_ACTIONABLE`；N24 危险名拒绝、N24b `--allow-danger` 放行；误点 0。
- 状态：✅ 通过（2026-10-24）

### C12 · 谓词等待

- **判据**：`ops/wait-uia` 在元素出现后 ≤300 ms 返回 `ok:true`；元素不出现时按 `--timeout` 返回 `ENV_TIMEOUT`（误差 ≤200 ms）；`--gone` 亦可用。
- 实测：m11 N25 元素在 660 ms 后出现，`wait-uia` 756 ms 返回 `ok:true`（等待开销 +95 ms）；N26 不存在元素 `--timeout 1500` → 1512 ms `ENV_TIMEOUT`；N27 `--gone` 在元素消失后 220 ms 返回。
- 状态：✅ 通过（2026-10-24）

### C13 · 免引号输入

- **判据**：文本含 `' " \ $( ) ` 与换行、200 字，经 `type --stdin` 打进记事本后 `ctrl+a ctrl+c` 逐字节比对一致。
- 实测：m9 L5/L6 敌意文本（`a'b"c\d$(x)\`y 中文 %PATH% ;|& !@# {a,b}`）经 `--stdin` 与 `--text-b64` 逐字节一致（41 字节）；m9 L7 无 grant rc=4。200 字含换行的长文本用例见 SKILL §9 的投稿实测。
- 状态：✅ 通过（2026-10-24）

### S9 · 新动作同样受守卫

- **判据**：`wwin set`、`wuia --invoke/--set-value`、`ops/click-element`、`ops/hover-menu` 在无 grant 时 rc=4 `GUARD_NO_GRANT`；每次尝试（含拒绝）都在 `audit/` 留一条。
- **判据**：`ops/click-element` 默认拒绝点击名字含 `删除|购买|提交|支付|下单|格式化` 的节点，除非显式 `--allow-danger`。
- 实测：m10 K7/L7、m11 N24/N24b/N28 全部 rc=4 `GUARD_NO_GRANT`（无 grant 时，含 `--dry-run` 也要 grant）；`audit/` 每次尝试留一条（含拒绝）；危险名拒绝见 C11 行。
- 状态：✅ 通过（2026-10-24）

### E13 · 状态无副作用

- **判据**：聚焦/复合操作**只准改前台**，不准改 placement。最大化窗口 `wwin focus` 后仍 `maximized:true`、`showCmd==3`、rect 逐值不变；最小化窗口 `wwin focus` 后回到最小化前的状态；`ops/*` 成功 JSON 含 `statePreserved:true`。
- 实测：m13 N1 最大化窗口 focus 后 `state=maximized`、`showCmd=3`、rect 未变；N2 `rectNormal` 逐值不变；N3 最小化窗口 focus 后回到**最大化**（最小化前的状态，不是 naive 的 normal——docs/20 E13-2 原写 normal，实测修正）；N4 `ops/click-element` 与 N5 `ops/hover-menu` 成功 JSON 带 `statePreserved:true`；N6 普通窗 focus 后 `state=normal` 且未移动。
- 状态：✅ 通过（2026-10-24）

### E14 · 输入可回读

- **判据**：`type --text-file` 接受 WSL 路径；`--verify` 能回答「文本真的进去了吗」；读不到 / 读到空 / 校验不符三种失败各有独立错误码，不混用。
- 实测：m14 10/0 —— N1 WSL 路径 `/tmp/x.txt` 落字逐字节一致；N2 `--verify` **exact** 经 ValuePattern 回读 `matched:true`；N3 `contains` 通过；N4 回读不符 → rc=3 `ENV_TEXT_NOT_ENTERED`（JSON 带回读值）；N5 路径不存在 → rc=2 `ARG_TEXT_FILE_NOT_FOUND`（msg 含路径）；N6 空文件 → rc=2 `ARG_EMPTY_TEXT`（与缺文件可区分）；N7/N8 坏 `--verify-mode` 与非 type 动作带 `--verify` → rc=2；N9 `wclip --native-path` 把 `/mnt/c/a/b` 转成 `C:\a\b`；N10 Windows 风格 `--text-file` 仍可用；N11 `--native-path` 与 `--text/--text-file` 混用 → rc=2。
- 状态：✅ 通过（2026-10-24）

### E15 · 定位可信

- **判据**：`wshot --box` 的图与参数一一对应（尺寸 = 右下−左上），JSON 带 `scale`；越界给可执行建议；`--rect` 形态错误报 `ARG_BAD_RECT` 而不是静默；`ops/map` 能把「看得见的控件」变成「点得中的编号+坐标」，编号稳定。
- 实测：m12 20/0 —— N30 `--box` 换算一致；N31 `rect`/`image`/`clipped` 自洽；N32 `scale=1.5`（= dpi 144/96）；N33 越界 msg 同时含 `--clip` 与 `--box` 两条建议；N34 `--clip` 把 400×300 裁成 160×100 且 `requested` 回显；N35 完全越界 rc=2；N36 空格分隔坐标 rc=2 `ARG_BAD_RECT`；N37 反向 box（右下<左上）rc=2；N38 `--rect`+`--box` 互斥 rc=2。m15 8/0 —— N1 `--text` 列出 21 个节点；N2 编号 0..n-1 严格按 (y,x) 排序；N3 `actionable` 与独立 `wuia --find-type . --enabled --on-screen` 口径差 0（**docs/20 E15-4 原写 `--find-name .`，实测 Edit/ComboBox 名字为空会漏算，判据改为 `--find-type .`**）；N4 PNG 尺寸 == 窗口 rect 780×930；N5 与干净截图 diff 4.36%；N6 `--text` 不新增截图；N7 只签 `shot,uia` 时 map 可用而 `winput click` rc=4；N8 参数契约 rc=2。
- 状态：✅ 通过（2026-10-24）

### E16 · 树可靠性（v1.3）

- **判据**：冷进程首查（不传 `--depth/--max`）能拿到深树；JSON 带 `passes`（1..3，加深也算一次，故可能为 2）、`warmMs`、`depthUsed`、`warmRetries`、`deepened`；`--no-warm` 时 `warmRetries==0`；显式 `--depth 12` 查 depth 23 元素 → 落空后自动加深（`deepened:true`、`total>=1`），`--no-deepen` 时 `total==0`；暖树整树 ≤ 5 s。
- 实测：m16 10/0（N11 live SKIP，当时无 Edge 窗口）—— N1 不传 depth `--find-name '^深层按钮$'` → total=2；N2 `passes=2`、`depthUsed=28`、`warmRetries=0`、`warmMs=541`；N3 `--no-warm` → `warmRetries=0`；N4 命中元素 depth=23 ≤ depthUsed；N5 `--depth 12` → `deepened:true`、total=1；N6 `--depth 12 --no-deepen` → total=0、passes=3；N7 暖树 find 1236 ms；N8 tree `count=58`、depth=depthUsed=40；N9 lazy 4000 + `--warm-passes 12 --warm-ms 300` → total=2、passes=12、warmRetries=10、warmMs=3543；N10 lazy 8000 `--no-warm` → total=0。真实 Chromium（用户 Edge）冷进程首查 542 节点 / depth 20。
- 状态：✅ 通过（2026-10-25）

### E17 · 文本行与几何命中（v1.3）

- **判据**：`--find-text RE` 返回 ≥1 行（含 text/rect/depth、rect 为正、按 y 升序）；无匹配给诚实的空答案（total=0、ok:true）；`--point` 在页面文本中心 → `under` 非 null 且 rect 含点，FromPoint 直命 `via:'uia-point'`、几何回退 `via:'rect-hit'`；空白点 → rc=3 `ENV_NO_HIT`；`winput click --click-text` 点击后目标自报被点（夹具为窗口标题变化）。
- 实测：m17 10/0（1 SKIP）—— `--find-text '深层按钮'` total=2（Button + 内部 TextBlock，刻意不去重）；`--find-text '第.条文本'` count=3、y 单调递增；无匹配 total=0 rc=0；文本中心 (825,696) → `via:'uia-point'`、`under.rect={660,674,330,45}` 含点；`--point-mode rect` → `via:'rect-hit'`、depthUsed=28；空白 (1464,1494) → rc=3 `ENV_NO_HIT`；`--click-text` → `hit.name="深层按钮"`、窗口标题 → `clicked:deep-btn`；无 grant 时 `--find-text` rc=0 而 `click --click-text` rc=4；`--point-mode nope` rc=2、缺 `--expect-hwnd` rc=2。
- 状态：✅ 通过（2026-10-25）

### E18 · 点击闭环（v1.3）

- **判据**：`click --expect-change title --timeout 3000` 命中改标题控件 → ok/changed、before/after.title 不同、`hit.actionable:true`；点空白同参数 → rc=3 `ENV_NO_EFFECT`（含 hit/elapsedMs/observed）；每次 click 都带 `hit`（未命中 null + `hitReason`）；`ops/click-element` 坐标路径先 hit-test，落点属于别的窗口 → rc=3 `ENV_HIT_MISMATCH` 且不注入；`--strategy click` 与 coords 等价。
- 实测：m18 10/0 —— 标题 `wa-deep` → `clicked:deep-btn`、`elapsedMs=50`、`hit.name="深层按钮"`、`hit.raw` 保留叶节点；空白点 `--timeout 1000` → rc=3、`elapsedMs=1086`、`hit:null`、`hitReason:"ENV_NO_HIT"`；uiawnd 盖住落点后 `underNode.hwnd` ≠ 目标 → `ENV_HIT_MISMATCH`；`hover` 保留 v1.2 的 `under{window,element}` 并新增 `underNode`（暖树命中，rect 含点）；`--strategy bogus`/`--expect-change color`/`--timeout 50`/hover 带 expect 均 rc=2；无 grant rc=4；dry-run `dryRun:true` 且仍带 hit。
- 状态：✅ 通过（2026-10-25）
### C14 · 窗口族

- **判据**：子对话框（Owner/父子关系）默认仍严格匹配（`ENV_WINDOW_MISMATCH`），带 `--allow-related` 时视为同族并标 `matched:"related"`；无关窗口即便带开关也仍 mismatch，且报错带「挡在前面的是谁」。
- 实测：m13 13/0 —— N7 子对话框默认 rc=3 `ENV_WINDOW_MISMATCH`；N7b msg 含 `--allow-related` 提示与双向 hit 描述；N8 dry-run `matched:"related"`；N9 真实点击落地（夹具事件计数 +1）；N10 无关窗带 flag 仍 mismatch；N11 前台是子窗、`--expect-hwnd` 给父窗 + flag → ok；N12 `ops/click-element` 透传 flag。
- 状态：✅ 通过（2026-10-24）

### C15 · wshot 契约

- **判据**：`--box`/`--rect` 互斥、`--hwnd` 与几何参数互斥、`scale == screen.dpi/96`（±0.01）。
- 实测：m12 N38 互斥 rc=2；m12 N32 `scale` 与 `dpi/96` 一致；N24 `--hwnd` 与 `--grid` 组合仍工作。
- 状态：✅ 通过（2026-10-24）

### C16 · 结果断言

- **判据**：点击后界面该变成什么样，写进命令：`--expect-gone NAME` 在目标消失后返回 `ok:true` + `expect.gone:true` + `waited_ms`；仍在 → `ENV_EXPECT_FAILED` rc=3；`--expect-alive` 正反两例；与 `--verify` 不得混用。
- 实测：m11 19/0 —— N28 `--expect-gone CYCLE-3` → ok `waited_ms=648 < 5000`；N29 `--expect-alive '^CYCLE-'` ok；N29b `--expect-alive NO-SUCH-NODE-XYZ` → rc=3 `ENV_EXPECT_FAILED`；N31 目标仍在时 `--expect-gone CYCLE` → rc=3 `ENV_EXPECT_FAILED`；N31b gone+alive、`--verify`+expect、坏 `--expect-timeout` 三种冲突 rc=2。
- 状态：✅ 通过（2026-10-24）

### C17 · 输入落点（v1.3）

- **判据**：焦点不可编辑 → rc=3 `ENV_NO_FOCUS` 且 `injected:false`；可读但值没变 → rc=3 `ENV_NO_EFFECT`（before==after、`pasteSettled:false`）；`--force` 越过两者并如实标 `forced:true`；`--verify` 与 `--force` 独立（forced 下 verify 仍报 `ENV_TEXT_NOT_ENTERED`）；dry-run 不跑焦点门；无 grant 仍 rc=4。
- 实测：m19 10/0 —— focus Button（`wa-btn`）→ `ENV_NO_FOCUS`、`focused.aid="wa-btn"`；只读编辑器（`wa-ro`）→ `ENV_NO_EFFECT`、before==after==`"\nreadonly"`、settleMs=900；`--force` → ok + `forced:true` + `pasteSettled:false`；可编辑 `wa-edit` 输入 hello → `pasteSettled:true`、值 hello、settleMs=0；`--verify exact` → `matched:true`；forced + verify → `ENV_TEXT_NOT_ENTERED`；dry-run → `dryRun:true`；无 grant rc=4；`--no-restore-clip` → `clipRestored:false`。
- 状态：✅ 通过（2026-10-25）

### C18 · 路径与正文（v1.3）

- **判据**：`wshot --out /tmp/x.png` → rc=0、文件存在、sha256 与 JSON 一致、`path` 为 Windows 落点、`wsl_path` 为入参路径；`ops/read-text --hwnd H` → `source:"uia"` 且 `chars>50`（网页），`--force-clip` 走剪贴板通道并还原剪贴板；`wwin focus --yes` → rc=0 且 `ignoredFlags:["--yes"]`（其余子命令仍 rc=2）；新旗标都出现在各自 `--help`。
- 实测：m20 11/0 —— `wshot --out /tmp/...` mapped:true、sha256 与 `sha256sum` 一致；`/mnt/c` 目标不中转；uiawnd `--read-text` `mode:"readtext"` chars=10；`ops/read-text` `source:"uia"`；`--no-fallback` 空文本 → rc=3 `ENV_NO_TEXT`；`--force-clip` → `source:"clip"`、文本逐字符一致、`clipRestored:true`、剪贴板回到哨兵值；`wwin focus --yes` 接受、`wwin info --yes` rc=2；无 grant 时 force-clip rc=4 而 UIA 读 rc=0；live Edge `--read-text` chars=173067。
- 状态：✅ 通过（2026-10-25）

### C19 · 真实站点冒烟（v1.3）

- **判据**：对已打开的真实浏览器（不重启、不切标签、不注入）只读冒烟：`--find-text` 有足够几何行、`--find-type Edit` 有结果、页面文本行中心 `--point` 命中（rect 含点）、暖树 `--find-name` ≤ 5 s；无浏览器时整份 SKIP、不判失败。
- 实测：m21 4/0（1 SKIP）—— 用户 Edge `0x90cdc`：`--find-text '.' --limit 120` total=174、几何行 120、`depth>=8` 行 88、2743 ms；`--find-type Edit` total=4；`--point 391,195` → `TabItem "对话"`、`via:"rect-hit"`、rect 含点；暖树 2162 ms；B 站断言因活动标签不是 B 站而 SKIP（不切标签）。
- 状态：✅ 通过（2026-10-25）
### F19 · 滚动容器与滚动状态（v1.4）

`bin/wuia --hwnd H --scroll-info [--point X,Y | --find-aid RE ...]`（全文见 `docs/24-v1.4-plan.md` §3）

- F19-1 命中可滚动容器：`scrollable:true`、`via` 为 `scroll-pattern`/`rect`、`container{name,type,rect,patterns}`、`scroll{percentY,viewHeight}`，rc=0。
- F19-2 命中不可滚动元素：`scrollable:false`、`container:null`，rc=0（不是错误）。
- F19-3 点空白：rc=3 `ENV_NO_HIT`。
- F19-4 `via` 如实：pattern 可用 → `scroll-pattern` 且 `percentY` 是数字；否则 `rect` 且 `percentY:null`，但 `container` 仍给最近裁剪祖先。

### F20 · reveal：滚到目标可见（v1.4）

`ops/reveal --hwnd H (--find-aid|--find-name|--find-text|--find-class) RE [--index N] [--steps 12] [--yes]`；`winput click --reveal …` 是它的点击一体形态。

- F20-1 目标在容器下方：`{ok,revealed:true,steps,moved,point,element,container,scroll{before,after},via}`，rc=0；`element.rect ⊆ container.rect`（±2px）；`point` 的 hit-test 命中该元素/后代/可点祖先。
- F20-2 幂等：再跑一次 `steps:0`、`moved:[]`，**不注入任何事件**。
- F20-3 目标不存在：rc=3 `ENV_NO_MATCH`、`steps:0`。
- F20-4 滚不动：rc=3 `ENV_SCROLL_NOT_MOVED`，带 `history`（含 `before/after`）与 `hoverTried:true`；不得谎报 revealed。
- F20-5 步数用尽：rc=3 `ENV_NOT_REVEALED`，带 `steps` 与 `history`。
- F20-6 dry-run：rc=0、`dryRun:true`、`plannedSteps`、**无** `revealed` 字段、不注入、不需要 input grant。
- F20-7 `winput click --reveal`：JSON 带 `reveal` 与一致的 `hit`；可与 `--expect-change` 同用；与 X Y / `--click-text` 同用或非 click → rc=2。

### F21 · 选择类控件（v1.4）

`ops/select-option --hwnd H --trigger RE --option RE [--expect-value RE] [--mode auto|panel|native] [--timeout 4000] [--yes]`

- F21-1 面板型：`{ok,mode:"panel",clicked,value{before,after},matches:true,closed:true,steps}`，rc=0。
- F21-2 原生弹层型（独立顶层 HWND，`GW_OWNER`= 主窗）：`mode:"native"`，JSON 回报 `popup{hwnd,title,class}`，点击走 `--allow-related` 语义。
- F21-3 选项不存在：rc=3 `ENV_NO_OPTION`、`steps:0`、`tried:["panel","native"]`，并用 Esc 关弹层（`closed` 如实）。
- F21-4 回读不符：rc=3 `ENV_NO_EFFECT`，带 `value.before/after`。
- F21-5 视口外选项：必须先 reveal 再点，`steps>=1`；直接点 raw rect 不算通过。

### F22 · 串行录入（v1.4）

- F22-1 `ops/chip-add`：`chipsBefore=k → chipsAfter=k+1`、`added==value`、无并字 chip。
- F22-2 输入被吞 → 自动重试一次（`retried:1`）且仍 `k+1`；两次失败 → rc=3 `ENV_CHIP_MISMATCH` 带 `chips`。
- F22-3 `ops/rich-write`：点入 + `ctrl+a` + 粘贴 + 回读，前缀比较 `matched:true`；不符 rc=3 `ENV_TEXT_NOT_ENTERED`。
- F22-4 `ops/wait-ready`：`{ok,polls,elapsedMs,matched{name,rect}}`；超时 rc=3 `ENV_TIMEOUT` 带 `lastCount`（0=没出现，>0=出现未布局）。

### S20 · 真实站点冒烟（v1.4）

真实 Edge、B 站投稿页、**零副作用**：S20-1 分区下拉 reveal 到可见后 Esc；S20-2 加一个测试标签再复原；S20-3 水印开关切两次回初值；S20-4 前后 `wwin list` 一致，不点提交类按钮。无 Edge/非投稿页 → 整份 SKIP（exit 0）。
### S10 · 默认行为不变

- **判据**：不传新开关时，`winput` 的匹配/校验行为、`wshot --rect` 语义、`ops/*` 输出（除新增字段）与 v1.1.0 一致。
- 实测：m1–m12 全部原判据在 v1.2 上仍全绿（m1 16/0 skip=15、m2 11/0、m3 20/0、m4 13/0、m5 6/0、m6 10/0、m7 9/0、m8 7/0、m9 8/0、m10 17/0、m11 19/0、m12 20/0）；`--allow-related`、`--verify`、`--expect-*` 全部**默认关**，C14-2/N7 专门断言默认严格不变。
- 状态：✅ 通过（2026-10-24）

### S11 · 只读边界

- **判据**：`ops/map` 只需 `scope=shot,uia`；`--text` 模式不产生截图文件。
- 实测：m15 N7 只签 `shot,uia` 时 map `ok:true`、同环境下 `winput click` rc=4 `GUARD_NO_GRANT`；N6 `--text` 前后 `shots/` 条目数不变。
- 状态：✅ 通过（2026-10-24）
## 里程碑 × 判据对照

| 里程碑 | 必须通过的判据 | 门槛 |
|---|---|---|
| **M1 只读** | E1–E7, C1(含 C1b), C2, C3 | 全绿才进 M2；任一红即停 |
| **M2 输入** | C4–C7 + S7（先建最小守卫） | C4 连续 10 次 10 中才算过 |
| **M3 守卫** | **S1–S8 全绿**（先于 M2 的能力判据通过亦可，但不许跳过） | 任一红即停 |
| **M4 组合** | C8 + E8 + 全部 E 族回归 | 端到端 3 次连过 ✅ 2026-10-21（13/0，E8 3/3） |
| **M5 收尾** | 全表回归 + SKILL.md 与实现一致 | ✅ 2026-10-21 冻结 v1.0.0（m1 17/0、m2 11/0、m3 20/0、m4 13/0、release yes、E8 10/10；冻结后补 E5 残留断言并复跑 7/0，E8 8156–8774 ms，
  单次入口 `bash tests/check-m5.sh`；报告 `tests/reports/2026-10-21-m5.md`） |

| **M8 v1.1** | E9–E12 + C9–C13 + S9 + E1–E8 回归 | ✅ 2026-10-24 冻结 v1.1.0（m1 16/0（skip=15：C3 最小化窗口 + 14 条非本里程碑占位）、m2 11/0、m3 20/0、m4 13/0、m5 6/0（含 E8 10/10）、m6 10/0、m7 9/0、m8 7/0、m9 7/0、m10 17/0、m11 14/0、m12 11/0、release pass=yes；报告 `tests/reports/2026-10-24-m8.md`） |
| **M10 v1.2** | E13–E15 + C14–C16 + S10–S11 + E1–E12 回归 | ✅ 2026-10-24 冻结 v1.2.0（m1 16/0（skip=15）、m2 11/0、m3 20/0、m4 13/0、m5 6/0（含 E8 10/10）、m6 10/0、m7 9/0、m8 7/0、m9 8/0、m10 17/0、m11 19/0、m12 20/0、m13 13/0、m14 10/0、m15 8/0、release pass=yes；报告 `tests/reports/2026-10-24-m9.md`） |
| **M11 v1.3** | E16–E18 + C17–C19 + E1–E15 回归 | ✅ 2026-10-25 冻结 v1.3.0（新判据 m16 10/0（1 SKIP）、m17 10/0（1 SKIP）、m18 10/0、m19 10/0、m20 11/0、m21 4/0（1 SKIP）；全表回归 m1 16/0（skip=15）、m2 11/0、m3 20/0、m4 13/0、m5 6/0（含 E8 10/10）、m6 10/0、m7 9/0、m8 7/0、m9 8/0、m10 17/0、m11 19/0、m12 20/0、m13 13/0、m14 10/0、m15 8/0、release pass=yes，共 **242 条断言通过 / 0 失败 / 18 SKIP**；报告 `tests/reports/2026-10-25-v1.3.md`） |
| **M12 v1.4** | F19–F22 + S20 + E1–E18 回归 | ✅ 2026-10-27 冻结 v1.4.0（新判据 m22 7/0、m23 8/0、m24 8/0、m25 10/0、m27 整套 SKIP rc=0（无可见投稿页，`reason:NO_BILIBILI_WINDOW`）；全表回归 m1 16/0（skip=15）、m2 11/0、m3 20/0、m4 13/0、m5 7/0（含 E8 10/10）、m6 10/0、m7 9/0、m8 7/0、m9 8/0、m10 17/0、m11 19/0、m12 20/0、m13 13/0、m14 10/0、m15 8/0、m16 10/0（1 SKIP）、m17 10/0（1 SKIP）、m18 10/0、m19 10/0、m20 11/0、m21 4/0（1 SKIP）、release pass=yes，共 **276 条断言通过 / 0 失败 / 18 SKIP**；报告 `tests/reports/2026-10-27-v1.4.md`） |
| **M9 网页语义** | 覆盖率报告（UIA 文本 / CDP innerText / 剪贴板基线） | 只出结论，不改主链路 |

## 验收记录规范

每次验收在 `tests/reports/YYYY-MM-DD-<milestone>.md` 落一份：

```markdown
# M1 验收 · 2026-10-XX
| 编号 | 期望 | 实测 | 状态 |
|---|---|---|---|
| E1 | 0 | 0 | ✅ |
...
结论：M1 通过 / 阻塞于 S3（理由）
```

**没有报告 = 未验收。** 报告本身也要提交进 git。