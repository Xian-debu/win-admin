# 17 · v2 升级计划（把绕路消灭在工具里）

> 依据：`docs/16-usage-feedback.md`（三会话取证：c0 手写 ShowWindow/hover、d2 25 轮剪贴板采集、fc 截图挪像素）。
> 冻结方式：判据先写死（§5），实施按 T1→T10 顺序，一步一提交、每步自带测试。

## 0 · 实施状态（2026-10-24 夜间执行完毕）

| 任务 | 状态 | 提交 | 验收 |
|---|---|---|---|
| T1 窗口状态 `wwin state/set` | ✅ 完成 | `5c87fbb` | m6 10/0 |
| T2 指针语义 `hover/wheel` | ✅ 完成 | `7740661` | m7 9/0 |
| T3 键盘 `--hold/keydown/keyup/releaseall` | ✅ 完成 | `38debdf` | m8 7/0 |
| T4 免引号输入 `--stdin/--text-b64` | ✅ 完成 | `38debdf`（与 T3 同一文件，合并提交） | m9 7/0 |
| T5 UIA 查找 | ✅ 完成 | `c4be8fc` | m10 17/0 |
| T6 UIA 动作 | ✅ 完成 | `c4be8fc` | m10 17/0 |
| T7 `ops/click-element` | ✅ 完成 | `79d3d3d` + 加固 `551ad50` + 网页加深 | m11 14/0 |
| T8 `ops/wait-uia` / `ops/hover-menu` | ✅ 完成 | `79d3d3d` | m11 13/0 |
| T9 `wshot --hwnd/--grid/sha256` | ✅ 完成 | `d3c9c8b` | m12 11/0 |
| T10 契约/文档/发布 | ✅ 完成 | 见 `CHANGELOG` 1.1.0 | `check-release.sh` pass=yes |
| T11 网页语义实验 | ✅ 完成（结论：网页读/写/点点**不需要 CDP**，UIA 够用；CDP 只用于自己起的受管实例） | 见 `docs/18` | 三通道覆盖率表 |

冻结结论：v1.1.0 发布于 2026-10-24；全表回归 m1 16/0 + 1 SKIP（C3，目标窗口最小化）、m2 11/0、m3 20/0、m4 13/0、m5 6/0（含 E8 10/10）、m6 10/0、m7 9/0、m8 7/0、m9 7/0、m10 17/0、m11 14/0（加 N27 auto-deepen）、m12 11/0；报告 `tests/reports/2026-10-24-m8.md`。

实施中的判据调整（都在 `docs/07` 保留原文，只追加实测）：

1. **C10 的判据从"element.rect 落在容器 rect 内"改成"element.rect 包含悬停点（±2 px）"**：UIA 报的元素矩形会溢出容器（m7 W3 实测右/下溢出 5–9 px），容器包含关系不是稳定判据。
2. **T2 的 N6 原计划"用 ScrollPattern 读回滚动位置"**：改用「滚动前后截图 sha256 不同 + 滚动条位置回读」双证，因为记事本的 ScrollPattern 在部分 DPU 下不可用。
3. **B 站二级分区菜单**未在 v1.1 强行支持：`ops/hover-menu` 只在自建夹具上验证；真实站点若二级项不进 UIA 树，按 `ENV_MENU_NOT_SHOWN` 报错并在报告写明（红线：不硬点）。

## 1. 目标（可判定）

1. **v1.0.0 有过的绕路，在 v1.1.0 里都变成一条命令**：窗口最大化、悬停展开二级菜单、滚轮、
   按控件名点击、有谓词地等待、免引号输入。
2. **每新增一个动作，都带"可判定性"**：不返回"我做了"，返回**回读到的状态**
   （rect/placement、落点元素、ValuePattern 值、元素出现/消失），延续 D27。
3. **不再有静默失败**：任何参数缺失/空文本/未知动作，都必须输出 JSON 且非零退出（缺口 F）。
4. **网页语义通道给出结论**：v1.1.0 末尾交付一份"能不能读网页结构"的实验报告，
   明确 v1.2.0 走 AX 树还是受管 CDP，还是继续剪贴板循环（缺口 G）。

## 2. 非目标（本轮明确不做）

- 不做 OCR（Windows 无 tesseract；`Windows.Media.Ocr` 需 WinRT 桥，另立里程碑）。
- 不做多显示器/混合 DPI 实测扩展（需改显示配置 = G3，留给用户在场时）。
- 不引入 Windows Python 包（pywin32/comtypes/uiautomation）——保持"只依赖 PowerShell 内置 UIA"（D2/G1）。
- 不做常驻进程/全局热键（D3/D12 不变）。
- 不改 v1.0.0 已冻结的 E/C/S 判据；新判据**追加**为 E9–E12 / C9–C13 / S9。

## 3. 任务分解（T = 一个提交单位）

### P1 · 窗口状态（缺口 A）——T1
- `wwin state --hwnd H` → `{placement, rect, minimized, maximized, topmost, visible}`（GetWindowPlacement + GetWindowRect + GetWindowLong）。
- `wwin set --hwnd H [--state max|restore|min|normal] [--x --y --w --h] [--topmost on|off]`。
- 校验：动作后回读并断言（`max` → `showCmd==3` 且 rect≈工作区；`move` → rect 与请求差 ≤2 px；否则 `ENV_STATE_UNCHANGED` exit 3）。
- 安全：`wwin set` 属输入类，需 grant `scope=input`；`--dry-run` 输出计划不执行。
- 测试 `tests/check-m6.sh`：N1 最大/还原往返、N2 move 到指定矩形、N3 topmost 开关、N4 无 grant 拒绝、N5 未知 hwnd → ENV_NO_WINDOW。

### P2 · 指针与键盘语义（缺口 B）——T2/T3
- `winput wheel --at X Y --delta N [--times N] [--horizontal]`（MOUSEEVENTF_WHEEL/HWHEEL，即 `win/winput.ps1` 里已半实现的 `wheel`）。
- `winput hover X Y [--steps N] [--dwell MS] [--expect-hwnd H]`：分段移动 → 驻留 → **返回落点元素**（UIA `ElementFromPoint` 的 name/type/aid/rect），让"浮层是否出现"可判定；`--dwell` 默认 600 ms。
- `winput key ... --hold MS`（长按后释放）、`winput keydown VK` / `keyup VK`（成对使用，退出时若仍按住则强制释放）。
- 测试：N6 wheel 改变滚动位置（用自建长文本窗口或记事本 + UIA ScrollPattern 读回）、N7 hover 返回元素非空且 rect 含落点、N8 hold 与 keydown/keyup 的 vks 回显、N9 未释放检测。

### P3 · 免引号输入（缺口 F）——T4
- `winput type --stdin`（读 stdin，UTF-8；空 → `ARG_EMPTY_TEXT` exit 2）。
- `bin/winput type --text` 保留但**空字符串必须报错**；新增 `--text-b64`（值走 base64，彻底免引号）。
- 文档与 SKILL 改口径：**默认教 `--stdin` / `--text-file`**，`--text` 只用于演示。
- 测试：N10 含半角单引号/双引号/反斜杠/`$()`/换行的文本经 `--stdin` 完整落进记事本（逐字节比对）。

### P4 · UIA 语义（缺口 C）——T5/T6
- `wuia --find`：`--name RE`、`--type RE`、`--aid RE`、`--class RE`、`--enabled`、`--onscreen`、`--index N`、`--limit N`、`--depth`；
  返回每个匹配节点的 `name/type/aid/class/rect/enabled/patterns[]`（patterns = 该节点实际支持的 Value/Invoke/SelectionItem/ExpandCollapse/Toggle/Text/ScrollItem）。
- `wuia --point X Y` → 该屏幕坐标下的元素（含祖先链），用于"悬停到了什么"。
- `wuia --invoke | --select | --toggle | --expand | --collapse | --focus | --set-value TEXT | --get-value`，
  用 `--index` 从 `--find` 结果里选；缺 Pattern 时 `ENV_NO_PATTERN`（带上下文：节点 name/type）。
- 测试：N11 自建 WinForms 测试窗（`C:/Users/Public/win-admin/win/wa-fixture.ps1`）里找按钮/输入框/下拉，
  N12 invoke 后计数变化、N13 set-value 后 get-value 回读一致、N14 不支持的 Pattern 正确报错。

### P5 · 复合操作（缺口 D/E）——T7/T8
- `ops/click-element --hwnd H --name RE [--type RE] [--index N] [--double] [--verify value:RE|gone:RE]`：
  find → 取 rect 中心 → `winput click --expect-hwnd` → 回读校验（默认校验焦点/元素仍存在）。
- `ops/wait-uia --hwnd H --name RE [--enabled] [--value RE] [--gone] [--timeout MS] [--interval MS]` 谓词等待。
- `ops/hover-menu --hwnd H --at X Y --dwell 800 --pick RE`：悬停 → 等 `--pick` 名字的元素出现 → 点它 → 校验。
- 测试：N15 click-element 命中且点击前后计数 +1、N16 wait-uia 300 ms 内命中、N17 超时返回 ENV_TIMEOUT、N18 hover-menu 在测试窗的可展开菜单上成功。

### P6 · 截图辅助（缺口 D）——T9
- `wshot --rect x,y,w,h` / `--hwnd H` / `--grid N`（画标尺网格与刻字）。返回 `{path, wsl_path, bytes, rect, sha256}`。
- 测试：N19 `--grid 100` 产出 PNG 尺寸不变、非网格像素不变（抽样），N20 `--hwnd` 尺寸 == 窗口 rect。

### P7 · 契约/文档/发布——T10
- `docs/04` 能力矩阵按实测重写；新增 K36–K40 到 `docs/11`；`docs/07` 追加 E9–E12/C9–C13/S9。
- SKILL.md → v1.1.0：新原语表、`--stdin` 口径、**替换 §11"hover 给不了"**为"hover + 可判定 + menu 链"配方、修 §`wuia --name` 漂移。
- `VERSION=1.1.0`、CHANGELOG、`scripts/build-release.sh` 重出 dist、`scripts/check-release.sh` 过、`tests/check-m6.sh` 并入总回归。

### P8 · 网页语义通道实验（缺口 G）——T11（研究，不改主链路）
- 实验 A：Edge 无障碍树。对已开的 Edge 窗口跑 `wuia --find --depth 12 --limit 4000`，记录节点数、是否含网页正文文本。
- 实验 B：受管 CDP。用 cdp-hub 的 `cdp_launch`（受管 profile）起一个 Edge，`Runtime.evaluate` 读 `document.body.innerText`，记录可行性与对登录态的要求。
- 产物：`docs/18-web-semantics-spike.md`（数据 + 结论 + v1.2.0 建议）。**不动的红线**：绝不把用户真实 Edge 重启、绝不改启动参数、绝不读 cookie。
- 判据：给出"读数覆盖率"量化（同一页面：UIA 文本节点字数 vs `document.body.innerText` 字数 vs 剪贴板循环字数）。

## 4. 顺序与依赖

```
T1(wwin)      ──┐
T2/T3(指针)   ──┼──► T5/T6(uia)──► T7/T8(ops)──► T9(wshot)──► T10(文档/发布)
T4(type)      ──┘                                   │
                                    T11(网页实验) ──┘（可与 T5 并行，独立目录）
```

T7 依赖 T5（find）与 T2（hover）；T10 必须最后做（VERSION/矩阵/技能一次性对齐）。

## 5. 新增验收判据（追加进 docs/07）

### E 族
- **E9 新原语契约一致**：每个新动作成功/失败都输出恰好一个 JSON；`ok:true` 必带回读字段；错误码 ∈ 既有枚举（新增 `ENV_STATE_UNCHANGED|ENV_NO_PATTERN|ENV_TIMEOUT|ARG_EMPTY_TEXT`）。
- **E10 失败必须响**：参数缺失/空文本/未知动作 → exit 2 + JSON（对 T4 专门测半角引号文本）。
- **E11 回读即证据**：`wwin set`、`--set-value`、`click-element` 的输出必须含动作后实测值，不是请求值。
- **E12 回归不倒退**：`check-m1..m5` 全绿，且 `check-release.sh` 静态守护仍过（无新增常驻/服务）。

### C 族
- **C9 窗口状态可控**：max→restore 往返后 rect 复原（±2 px）；move 到 (x,y,w,h) 后回读一致。
- **C10 悬停可判定**：`hover` 返回落点元素，且与 `--expect-hwnd` 一致；在可 hover 展开的菜单上，`hover-menu` 能点到二级项（用自建测试窗验证，不用真实 B 站）。
- **C11 元素级点击**：`click-element` 在测试窗命中 3/3，误点 0；对不可见/离屏元素必须拒绝（`ENV_ELEMENT_NOT_ACTIONABLE`）。
- **C12 谓词等待**：`wait-uia` 在元素出现后 ≤300 ms 返回；超时按 `--timeout` 准确返回 `ENV_TIMEOUT`。
- **C13 免引号输入**：含 `' " \\ $( )` 与换行的文本经 `--stdin` 后逐字节一致。

### S 族
- **S9 新动作同样受守卫**：`wwin set`、`wuia --invoke/--set-value`、`click-element` 在无 grant 时一律 rc=4 `GUARD_NO_GRANT`；审计各记一条。

## 6. 风险与处置

| 风险 | 处置 |
|---|---|
| 新动作扩大输入面（`wwin set` 能改任何窗口） | 一律要求 `--hwnd` 显式给出 + `--dry-run` 先看计划 + 审计记 rect 前后值；不提供"按标题模糊改窗"的批量入口 |
| `--invoke` 可能触发不可逆业务动作（下单/删除） | 文档写明"危险动作仍走坐标点击 + 人工可见"，`--invoke` 只用于导航/切换类控件；`ops/click-element` 默认不点 "删除/购买/提交" 字样的节点（`--allow-danger` 才点） |
| hover 在 Chromium 上可能因合成器延迟失败 | 用 `--dwell` 可调 + 返回落点元素做判据；失败就明确写"不可达"，不硬凑 |
| 改 `win/*.ps1` 不 bootstrap 的老坑（K28） | 每个 T 提交后立即 `scripts/bootstrap.sh --force`，测试脚本开头断言 `wdiag.version == VERSION` |
| 夜间屏幕锁定导致 GUI 用例失败 | 按既有纪律：锁屏 → GUI 用例 SKIP 并记录，不绕过 |

## 7. 时间预算（夜间自主执行）

| 阶段 | 预算 | 产物 |
|---|---|---|
| P0 规划（本文 + 16 + 判据 + 自授权清单） | 30 min | 3 个提交 |
| P1 wwin 状态 | 45 min | 代码 + check-m6 N1–N5 + 报告 |
| P2 指针/key | 60 min | 代码 + N6–N9 |
| P3 type 安全 | 30 min | 代码 + N10 |
| P4 UIA 语义 | 75 min | 代码 + fixture + N11–N14 |
| P5 ops | 45 min | 代码 + N15–N18 |
| P6 wshot | 30 min | 代码 + N19–N20 |
| P7 文档/发布 | 45 min | 矩阵/K/技能/CHANGELOG/dist |
| P8 网页实验 | 40 min | docs/18 |

超时处置：某阶段超预算 1.5 倍则**先提交可用部分 + 写清未完成原因**，不硬撑（五次失败即停止）。

## 8. 回滚

- 每个 T 一个提交，回滚 = `git revert <sha>`；`VERSION` 只在 T10 提升，之前保持 1.0.0 以免载荷版本混淆。
- 新增 `win/*.ps1` 分支不改既有动作语义（只加 switch 分支），旧调用行为不变。