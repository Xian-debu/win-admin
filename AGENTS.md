# win-admin 项目级 Agent 规则

> 本文件是 **项目级** 约束，叠加在 `~/.dsh/AGENTS.md`（全局准则与 G1–G5 门控）之上。
> 冲突时以更严的一条为准。任何自称"为了跑通"的越界，都必须先走门控。

## 0. 一句话定位

让运行在 **WSL2 里的 DSH** 在**用户显式授权的时间窗内**操作 **Windows 桌面**
（截屏、控件树、鼠标键盘、窗口），且**每一步可审计、随时可急停**。

## 1. 写入边界（硬约束）

允许写：

| 位置 | 用途 |
|---|---|
| 本仓库 `/root/win-admin/` | 代码、文档、测试 |
| `/mnt/c/Users/Public/win-admin/` | Windows 侧临时物（截图、ps1、日志），可随时整体删除 |
| `~/.dsh/win-admin/` | 运行时：`grant.json` / `audit/*.jsonl` / `pause.flag` |
| `/tmp/` | 单次临时文件 |

禁止（除非用户当次明确批准）：

- 写 Windows 注册表、服务、计划任务、开机启动项、系统代理、DNS
- 写 `C:\Windows\`、`Program Files`、用户文档/桌面/下载等个人目录
- 修改 `~/.dsh/` 下除 `win-admin/` 外的任何配置（尤其 profile 的 `package.json`）
- 删除任何用户数据（删除类动作永远先列清单 + 等确认，即便在 danger-full-access 下）

## 2. 三条红线（无论授权与否都不做）

1. **不碰 UAC 安全桌面**：提权弹窗是系统级隔离，绕过尝试（模拟按键到 Secure Desktop、
   改 UAC 策略、注入 winlogon）一律拒绝。
2. **不在"用户不在场"时静默操作**：锁屏 / 会话断开 / 显示器休眠 / RDP 未连接时，
   输入类工具必须**报错退出**，不允许"点了但没人看见"。
3. **不在无有效 grant 时执行输入类动作**：截屏与读取（只读）可仅凭会话授权；
   点击 / 键盘 / 拖拽必须持有未过期的 `grant.json` 且 scope 覆盖。

## 3. 门控映射（本项目常见触发点）

| 动作 | 门 |
|---|---|
| 安装 Windows 侧 Python 包（pywin32 / comtypes / uiautomation / pyautogui …） | **G1 选型** |
| 开始常驻进程（急停热键守卫、Windows 侧 bridge 服务） | **G4 常驻** |
| 注册全局热键 / 开机自启 / 计划任务 | **G3 系统配置** |
| 覆盖、删除、卸载任何既有脚本或产物 | **G5** |
| 只要读写本仓库与 `/mnt/c/Users/Public/win-admin/` | 无需门控（本会话默认可行） |

## 4. 只读优先（M1 阶段纪律）

**M1（只读能力）通过验收前，仓库里不允许出现任何鼠标/键盘注入代码。**
先证明"看得见、认得准"，再谈"点得中"。这条是防止"先能点、后补安全"的经典翻车。

## 5. 提交规范

- **一个文档 / 一个原语 = 一个提交**，不攒大提交。
- subject 前缀：`init:` / `docs:` / `probe:` / `bin:` / `guard:` / `test:` / `fix:` / `chore:`
- subject 用中文，说清"做了什么"；body 说"为什么 + 实测数字"。
- 文档里的结论**必须带证据**（命令、输出片段、文件路径:行号、字节数、耗时）。
  没有实测支撑的判断，写成 `假设`/`待验`，不许写成结论。
- 验收标准（`docs/07-acceptance.md`）是**冻结件**：改判据要单独提交并说明为什么原判据不成立。

## 6. 编码与平台坑（血泪，别重犯）

- WSL → Windows 的 stdout 默认会被抓成 GBK/UTF-16：一律 `[Console]::OutputEncoding = [Text.Encoding]::UTF8`，
  复杂脚本走 `winps -`（BOM 化临时 ps1）或 `--file`，**不要**在 bash 里手拼多层引号。
- 屏幕是 **2560×1600 物理 / 1707×1067 逻辑（150% 缩放）**：
  未声明 DPI 感知的进程拿到的是逻辑像素，`SetCursorPos` 与 GDI 抓屏**坐标系不一致**就是"点歪"的第一原因。
  所有原语必须以 **per-monitor v2 DPI aware** 启动，并对外只暴露一种坐标（物理像素）。
- Windows Python 只有 `Pillow`，没有 pywin32/comtypes/pyautogui：
  **UIA 与输入一律走 PowerShell（内置 `UIAutomationClient` + `Add-Type` 的 P/Invoke）**，
  装包要先过 G1。这条是长期可用性的关键：不依赖 pip 生态，就不怕环境漂移。
