# win-admin · 让 WSL 里的 DSH 在授权窗口内操作 Windows 桌面

> **当前状态：M2 已完成（2026-10-21）。可截图、读控件树、点、打、拖、等——全部默认拒绝、默认 dry-run。下一步 M3（守卫硬化）。**
>
> 一句话：不是"给 agent 开个后门"，而是**一套带刹车、带行车记录仪、见过反例的工具箱**。

## 为什么有这个仓库

用户需求原文（2026-10-20）："让你在我允许时彻底接管 PC 操作。"

调研了一个现成的"DSH 管理员插件"，结论是**不采纳**（详见 `docs/03`）：
它的权限档等于 DSH 内置的 `danger-full-access + approval:never`（零增益），
它真正带来的 computer use 需要 Windows 侧 Electron，而本机 DSH 在 WSL2 里（`DISPLAY` 为空）。

于是自建：不搬环境、不装驱动、不常驻服务，用 Windows 自带的 PowerShell 5.1 做无状态原语。

## 文档索引

| # | 文档 | 回答什么问题 | 状态 |
|---|---|---|---|
| — | [AGENTS.md](AGENTS.md) | 这个项目的硬约束：写入边界、三条红线、门控映射、只读优先纪律 | 现行 |
| 01 | [目的与边界](docs/01-purpose.md) | 要把"彻底接管"做到什么程度、明确不做什么、验收哲学 | 冻结 |
| 02 | [环境实测快照](docs/02-environment.md) | 两侧平台、DPI 双坐标、工具链、三条只读通道、Q1–Q4 开放问题 | 冻结（附复跑） |
| 03 | [插件审计结论](docs/03-plugin-review.md) | 那个插件到底干了什么、为什么不用、借鉴了什么 | 冻结 |
| 04 | [能力矩阵](docs/04-capability-matrix.md) | 四层能力（命令/文件/GUI/视觉）现状、缺口、里程碑归属、八条坑 | 活文档 |
| 05 | [架构设计](docs/05-architecture.md) | 五层架构、无状态原语的选择依据、JSON 契约、守卫层、端到端数据流 | 冻结 |
| 06 | [决策记录](docs/06-decisions.md) | D1–D14：为什么这么选、否掉了什么、何时该推翻 | 现行 |
| 07 | [验收标准](docs/07-acceptance.md) | **冻结件**：E1–E8 / C1–C8 / S1–S8 共 24 条判据 + 里程碑门槛 | 冻结 |
| 08 | [工程规范](docs/08-conventions.md) | 目录归属、提交规范、证据规则、坐标编码铁律、原语模板、DoD | 现行 |
| 09 | [路线图](docs/09-roadmap.md) | M0–M6 里程碑、工作项、风险、G1–G5 授权点 | 现行（M0/M0.5/M1 已完成） |
| 10 | [部署包](docs/10-deployment.md) | 两个包装到哪、怎么升级回滚卸载、怎么打发布物 | 现行 |
| 11 | [已知问题](docs/11-known-issues.md) | K1–K14：每条都有实测证据与修复状态 | 活文档 |

## 目录结构

```
win-admin/
├── AGENTS.md              项目级硬约束（叠加在 ~/.dsh/AGENTS.md 之上）
├── README.md              本文件
├── docs/                  01–09 设计与判据
├── bin/                   原语（M1 起）：wdiag wshot wuia wwin …（M2 才有 winput）
├── ops/                   组合操作（M4 起）
├── guard/                 授权令牌 / 急停 / 审计（M3 起）
├── tests/                 自检与端到端；tests/reports/ 存验收报告
└── inventory/
    ├── scripts/probe-env.sh   只读环境探测（可反复跑）
    └── raw/                   探测原始输出（只增不改）
```

## 三条红线（无论授权与否都不做）

1. **不碰 UAC 安全桌面**——不模拟按键、不改策略、不注入 winlogon。
2. **不在用户不在场时静默操作**——锁屏/断开/息屏必须报错退出。
3. **不在无有效授权令牌时注入输入**——点击/键盘/拖拽都要 `grant.json` 覆盖且未过期。

## 安全模型（三层，全部文件化，用户可随时拧）

| 层 | 机制 | 用户怎么用 |
|---|---|---|
| 授权 | `~/.dsh/win-admin/grant.json`（30 分钟窗口 + scope + 用户原话摘录） | 删文件 = 立即撤销 |
| 急停 | `touch ~/.dsh/win-admin/pause.flag`（M3 起每个输入原语先读） | 敲一行就停；M3 再加 F12 硬通道 |
| 审计 | `~/.dsh/win-admin/audit/YYYY-MM.jsonl`（一行一动作，含被拒的） | `jq` 查我到底干了什么 |

## 关键实测事实（`docs/02` §7 有复跑记录）

| 事实 | 数字 | 影响 |
|---|---|---|
| 屏幕 | 物理 2560×1600 / 逻辑 1707×1067（150%） | 坐标必须声明 DPI 感知，否则点歪 1.5× |
| WSL 侧图形 | `DISPLAY` 为空 | 任何 Linux GUI 驱动都看不见 Windows 桌面 |
| 截图（未声明 DPI） | 1707×1067，137,691 B PNG | 声明后可得 2560×1600（已实测） |
| UIA | 10 个顶层窗口可枚举 | 语义定位可行；中文需首行 UTF-8（已实测修法） |
| Windows Python | 3.11.9 + Pillow 12.2.0，**无** pywin32/comtypes | UIA 与输入走 PowerShell 内置程序集 |
| 会话 | `SessionId=1`，explorer 在 session 1 | 有真实交互桌面可操作 |
| 视觉通道 | ✅ 可读 2560×1600 截图中的 UI 文字 | L4 语义成立，可"看全局"，但不用于判 2px 对齐 |

## 现在能用什么（M2 阶段）

```bash
# 0) 安装 Windows 侧载荷到 C:/Users/Public/win-admin/app/<version>/（幂等）
bash scripts/bootstrap.sh            # 末尾出现 SMOKE PASS 即成功

# 1) 环境体检（会话/锁屏/DPI/屏幕/前台窗口）
bash bin/wdiag | jq .

# 2) 截图（物理像素 2560×1600；区域截图加 --rect x,y,w,h）
bash bin/wshot | jq -r .wsl_path

# 3) 列窗口 / 读控件树（语义定位）
bash bin/wwin list | jq -c '.windows[] | {hwnd,title}'
bash bin/wuia --title 'Notepad' --depth 2 | jq -c '.nodes[] | {depth,name,type}'

# 4) 输入（默认 dry-run 只打印计划；真实注入要 --yes + 有效授权）
bash guard/grant.sh issue --minutes 30 --scope input --note "用户原话：..."   # 授权
bash bin/wwait --title 'Notepad' --timeout 10                                  # 等窗口出现
bash bin/winput click 100 200 --expect-hwnd 0x108c6 --focus                    # 打印计划
bash bin/winput click 100 200 --expect-hwnd 0x108c6 --focus --yes              # 真的点
bash bin/winput type --text "中文内容" --expect-hwnd 0x108c6 --yes             # 剪贴板粘贴
bash bin/wuia --hwnd 0x108c6 --value | jq -r .value                            # 回读校验
bash bin/wclip get                                                             # 剪贴板
bash guard/grant.sh revoke                                                     # 撤销

# 5) 验收（M1 17 项 / M2 11 项，全绿才算过）
bash tests/check-m1.sh
bash tests/check-m2.sh

# 6) 部署工程自检 / 回退 / 卸载
bash scripts/check-release.sh
bash scripts/rollback.sh --list
bash scripts/uninstall.sh --yes
```

注入代码现在**只允许存在于 `winput`**（`bin/winput` + `win/winput.ps1`），由 `scripts/check-release.sh` 第 4 项静态检查守护（`docs/06` D14 随里程碑演进）。
单次原语经 winps 桥约 600–750 ms——真实任务要靠 M4 的复合操作把多次动作压进一次会话，而不是循环调用原语。

## 路线图（详见 `docs/09`）

| 里程碑 | 内容 | 门槛 | 估算 |
|---|---|---|---|
| M0 ✅ | 文档与骨架 | E1 | 2026-10-20 |
| M0.5 ✅ | 双包部署工程（bootstrap/rollback/uninstall/可复现构建） | E9–E12 | 2026-10-21 |
| M1 ✅ | 只读：`wshot` `wuia` `wwin list` `wdiag` | E1–E7, C1–C3（17/0 绿） | 2026-10-21 |
| M2 ✅ | 输入：`winput` `wclip` `wwait` `wwin info` | C4–C7, S7（11/0 绿） | 2026-10-21 |
| M3 | 守卫：令牌 / 急停 / 审计 / 锁屏与 UAC 检测 | **S1–S8 全绿** | 4–6h |
| M4 | 组合操作 + `SKILL.md` + 端到端 | C8, E8 | 5–8h |
| M5 | 稳定化与冻结 | 全表回归 | 2–3h |

## 需要用户点头的事

| 事件 | 门 |
|---|---|
| 开始 M3 实施（审计日志、锁屏/UAC 拒绝、令牌不可篡改） | **用户授权开工**（M2 已交付，等下一步指令） |
| 装任何 Windows Python 包 | G1（当前设计不需要） |
| 常驻急停进程 / 全局热键 / 自启 | G4 + G3（可跳过，软急停够用） |
| 删除/覆盖既有产物 | G5 |

## 已知长期风险

- **前台锁**：Windows 可能拒绝后台进程抢焦点，输入打到别的窗口（M2 必须校验前台）。
- **锁屏检测**：Win11 版本差异可能让 `OpenInputDesktop` 口径失效（M3 必须真实锁屏验证）。
- ~~视觉通道未定（Q1）~~：**已预验通过**（2026-10-20），模型可读截图文字；但像素级精度仍归 UIA。
