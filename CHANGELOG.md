# Changelog

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循语义化版本。首个正式版在 M5 冻结为 1.0.0；此前 0.x 不承诺接口稳定。

## [1.3.0] - 2026-10-25

主题：**把「能点」推进到「知道点到了什么」**。依据 `session-c022d2c2`（v1.2.0 的第一次实战：B 站投稿草稿）的 7 条取证（`docs/21`），按 `docs/22` 的冻结判据实施 T20–T26。

### Added
- **点击有回报**：每次 `winput click` 在注入**之前**用几何反查落点元素的 `hit{name,type,aid,class,rect,depth,actionable,hwnd,clickable,raw}`；未命中给 `hit:null` + `hitReason`。语义是「a11y 认为这里是什么」，不是像素断言。
- **点击有后果断言**：`click --expect-change title|rect [--timeout MS]` 轮询读窗口状态，超时给 `ENV_NO_EFFECT` rc=3 并附 `before/after/observed/elapsedMs`（不是静默 ok）。
- **按文本点**：`wuia --find-text RE` 给出「文本行 + rect + depth」清单（按 y 升序）；`winput click --click-text RE [--text-index N]` 直接点第 N 行的中心。
- **几何命中**：`wuia --point X,Y --point-mode auto|rect|uia` —— FromPoint 命中容器或空时，用暖树做 rect-hit 回退，`via` 明确写 `uia-point` 或 `rect-hit`；空白点 `ENV_NO_HIT` rc=3。
- **正文一条命令**：`ops/read-text --hwnd|--title [--no-fallback|--force-clip]`，UIA TextPattern 优先、剪贴板兜底并还原，`source:"uia"|"clip"`。真实 Edge 一次取回 156–173 KB。
- **输入落点契约**：`type` 出现焦点不可编辑 → `ENV_NO_FOCUS`（`injected:false`，附 `focused`/`reason`）；粘贴未落地 → `ENV_NO_EFFECT`（`pasteSettled:false`）；`--force` 是显式逃生口并回显 `forced:true`。
- `wuia` 冷暖树策略：默认 depth find 20 / tree 3，落空自动加深到 28 并短暂重试，输出 `passes/warmMs/warmRetries/depthUsed/deepened`；`--no-warm/--no-deepen/--warm-ms/--warm-passes` 可关。
- `wshot --out` 接受 WSL 路径（`/tmp/x.png`），非 `/mnt` 目标自动中转并回显 `mapped`/`windows_tmp`/`wsl_path`；`wwin focus --yes` 接受多余 `--yes` 并标 `ignoredFlags`。
- 新夹具 `tests/helpers/deepwin.ps1`（22 层 + `-Lazy` 深树）与 `tests/helpers/uiawnd.ps1` 增只读编辑器 `wa-ro`；验收 `check-m16.sh`–`check-m21.sh`；判据 E16–E18 / C17–C19 追加进 `docs/07`；`docs/21`（c022 取证）、`docs/22`（计划与冻结判据）。

### Changed
- `ops/click-element` 坐标路径在注入前做 hit-test：落点属于别的窗口 → `ENV_HIT_MISMATCH` rc=3 且不注入；`--strategy click` 归一为 `coords`。
- `wuia` 的 `--point` 现在区分「legacy 无目标」与「带 `--hwnd/--title` 的几何命中」；`hover/wheel` 额外回原始 `underUia`。
- `SKILL.md` → v1.3.0（`--find-text/--read-text/--click-text/--expect-change`、命中语义、坑表 6 行）；`docs/04` 增 §10；`docs/11` 增 K62–K70。

### Fixed
- **冷进程首查只拿到 chrome**：Chromium 的 a11y 树异步生长，v1.2 的首查 279 节点里没有页面内容，用户以为「工具读不到网页」——现在默认预热+自动加深（`K62`/`K63`/`K64`）。
- **点完不知道点到哪**：v1.2 只会 `ok:true`，实战里三次点空全靠人肉核对截图。
- **真实正文取不回来**：`--arg` 传 156 KB 文本撞 `ARG_MAX`，`--argjson 0x…` 直接解析失败（K69）。
- **焦点不对也往上打**：v1.2 的 `type` 只看 `hwnd` 匹配，落在按钮/只读框上仍报成功（K66 类），现在先判焦点（K65 收口）。
- `wwin focus` 偶发 `ENV_NOT_FOREGROUND` 的真因是探针控制台抢前台（K67），不是目标窗口拒绝。

### Measured
- m16 10/0（1 SKIP live）、m17 10/0（1 SKIP live）、m18 10/0、m19 10/0、m20 11/0、m21 4/0（1 SKIP：活动标签非 B 站）。
- 真实 Edge（`0x90cdc`）：冷进程首查 542 节点 / depth 20 / 1545 ms；`ops/read-text` 173067 字符；`--find-text . --limit 120` total=174 / 几何 120 行 / 2743 ms；暖树 `--find-name .` 2162 ms。
- `click --expect-change title` 实测 50–64 ms 内判定改标题；点空白 1000 ms 超时 `ENV_NO_EFFECT`（elapsedMs 1086）。
- 全表回归：m1 16/0（skip=15）、m2 11/0、m3 20/0、m4 13/0、m5 6/0（含 E8 10/10）、m6 10/0、m7 9/0、m8 7/0、m9 8/0、m10 17/0、m11 19/0、m12 20/0、m13 13/0、m14 10/0、m15 8/0、m16 10/0（skip=1）、m17 10/0（skip=1）、m18 10/0、m19 10/0、m20 11/0、m21 4/0（skip=1）、`check-release.sh` pass=yes；共 **242 条断言通过 / 0 失败 / 18 SKIP**（回归首轮曾 4 个套件红：release 的 UTF-8 窗口不足、hover `under` 契约被破坏、`--find-class` 正则误命中、两条旧断言撞上新焦点门；修法与判据修正见 `tests/reports/2026-10-25-v1.3.md` §4 与 `docs/22` §5.1 第 18–20 条）。
- 报告：`tests/reports/2026-10-25-v1.3.md`（含 m16–m21 分报告）。

## [1.2.0] - 2026-10-24

主题：**把「命令有了」推进到「命令可信」**。依据 `session-4f961713`（v1.1.0 的第一次实战：B 站投稿）逐条取证（`docs/19`：8 条反馈 → 6 个缺口 G1–G6），按 `docs/20` 的冻结判据实施 T12–T19。

### Added
- `wwin`/`ops/*` 的**状态无副作用**保证：聚焦只改前台，不改 placement；`Set-WaForeground` 只在窗口最小化时才 `SW_RESTORE`，最大化窗口 focus 后仍是最大化（判据 `GetWindowPlacement().showCmd`）。复合操作成功 JSON 增 `statePreserved:true`。
- `winput --allow-related` 与全部注入类 ops 的同名开关：目标与命中窗口互为祖先/后代（「文件名无效」这类子对话框）时放行并标 `matched:"related"`；mismatch 的 JSON 增 `hit:{hwnd,title,class,pid,rect}`，msg 直接说出「挡在前面的是谁」。**默认关**，默认仍严格相等。
- `winput type --verify [--verify-mode exact|contains]`：动作后读焦点元素的 Value/Text pattern 回读比对，不符 `ENV_TEXT_NOT_ENTERED` rc=3、读不到 `ENV_TEXT_UNVERIFIABLE` rc=3；JSON 带 `verify{focused,hwnd,value,matched,mode}`。`--text-file` 现在接受 WSL 路径/相对路径（bash 侧读入并转存），路径不存在 `ARG_TEXT_FILE_NOT_FOUND` 与内容为空 `ARG_EMPTY_TEXT` **分开报**。
- `wclip set --native-path`：`/mnt/c/a/b` → `C:\a\b`，原生文件对话框的斜杠问题不再靠记（与 `--text/--text-file` 互斥）。
- `wshot --box X1,Y1,X2,Y2`（左上/右下）与 `--clip`（越界裁剪）；JSON 增 `scale`（dpi/96，本机 1.5）、`rect`、`image{w,h}`、`requested`、`clipped`；越界 msg 附 `--clip` 与 `--box` 两条改法；`--rect` 形态错误改报 `ARG_BAD_RECT` rc=2（不再静默 `unknown arg`）。
- `ops/map`：一次 UIA 枚举给出「编号 + 能点的 rect + 可操作性」清单，并可选在截图上画红框编号图（`win/wannotate.ps1`）——把「看图猜坐标」变成「按编号点」。只读，只需 `--scope shot,uia`；`--text` 零截图。
- `ops/click-element --expect-gone NAME | --expect-alive NAME [--expect-timeout MS]`：把「点完界面该变成什么样」写进命令，不成立 `ENV_EXPECT_FAILED` rc=3，成功 JSON 增 `expect{gone|alive|value,waited_ms}` 与 `waited_ms`。
- 新夹具 `tests/helpers/dialogwin.ps1`（主窗 + Owner 子对话框 + 无关窗）；验收 `check-m13.sh`（13 项）、`check-m14.sh`（10 项）、`check-m15.sh`（8 项）。判据 E13–E15 / C14–C16 / S10–S11 追加进 `docs/07`。
- `docs/19`（4f 会话取证）、`docs/20`（v1.2 计划 + 判据 + §0.1 实施中对判据的修正）。

### Changed
- `tests/check-m11.sh` 扩到 19 项（N28–N31b）、`tests/check-m12.sh` 扩到 20 项（N30–N38）。
- `SKILL.md` → v1.2.0：`ops/map` 用法、`--expect-*` 配方、`--allow-related` 边界、`--native-path`、「看图点坐标」三条新坑。
- `docs/11` 增 K49–K56（`--find-name .` 漏空名、GDI+ 锁图、`SW_RESTORE` 改状态、WPF Owner 赋值顺序、DIP≠物理像素、`grep -c || echo 0`、长脚本生成、`old_string` 缩进）。
- `docs/04` 增 §9「v1.2 语义层补强」；`docs/17` 顶部指向 `docs/20`。

### Fixed
- **窗口自己从最大化变回窗口化**：`Set-WaForeground` 无条件 `ShowWindow(SW_RESTORE)`，对最大化窗口等于「还原」（K51）。4f 会话里两次 `hover-menu` 失败后坐标全失效就是它干的。
- `type --text-file` 传 WSL 路径报 `ARG_EMPTY_TEXT`（读不到与空内容混为一谈）。
- `ops/map`/`wannotate` 首版 `Image.FromFile` 锁图导致 `Save` 报 GDI+ 一般性错误（K50）。

### Measured
- m1 16/0（skip=15）、m2 11/0、m3 20/0、m4 13/0、m5 6/0（含 E8 10/10）、m6 10/0、m7 9/0、m8 7/0、m9 7/0、m10 17/0、m11 19/0、m12 20/0、m13 13/0、m14 10/0、m15 8/0、`check-release.sh` pass=yes。
- 状态保全实测：最大化窗口 focus 前后 `showCmd=3`、rect 逐值不变；`--expect-gone CYCLE-3` 648 ms 返回；`ops/map` 在 780×930 夹具上 21 节点 / 9 可操作 / 编号 0..20 严格按 (y,x)。
- 报告：`tests/reports/2026-10-24-m9.md`。
## [1.1.0] - 2026-10-24

主题：**把 v1.0.0 的绕路变成一条命令**。依据三份真实会话取证（`docs/16`），逐条对照实施（`docs/17`）：T1–T9 落地，T10 文档/契约/发布，T11 网页语义实验见 `docs/18`。

### Added
- `wwin state` / `wwin set`：窗口状态可控（max/restore/min/normal、移动缩放、topmost），判据是回读的 `GetWindowPlacement`（最大化窗口的 `GetWindowRect` 是负偏移，几何判不出来），输出 `before/after` 两份实测状态；不符即 `ENV_STATE_UNCHANGED` rc=3。
- `winput hover X Y [--dwell MS]`：分段移动 + 驻留，返回**落点元素**（UIA `ElementFromPoint`），让「浮层出没出来」可判定；`winput wheel`（垂直/水平）、`winput key --hold`、`keydown/keyup/releaseall` 与 `held.json` 未释放检测。
- `winput type --stdin` / `--text-b64` / `--text-file`：彻底免引号；空文本报 `ARG_EMPTY_TEXT` rc=2（v1.0 是静默失败）。
- `wuia` 语义层：`--find-name/--find-type/--find-aid/--find-class/--enabled/--on-screen/--index/--limit`，`--point X,Y` 问「光标下是什么」，动作 `--invoke/--select/--toggle/--expand/--collapse/--focus/--get-value/--get-text/--set-value`，每个动作返回**动作后的回读状态**；禁用元素 `ENV_DISABLED`，缺 Pattern `ENV_NO_PATTERN`。
- `ops/click-element`（语义动作 + 必备校验 + invoke/click 双策略）、`ops/wait-uia`（谓词等待）、`ops/hover-menu`（悬停展开 → 按 UIA 名字点二级项，失败 `ENV_MENU_NOT_SHOWN`）。
- `wshot --hwnd H`（窗口矩形截图）、`--grid N`（标尺网格 + 绝对坐标刻字）、JSON 增 `sha256`。
- 新夹具：`tests/helpers/menutwin.ps1`（hover 才显形菜单）、`tests/helpers/uiawnd.ps1`（UIA 控件窗，含计数按钮、内容自变的 CYCLE 按钮、禁用按钮、危险名按钮「删除」、下拉、列表）、`tests/helpers/imgcmp.ps1`。
- 验收：`check-m6.sh`（窗口状态 N1–N10）、`check-m7.sh`（悬停/滚轮）、`check-m8.sh`（键盘长按/held）、`check-m9.sh`（免引号输入）、`check-m10.sh`（UIA find/act 17 项）、`check-m11.sh`（ops 13 项）、`check-m12.sh`（截图 hwnd/grid/sha 11 项）。判据 E9–E12 / C9–C13 / S9 追加进 `docs/07`。

### Changed
- `ops/click-element` 对名字含 `删除|购买|提交|支付|下单|格式化|reset` 的节点**默认拒绝**（`ENV_DANGEROUS_ACTION` rc=3），`--allow-danger` 才动手；禁用/离屏元素报 `ENV_ELEMENT_NOT_ACTIONABLE`（不再混进「找不到」）。
- `ops/click-element` / `ops/wait-uia` 默认深度失手时**自动加深一次**（10/3000 → 16/8000）并在 JSON 标 `deepened`：网页内容在 a11y 树 depth 12–13，旧默认值会把「搜得不够深」误报成「页面里没有」。`wait-uia --gone` 同样受益（浅搜「看不见」不再被当成「已消失」）。
- `SKILL.md` → v1.1.0：新原语表、`--stdin` 口径、投稿长表单配方（替换 v1.0 的「hover 给不了」结论）、新增「中文 .ps1 必须 BOM」等坑。
- `docs/04` 能力矩阵按实测重写 L3/L4 与新增 §8 语义层；`docs/11` 增 K36–K46；`docs/07` 增 M8 验收记录；`SKILL.md` §8 改写为「正文走 TextPattern、网页元素在 depth 12–13、异步 a11y 要轮询」。
- `docs/18` 新增：网页语义通道实验（三通道覆盖率/延迟对照、页面元素动作实测、异步 a11y 观测、v1.2 建议）。结论：网页读/写/点**不需要 CDP**。

### Fixed
- `wuia` 的 find 分支缺 `-not $Action` 条件，导致「find 条件 + 动作」总是提前 exit 0，动作从未执行（K40）。
- `wuia` 对 TextBlock 的 `--get-text` 回落到 `Name`（WPF 不给 TextPattern，K38）。
- `tests/check-m1.sh` 的 C3 对最小化窗口改判 SKIP：UIA 矩形为 null 时没有可比几何（K36）。
- `tests/check-m10.sh` 混入一个 NUL 字节导致工具判定为二进制文件，已清除。
- 夹具 `uiawnd.ps1` 存成无 BOM UTF-8，PowerShell 5.1 按 ANSI 读，中文按钮名变乱码（K39）。

### Measured
- 夜间全表：m1 16/0（skip=15：C3 最小化窗口 + 14 条非本里程碑占位）、m2 11/0、m3 20/0、m4 13/0、m5 6/0（含 E8 10/10）、m6 10/0、m7 9/0、m8 7/0、m9 7/0、m10 17/0、m11 14/0、m12 11/0。
- 网页三通道（同一页面）：CDP innerText 316 字符/0.11 s；UIA TextPattern 347 字符/1.50 s；剪贴板 353 字符/2.00 s。UIA 默认深度 10 命中率 0，depth 16 命中。
- 单次原语仍是 600–750 ms；`ops/` 把多步压进一次调用（click-element 一次 ≈ 1.3 s）。
- `check-release.sh` pass=yes；`dist/` 重出 tar.gz + zip + SHA256SUMS。

## [1.0.0] - 2026-10-21

首个正式版：**在授权窗口内操作 Windows 桌面**的能力包冻结。

### Added
- `tests/check-m5.sh`：全表回归入口（m1..m4 + release + E8 十轮），`--only-a` / `--only-b` 可单独重跑。
- `tests/helpers/e2e.sh`：端到端单轮（open → fill → ctrl+s → 字节比对 → close）供 m4/m5 共用。
- `docs/12-retro.md`：九个翻车点按代价排序 + 三个关键判断 + 明确没做的事。

### Fixed
- E1 提交前缀白名单缺 `ops`（全表回归第一枪就红）；`docs/08` 的 type 表补 `ops`/`release`/`auth`。
- `win/waopen.ps1` 缺首行 `OutputEncoding`，`check-release` 第 3 项红。
- `jq '.desktop.secured // true'` 把 `false` 当空值 → 解锁被误判锁屏，E8 连两次 SKIP（K32）。
- 测试套件清理逻辑按 `HAD_GRANT` 分叉，备份缺失时静默留下有效令牌（K34）；`check-m4.sh` 的 N1 复用同一备份槽，吃掉自己签发的令牌（K35）。
- `check-m5.sh` 新增 E5 残留断言：跑前无令牌、跑后必须仍无令牌，否则 FAIL 并撤销。

### Measured
- 全表：m1 17/0、m2 11/0、m3 20/0、m4 13/0、release pass=yes（合计 61 项断言）。
- E8 十轮：8185–8288 ms 全绿；另一次独立十轮跑 8158–8289 ms（极差 ≤131 ms）。
- 单次 `bash tests/check-m5.sh` → `SUMMARY pass=6 fail=0 skip=0`。
- 冻结后复跑（A 段增 E5）→ `SUMMARY pass=7 fail=0 skip=0`；E8 十轮 8156–8774 ms。

## [0.3.0] - 2026-10-21

### Added
- 复合操作层 `ops/`：`open`（启动并等窗口）、`find-and-click`（UIA 语义定位 + 点击中心）、
  `fill`（点击 + 全选 + 粘贴 + UIA 读回校验）、`wait-for`（等窗口或等 UIA 控件）。
  全部默认 dry-run，`--yes` 才注入；全部过 guard 并写审计。
- `win/waopen.ps1`：启动程序并等窗口（进程 pid 或标题匹配），单次桥调用完成。
- `wwin focus`（双线程 attach 抢前台，不产生合成输入）/ `wwin close`（PostMessage WM_CLOSE，脏文档交给应用）。
- `SKILL.md`（L4 技能：红线 / 授权 / 原语表 / 五步配方 / 坑表 / 拒绝条件）+ `scripts/install-skill.sh`。
- 验收 `tests/check-m4.sh`（13 项：N1-N6 阴性 + C8-1…C8-6 + E8 三连跑），报告 `tests/reports/2026-10-21-m4.md`。

### Fixed
- `jq --argjson` 不接受 `0x` hwnd（K25）；`$(op_resolve_hwnd)` 吞掉错误 JSON（K26）；
  `waopen.ps1` 缺 `Fail` 导致无 JSON 输出（补本地 Fail + trap，坏程序现在 `ENV_NO_EXE` rc3）。

### Measured
- `ops/open` 564 ms 返回 hwnd；`ops/wait-for --uia-name` 606 ms 命中；
- `ops/fill` 48 字节中文+emoji 读回逐字节一致；端到端（含落盘与关窗）8.2–9.0 s，3/3 连过。

## [0.2.0] - 2026-10-21

### Added
- M2 输入原语：`winput`（move/click/dclick/drag/key/type，默认 dry-run，真实注入需 `--yes`）、
  `wclip`（get/set/clear，写后回读校验）、`wwait`（窗口出现轮询）、`wuia --value`（回读控件内容）、`wwin info`。
- M3 守卫层：`guard/grant.sh`（issue/status/revoke/pause/resume）、`guard/check.sh`（scope/过期/撤销/pause/验签）、
  `lib/audit.sh`（一行一动作，写失败 fail closed）、`grant.json` 签名（`GUARD_TAMPERED`）。
- 拒绝码：`SESSION_LOCKED`、`UAC_SECURE_DESKTOP`；只能更严格的桌面测试钩子（SG-0002）。
- 验收：`tests/check-m2.sh`（11 项）、`tests/check-m3.sh`（20 项）、自带 WPF 测试窗、`pixdiff.py`。

### Fixed
- `Out-Plan | Out-Null` 吞掉 dry-run JSON（K15）；`-split '+'` 的正则转义错误；
- 事件处理器看不到外层局部变量（改 `$script:`，K16）；`$env:WA_VERSION` 设置顺序导致错误 JSON 报 unknown；
- guard 拒绝路径绕过审计（K20）。