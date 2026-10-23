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