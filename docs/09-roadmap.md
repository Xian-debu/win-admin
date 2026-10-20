# 09 · 路线图与里程碑

> 每个里程碑都绑定 `docs/07` 的判据编号，**判据未全绿不得进入下一阶段**。
> 时间估算是“专注工作时长”，不含等待用户回复。
> 2026-10-21 起新增 **M0.5 部署包**：用户要求“工程化管理，方便发布、迁移、复现、回退”，
> 因此部署工程与功能实现并行推进，且每完成一块即验证即提交。

## 总览

| 里程碑 | 主题 | 交付物 | 门槛判据 | 估算 | 状态 |
|---|---|---|---|---|---|
| **M0** | 文档与骨架 | AGENTS.md、docs/01–09、仓库结构 | E1 | — | ✅ 2026-10-20 |
| **M0.5** | 部署包工程 | 双包布局、VERSION、bootstrap/rollback/uninstall、发布构建 | E9–E12（见 §M0.5） | 3–4h | 🚧 进行中 |
| **M1** | 只读：看得见、认得准 | `wshot` `wuia` `wwin(list)` `wdiag` | E1–E7, C1(+C1b), C2, C3 | 4–6h | 🚧 已授权，进行中 |
| **M2** | 输入：点得中、打得进 | `winput` `wclip` `wwin(focus/layout)` + DPI 校准 | C4–C7, S7 | 6–10h | ☐ |
| **M3** | 守卫：授权、急停、审计 | `guard/`（grant/pause/audit/preflight） | **S1–S8 全绿** | 4–6h | ☐ |
| **M4** | 组合与技能 | `ops/` + `SKILL.md` + 端到端用例 | C8, E8, E 族回归 | 5–8h | ☐ |
| **M5** | 稳定化 | 回归、文档定稿、性能打磨 | 全表回归 + 报告 | 2–3h | ☐ |
| **M6** | 发布 | 打 tag、GitHub Release、迁移说明 | 干净机器复演一次 | 1–2h | ☐ |

## M0 · 文档与骨架（已完成）

- 目的、环境、插件审计、能力矩阵、架构、决策、验收、规范、路线图九份 + AGENTS.md + README。
- **不做任何探测性代码**，只清点不动刀。

## M0.5 · 部署包工程（2026-10-21 起）

### 为什么是“两个包”

WSL 与 Windows 是两个隔离的执行环境，**仓库在 WSL ext4 上，Windows 的 PowerShell 根本看不见它**
（`powershell.exe` 只能读 `/mnt/c` 及 Windows 盘符下的文件）。所以拆成两个可独立发布/安装的包：

| 包 | 内容 | 装到哪 | 谁调用 |
|---|---|---|---|
| **P1 `win-admin`（WSL 侧）** | `bin/` `guard/` `lib/` `tests/` `docs/` | 任意 WSL 路径（当前 `/root/win-admin`） | 我（DSH agent）在 WSL 里执行 |
| **P2 `win-admin-win`（Windows 侧载荷）** | `win/` 下的 `.ps1` + `lib/wa-core.ps1` | `C:/Users/Public/win-admin/app/<version>/` | `winps` 转交 `powershell.exe` |

P2 **零依赖、零安装器、零常驻**：只有被调用的瞬间存在，调用结束即无进程。
P1 通过 `current.txt` 找到 P2 的活动版本，因此升级/回滚都是**改一个指针**，不删文件。

### 工作项

| # | 工作 | 产出 | 判据 |
|---|---|---|---|
| 0.5.1 | 双包目录与 `VERSION`、`LICENSE`、`THIRD_PARTY_NOTICES`、`CHANGELOG` | 仓库结构 | E9 |
| 0.5.2 | `scripts/bootstrap.sh`：环境体检 → 拷贝载荷 → 校验哈希 → 写 `current.txt` → 冒烟 | 脚本 | E10 |
| 0.5.3 | `scripts/rollback.sh` / `scripts/uninstall.sh`：指针回退 / 彻底卸载 | 脚本 | E11 |
| 0.5.4 | `scripts/build-release.sh`：可复现归档 + `SHA256SUMS` | 发布物 | E12 |
| 0.5.5 | `docs/10-deployment.md` + `docs/11-known-issues.md` | 文档 | E9 |
| 0.5.6 | 在**干净目录**复演一次安装→冒烟→回滚→卸载 | 报告 | E12 |

### 判据（本阶段新增，追加进 docs/07）

| 编号 | 判据 | 命令 | 期望 |
|---|---|---|---|
| **E9** | 部署相关文件齐全、版本单一真源 | `bash scripts/check-release.sh` | PASS，且 `VERSION` 与 `CHANGELOG` 首条一致 |
| **E10** | 一条命令装好并冒烟通过 | `bash scripts/bootstrap.sh` | 退出 0，末尾 `SMOKE PASS` |
| **E11** | 回滚与卸载可逆 | `scripts/rollback.sh --previous` 后 `wdiag.v` 变化；`uninstall.sh --yes` 后目录不存在 | 两条都成立 |
| **E12** | 发布物可复现 | 连续两次 `build-release.sh` | 两个 `SHA256SUMS` 逐行一致 |

## M1 · 只读（已授权，进行中）

### 目标

在不注入任何输入的前提下，证明三件事：

1. 截到的图**是**物理像素的屏幕（C1）；
2. 能从 UIA 语义树里**精确**找到窗口与控件（C2）；
3. UIA 给的 rect 与截图**对得上**（C3，误差 ≤2px）。

### 工作项

| # | 工作 | 产出 | 备注 |
|---|---|---|---|
| 1.1 | `lib/common.sh`：定位 P2、统一 exit code、JSON 校验 | 库 | 所有原语共用 |
| 1.2 | `wdiag` 前置体检（锁屏/前台/DPI/session/guard/pause） | 原语 | 锁屏探测走 `OpenInputDesktop` |
| 1.3 | `wshot`（DPI aware、全屏/区域） | 原语 | 校验 2560×1600 |
| 1.4 | `wuia`（窗口枚举 + 树 + 深度/名称过滤 + JSON） | 原语 | 中文编码在 P2 首行解决 |
| 1.5 | `wwin list` | 原语 | 与 C2 的 hwnd 对照 |
| 1.6 | Q1 复跑：截图读字，确认视觉通道 | 结论 | M0 已预验通过 |
| 1.7 | `tests/check-m1.sh` + 报告 | 报告 | 填 E1–E7/C1–C3 实测列 |

### 风险

- `wuia` 输出体积爆炸（Edge 数千节点）→ 默认 `--depth 3` + `--filter`，并限制最大节点数。
- 中文乱码若修不掉 → 退回“全部输出英文 key + 名称 base64”，但这是下策。
- UIA 树遍历慢（>3s）→ 先按 hwnd 取 `ElementFromHandle`，不遍历全桌面。

## M2 · 输入（M1 全绿后）

| # | 工作 | 产出 |
|---|---|---|
| 2.1 | DPI 校准闭环：截图点十字 → 点击 → 复截比对 | `tests/dpi-calib.sh` |
| 2.2 | `winput` 基础：`move/click/dclick/drag`（绝对坐标，步进拖拽） | 原语 |
| 2.3 | `wclip`：中文输入主通道 | 原语 |
| 2.4 | `winput key/type`（组合键 + 剪贴板粘贴） | 原语 |
| 2.5 | `wwin focus/layout/state` + 前台锁校验 | 原语 |
| 2.6 | `winput --dry-run`（安全阀） | 特性 |
| 2.7 | 复测技能库三条结论（SetCursorPos / mouse_event / 相对移动） | 结论进 `docs/04` |

风险：**前台锁**（Windows 拒绝后台进程抢焦点 → `AttachThreadInput`/`SetForegroundWindow` 重试策略）；
IME 吃键 → 一律走剪贴板，不做逐字 `SendKeys`。

## M3 · 守卫（可与 M2 并行，但**必须**在 M4 之前全绿）

| # | 工作 | 产出 |
|---|---|---|
| 3.1 | `guard/grant.sh`（签发/撤销/查看） | 脚本 |
| 3.2 | `guard/check.sh`（被所有写操作调用：scope/过期/pause） | 脚本 |
| 3.3 | 审计写入（`audit/*.jsonl`，一行一动作） | 库 |
| 3.4 | 锁屏检测（`OpenInputDesktop` / `WTSQuerySessionInformation`） | 原语内建 |
| 3.5 | UAC 检测（`Consent.exe` / 安全桌面） | 原语内建 |
| 3.6 | （已定：不做）F12 常驻急停 → 改用软急停 `pause.flag`，D7 已改 | — |
| 3.7 | S1–S8 验收报告 | 报告 |

风险：锁屏检测方法可能因 Win11 版本不同而失效 → 必须构造真实锁屏场景验证（S3），不许“读文档认为可行”。

## M4 · 组合与技能

| # | 工作 | 产出 |
|---|---|---|
| 4.1 | `ops/open` `ops/find-and-click` `ops/fill` `ops/wait-for` | 脚本 |
| 4.2 | `SKILL.md`（何时拒绝 / 五步配方 / 退出码解读） | 技能 |
| 4.3 | 端到端用例：记事本写中文另存（C8） | 测试 |
| 4.4 | 真实任务演练：用户指定的一个实际需求 | 演练报告 |

## M5 · 稳定化

- 全表回归（E+C+S 共 24 条）。
- `docs/04` 状态全量更新、`docs/05` 与原语对齐。
- 性能：若 `wdiag` > 3s，考虑合并调用（一个 PS 进程干多件事）。
- 冻结 v1.0，写 `docs/12-retro.md`（哪里翻车了、为什么）。

## M6 · 发布（用户要求“未来推送到 GitHub 用得上”）

1. `bash scripts/build-release.sh` 产出 `dist/`（两个包 + SHA256SUMS）。
2. 干净目录复演：`git clone` → `bash scripts/bootstrap.sh` → `tests/check-m1.sh`。
3. `git tag vX.Y.Z` + Release 附 `dist/` 产物与复演记录。
4. 迁移说明：换机器时只需 P1 + `bootstrap.sh`；P2 由脚本部署，不入库、不进备份。

## 依赖关系

```
M0 ──► M0.5 ──┐
M0 ──► M1 ────┼──► M2 ──┐
              │          ├──► M4 ──► M5 ──► M6
      M1 ──► M3 ─────────┘   (M3 可与 M2 并行；M4 前 M3 必须全绿)
```

**硬约束**：

- M1 未过不许写 `winput`（D14 + AGENTS.md §4）。
- M3 未过不许做端到端自动化（C8 要求“全程无人工介入”，没有守卫就不许无人值守）。
- 每个里程碑结束必须有一份 `tests/reports/` 报告并提交。

## 授权点（需要用户点头的地方）

| 事件 | 门 | 说明 |
|---|---|---|
| 开始 M1 实施 | 用户授权开工 | ✅ 2026-10-21 已授权 |
| 装任何 Windows Python 包 | G1 | 当前设计**不需要** |
| 常驻急停进程 | G4 | **已决定不做**（软急停够用） |
| 注册全局热键/自启 | G3 | **已决定不做** |
| 删除/覆盖既有产物 | G5 | 每次单独确认 |
