# Changelog

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循语义化版本。首个正式版在 M5 冻结为 1.0.0；此前 0.x 不承诺接口稳定。

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