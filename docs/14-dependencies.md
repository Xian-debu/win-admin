# 依赖、组件与"用了什么"清点

> 目标：任何人拿到这个仓库，都能一眼看清**跑起来需要什么、可选的是什么、我们没用什么**。
> 所有版本号均为本机实测（2026-10-21），不是"大概"。

## 1. 运行时硬依赖（缺任何一个都跑不起来）

| 组件 | 本机版本 | 用途 | 来源/许可 | 备注 |
|---|---|---|---|---|
| WSL2（Linux 侧） | Ubuntu 24.04.4 LTS，内核 5.15.133.1-microsoft-standard-WSL2 | 宿主：DSH 与所有 bash 原语在此运行 | 系统自带 | WSL1 不适用（无 \\wsl$ 互操作性能） |
| bash | GNU bash 5.2.21 | 原语与测试脚本 | GPLv3+ | 只用到 4.x 特性 |
| jq | jq-1.7 | 每个原语的 JSON 输出解析、mission plan 读写 | MIT | **唯一**被硬依赖的三方 CLI |
| Windows PowerShell | 5.1.26100.4061（Windows 自带） | Windows 侧全部动作（截图/UIA/输入/窗口） | 系统自带 | 不需要 PowerShell 7，不需要装模块 |
| .NET UIAutomationClient / System.Windows.Forms / System.Drawing | 随 .NET Framework 4.8 自带 | 控件树、屏幕截图、Win32 P/Invoke | 系统自带 | 全部 `Add-Type` 内联，不落 DLL |
| Windows 11 | 26100（24H2） | 目标桌面 | 系统自带 | Win10 1809+ 理论可用，未实测 |

**没有的东西**：无 pip 包、无 npm 包、无 Python 侧依赖、无常驻服务、无驱动、无浏览器扩展、无 Electron 第二实例。

## 2. 桥接层（自研，非三方）

| 组件 | 位置 | 作用 |
|---|---|---|
| `winps` | `/usr/local/bin/winps` | WSL→Windows PowerShell 调用桥：inline / `-f 文件` / stdin 三种模式、`-j` 输出 JSON、`-t` 超时、`-m` 截断、UTF-16→UTF-8 转码 |
| `lib/common.sh` | 仓库内 | 原语公共函数：JSON 输出、退出码、`winps` 封装、guard 调用 |

> `winps` 不在本仓库里（属于本机基础设施），第 7 节给了它的最小可用实现，方便别人复现。

## 3. 目标应用（被操作对象）

| 应用 | 版本 | 用途 | 说明 |
|---|---|---|---|
| Microsoft Edge | Chromium 155（`537.ks-webkit-chrome155`） | 真实任务演练的浏览器 | 只作为被驱动对象；不注入、不调试协议、不读 Cookie |
| 记事本（Win11 单进程多标签） | 系统自带 | M4 端到端验收靶子 | 单进程多标签带来的坑见 `docs/11-K31` |

## 4. 开发期工具（只影响"改代码/跑演示"，不影响运行）

| 工具 | 版本 | 用途 |
|---|---|---|
| Python 3 | 3.12.3（WSL） | 仅用于**离线**解析采集文本、生成 xlsx；原语层零 Python |
| openpyxl | 3.1.5 | 生成采购表 xlsx（MIT） |
| Pillow | 12.2.0（Windows Python 3.11.9，可选） | 早期截图实验用；原语改走 GDI 后已不需要 |
| git | 2.x | 版本管理；`scripts/bootstrap.sh` 不依赖 git |

## 5. 用到的 DSH 技能（模型侧的"作业指导书"）

| 技能 | 关系 | 说明 |
|---|---|---|
| `win-admin`（本仓库 `SKILL.md` 安装） | **本项目产出** | 五步配方（看→定窗→定控件→动→验）+ 坑表 + 拒绝条件 |
| `windows-gui-e2e-testing` | 前作，复用结论 | 合成输入的可靠性结论（SetCursorPos/mouse_event 实测）在 M2 被重新验证 |
| `wsl-windows-token-bridge` | 基础设施 | 跨侧命令一律走 `winps`/`wslrun`，避免引号与编码事故 |
| `local-facts-bridge` | 基础设施 | 查磁盘/内存/进程用 `sysfacts`，省 token |
| `task-alignment-charter` / `destructive-change-discipline` | 纪律 | 授权门控 G1–G5、不可逆操作前的回退点 |

## 6. 用到的模型

| 模型 | 角色 | 说明 |
|---|---|---|
| DeepSeek-V4.1-Flash（DSH 会话） | 规划 + 执行 + **视觉判读** | 截图理解（读 tab 标题、地址栏、中文文案、价格）由同一个模型完成，没有额外 OCR/检测模型 |
| — | 无第三方视觉模型 | 没有调用任何云 API；截图不出本机（`docs/12` 硬约束：不上传用户数据） |

## 7. `winps` 最小实现（复现用）

```bash
#!/usr/bin/env bash
# 极简版：inline 模式 + UTF-8 前导；够跑通 bin/wdiag 与 bin/wshot
PROLOG='[Console]::OutputEncoding=[Text.Encoding]::UTF8;'
exec powershell.exe -NoProfile -NonInteractive -Command "$ProgressPreference='SilentlyContinue'; $PROLOG $*"
```

stdin/`-f` 模式必须由调用方在脚本**第一行**自己写 `[Console]::OutputEncoding=[Text.Encoding]::UTF8`，
否则 PowerShell 5.1 以 OEM 936 输出，中文全变乱码（`docs/11-K1`）。

## 8. 许可与合规

- 本仓库代码：MIT（见 `LICENSE`）。
- 三方组件许可与义务：见 `THIRD_PARTY_NOTICES.md`（jq MIT、openpyxl MIT、PowerShell/.NET 为系统组件）。
- **不含**任何用户数据：截图、购物车文本、xlsx 产物都在 `missions/` 下，`*.png` 与逐轮原始文本默认 `.gitignore`。
