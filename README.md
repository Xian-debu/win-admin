# win-admin · 让 WSL 里的 DSH 在授权窗口内操作 Windows 桌面

> **当前状态：v1.0.0 已冻结（2026-10-21）。全表回归 61 项断言全绿（m1 17 / m2 11 / m3 20 / m4 13 / release pass），端到端十轮连跑 8.19–8.29 s。能力：看屏、读控件树、点/打/拖、复合操作、授权+审计+急停。下一步只剩 M6 发布与 4.4 真实任务演练（等用户给需求）。**
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
| 06 | [决策记录](docs/06-decisions.md) | D1–D23：为什么这么选、否掉了什么、何时该推翻 | 现行 |
| 07 | [验收标准](docs/07-acceptance.md) | **冻结件**：E1–E8 / C1–C8 / S1–S8 共 24 条判据 + 里程碑门槛 | 冻结 |
| 08 | [工程规范](docs/08-conventions.md) | 目录归属、提交规范、证据规则、坐标编码铁律、原语模板、DoD | 现行 |
| 09 | [路线图](docs/09-roadmap.md) | M0–M6 里程碑、工作项、风险、G1–G5 授权点 | 现行（M0–M5 已完成） |
| 10 | [部署包](docs/10-deployment.md) | 两个包装到哪、怎么升级回滚卸载、怎么打发布物 | 现行 |
| 11 | [已知问题](docs/11-known-issues.md) | K1–K33：每条都有实测证据与修复状态 | 活文档 |
| 12 | [复盘](docs/12-retro.md) | 一夜九个翻车点（按代价排序）、三个关键判断、明确没做的事 | 冻结 |
| 13 | [Mission 协议](docs/13-mission-protocol.md) | 长任务的可恢复执行单元：plan/log/evidence 三层 + `wmission` CLI | 现行 |
| 14 | [依赖清点](docs/14-dependencies.md) | 跑起来要什么、可选什么、我们没用什么（版本均实测） | 现行 |
| — | [真实演练实录](missions/taobao-cart-2026-10-21/REPORT.md) | 淘宝购物车 → 采购表：63 行 / ¥202,348.60 / 四个数字对不上 | 存档 |

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
| 授权 | `~/.dsh/win-admin/grant.json`（时间窗 + scope + 用户原话 + **签名**） | 删文件 = 立即撤销；改内容 = `GUARD_TAMPERED` |
| 急停 | `touch ~/.dsh/win-admin/pause.flag` | 敲一行就停（软通道是唯一通道，用户已确认 D7） |
| 审计 | `~/.dsh/win-admin/audit/YYYY-MM-DD.jsonl`（一行一动作，含被拒的；写失败则动作失败） | `jq` 查我到底干了什么 |

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

## 现在能用什么（M4 阶段）

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

# 5) 组合操作（默认 dry-run；--yes 才真动手；全部过 guard + 写审计）
bash ops/open      --exe notepad --args "C:/Users/Public/win-admin/tmp/a.txt" --title a.txt --yes
bash ops/find-and-click --hwnd 0x108c6 --name "^保存$" --type Button --yes
bash ops/fill      --hwnd 0x108c6 --name "文本编辑器" --text "中文 ok" --yes
bash ops/wait-for  --hwnd 0x108c6 --uia-name "^是否要将更改保存" --timeout 5
bash bin/wwin focus --hwnd 0x108c6     # 激活（不产生合成输入）
bash bin/wwin close --hwnd 0x108c6     # 优雅关闭（脏文档交给应用问）

# 6) 把 SKILL.md 装成 agent 技能（装到 ~/.dsh/skills/win-admin）
bash scripts/install-skill.sh          # --remove 卸载

# 7) 验收（M1 17 / M2 11 / M3 20 / M4 13，全绿才算过）
bash tests/check-m1.sh
bash tests/check-m2.sh
bash tests/check-m3.sh
bash tests/check-m4.sh
bash tests/check-m5.sh      # 全表 + E8 十轮（约 6-8 分钟；--only-a / --only-b 可分开跑）

# 8) 部署工程自检 / 回退 / 卸载
bash scripts/check-release.sh
bash scripts/rollback.sh --list
bash scripts/uninstall.sh --yes
```

注入代码现在**只允许存在于 `winput`**（`bin/winput` + `win/winput.ps1`），由 `scripts/check-release.sh` 第 4 项静态检查守护（`docs/06` D14 随里程碑演进）。
单次原语经 winps 桥约 600–750 ms——真实任务用 `ops/` 把多次动作压进一次会话（实测「开记事本→写中文→另存」8.2–9.0 s），而不是让 agent 一步步调原语。

## 路线图（详见 `docs/09`）

| 里程碑 | 内容 | 门槛 | 估算 |
|---|---|---|---|
| M0 ✅ | 文档与骨架 | E1 | 2026-10-20 |
| M0.5 ✅ | 双包部署工程（bootstrap/rollback/uninstall/可复现构建） | E9–E12 | 2026-10-21 |
| M1 ✅ | 只读：`wshot` `wuia` `wwin list` `wdiag` | E1–E7, C1–C3（17/0 绿） | 2026-10-21 |
| M2 ✅ | 输入：`winput` `wclip` `wwait` `wwin info` | C4–C7, S7（11/0 绿） | 2026-10-21 |
| M3 ✅ | 守卫：令牌签名 / 软急停 / 审计账本 / 锁屏与 UAC 拒绝 | S1–S8（20/0 绿） | 2026-10-21 |
| M4 ✅ | 组合操作 + `SKILL.md` + 端到端 | C8, E8（13/0 绿，E8 3/3） | 2026-10-21 |
| M5 ✅ | 稳定化与冻结 v1.0.0 | 全表回归 + E8 十轮（pass=6 fail=0 skip=0） | 2026-10-21 |

## 需要用户点头的事

| 事件 | 门 |
|---|---|
| 开始 M4 实施（`ops/` 复合操作 + `SKILL.md` + 端到端 C8） | 夜间自主授权已覆盖（`docs/12`、SG-0001），早晨一并复核 |
| 装任何 Windows Python 包 | G1（当前设计不需要） |
| 常驻急停进程 / 全局热键 / 自启 | G4 + G3（可跳过，软急停够用） |
| 删除/覆盖既有产物 | G5 |

## 已知长期风险

- **前台锁**：Windows 可能拒绝后台进程抢焦点，输入打到别的窗口（M2 必须校验前台）。
- **锁屏检测**：Win11 版本差异可能让拒绝码文案漂移（K21）；真锁屏无法自测，用只能更严格的钩子断言。
- **审计不可篡改**：同用户进程可删改账本（K22）；真隔离需独立账户/系统服务，本轮明确不做。
- ~~视觉通道未定（Q1）~~：**已预验通过**（2026-10-20），模型可读截图文字；但像素级精度仍归 UIA。

---

## 真实演练：淘宝购物车 → 采购表 Excel（2026-10-21）

这不是玩具 demo，是用户当天给的真任务（`docs/13` Mission 协议的第一个实例，实录见
[`missions/taobao-cart-2026-10-21/REPORT.md`](missions/taobao-cart-2026-10-21/REPORT.md)）：

| 环节 | 怎么做的 | 结果 |
|---|---|---|
| 定位 | `wwin focus` 激活 Edge → `winput key ctrl+l` 输入 `cart.taobao.com/cart.htm` | 购物车页，登录态在 |
| 采集 | 25 轮 `Ctrl+A/Ctrl+C` → `wclip get` 累积渲染文本 + 12 张 50% 缩放截图 | 62 个支付行 + 完整条目文本 |
| 解析 | `parse-cart.py`（价格组锚定「平台加补后」、判别「距加入降」、数量取末组之后） | 63 行，抽查 6/6 单价与截图一致 |
| 产出 | `build-xlsx.py`（openpyxl）→ 2 个工作表 | `out/淘宝购物车采购表.xlsx`，SUM 复核 ¥202,348.60 |
| 对账 | 角标 138 / 文本 62 行 / 全选可结算 50 件 / 本表 63 行 | 四个数字不相等，差异**原样登记**，不做推测性修正 |

关键点：**全程没有接口抓包、没有 DevTools 协议、没有注入页面脚本**，只用键盘/剪贴板/截图这类"人也能做"的动作。
试过并失败的路（记录在 REPORT）：`ctrl+u` 源码壳、F12 控制台收键、CDP 端口、`javascript:` 地址栏。

## 依赖与"用了什么"（完整清单见 [docs/14](docs/14-dependencies.md)）

- **硬依赖**：WSL2 + bash 5.2 + jq 1.7 + Windows 自带 PowerShell 5.1 + .NET（UIAutomationClient/Drawing/Forms，全部 `Add-Type` 内联）。
- **零三方库**：没有 pip 包、没有 npm 包、没有驱动、没有浏览器扩展、没有常驻服务。
- **开发期可选**：Python 3.12.3 + openpyxl 3.1.5（只用于离线解析与出 xlsx）。
- **模型**：DeepSeek-V4.1-Flash（规划 + 执行 + 视觉判读），未调用任何云视觉/OCR API，截图不出本机。
- **技能**：本仓库的 `SKILL.md`（安装到 `~/.dsh/skills/win-admin`）+ `wsl-windows-token-bridge`、`local-facts-bridge`、`windows-gui-e2e-testing`。

## 控制方式（用户手里有三个开关）

| 想做什么 | 怎么做 | 生效时间 |
|---|---|---|
| 临时允许我操作 | 让我 `guard/grant.sh issue --minutes 30 --scope input --note "你的原话"`（我会把原话写进令牌） | 立即 |
| 立刻收回 | `rm ~/.dsh/win-admin/grant.json` | 下一次动作即 `GUARD_NO_GRANT` |
| 紧急刹车 | `touch ~/.dsh/win-admin/pause.flag` | 下一次动作即 `GUARD_PAUSED`（软通道，用户 D7 确认） |
| 事后追责 | `jq . ~/.dsh/win-admin/audit/$(date +%F).jsonl` | 一行一动作，被拒的也记 |

我会**拒绝**的情况（不是"尽量"）：锁屏/断开/息屏（`SESSION_LOCKED`）、UAC 安全桌面（`UAC_SECURE_DESKTOP`）、
无有效令牌、令牌被改（`GUARD_TAMPERED`）、坐标点击未声明目标窗口（S7）。

## 换台机器怎么部署（难度分级）

| 环境 | 难度 | 要做的事 | 已知限制 |
|---|---|---|---|
| Windows 11 + WSL2（本机） | ★☆☆ 照抄 | 装 `winps` 桥 → `bash scripts/bootstrap.sh` → `bash tests/check-m1.sh`；屏幕缩放非 100% 时会自动声明 DPI | 无（本机全绿） |
| Windows 10 1809+ + WSL2 | ★★☆ | 同上；DPI 感知走 `SetProcessDPIAware()` 回退分支 | 未实测；UIA 树差异可能影响 `--name` 匹配 |
| Windows + Git Bash / MSYS2（无 WSL） | ★★★ | 需要自己实现 `winps` 等价桥（bash→powershell）；原语可原样用 | `wsl_path` 输出要改；中文编码坑同 K1 |
| Linux / macOS 主机 | ★★★★ | 必须另配一台 Windows（RDP/VNC/VM）并重做传输层；本仓库的 `winps` 假设不成立 | 本仓库不承诺可移植 |
| 多显示器 / 4K 缩放混搭 | ★★★ | 需要把 `--rect` 的坐标系扩到 per-monitor 原点 | Q3 仍未闭环（`docs/02`） |

## 未来改进（按性价比排序）

1. **控件树直读页面**：本次用页面渲染文本 + 截图双源；下一版试 `wuia` 读 Chromium AX 树（需先打开 Edge 无障碍），可省掉 25 轮复制。
2. **视觉列抽取**：把截图里的价格/数量也逐行对齐，做自动三方比对（文本 / 截图 / 结算栏）。
3. **审计防篡改**：当前同用户可改账本（K22）→ 独立账户或系统级追加日志。
4. **多显示器与混合 DPI**：Q3 未闭环，坐标系需要 per-monitor。
5. **急停升级**：软通道够用（D7），但可加"看门狗进程"（G4，需用户点头）。
6. **发布**：GitHub Release + 签名 tag 尚未做（M6，需用户决定）。

## 许可

MIT（`LICENSE`）；三方组件见 `THIRD_PARTY_NOTICES.md`。
本仓库**不含**用户数据：截图与逐轮原始文本默认被 `.gitignore` 排除。

