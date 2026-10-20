# 02 · 环境实测快照

> 采集时间：2026-10-20 23:30–23:45（Asia/Shanghai）。全部为**只读探测**，未做任何修改。
> 复现脚本：`inventory/scripts/probe-env.sh`，原始输出：`inventory/raw/2026-10-20-probe.txt`。

## 1. 两侧平台

| 项 | WSL 侧（DSH 宿主） | Windows 侧（被接管对象） |
|---|---|---|
| 内核 / OS | Linux 5.15.133.1-microsoft-standard-WSL2 | Microsoft Windows 11 专业版，NT 10.0.26100 |
| 主机名 / 机型 | LAPTOP-8USU1IEJ | TX Gaming FX608LP |
| 用户 | root | ZYX |
| CPU/GPU | — | Intel Graphics（显示输出）+ NVIDIA RTX 5070 Laptop |
| 磁盘 | `/dev/sdc` 1007G，已用 377G（40%） | `C:` 已挂载于 `/mnt/c` |

## 2. 显示与坐标（最关键的一组数）

| 事实 | 值 | 来源 |
|---|---|---|
| 物理分辨率 | **2560 × 1600** | `Get-CimInstance Win32_VideoController` → `CurrentHorizontalResolution` |
| 逻辑分辨率（DPI 虚拟化后） | **1707 × 1067** | `[System.Windows.Forms.SystemInformation]::VirtualScreen` |
| 缩放比 | **150%** | 2560/1707 = 1.4997 |
| 显示器数 | **1**（`\\.\DISPLAY1`，primary） | `[System.Windows.Forms.Screen]::AllScreens` |
| 交互会话 | `SessionId = 1`（`explorer.exe` 在 session 1） | `(Get-Process -Id $PID).SessionId` |
| WSL 侧图形栈 | **无**：`DISPLAY` 为空，`WAYLAND_DISPLAY` 为空 | `echo $DISPLAY` |

**推论（写进架构的硬约束）：**

- 同一个程序，不声明 DPI 感知时拿 1707×1067，声明 per-monitor v2 后拿 2560×1600。
  两套坐标混用 = 点击偏移 1.5 倍，这是"点歪"的第一大原因。
- 截图 1707×1067（150,560 B PNG）实测成功，说明 **GDI `CopyFromScreen` 在未声明 DPI 的 PS 里拿到的是逻辑图**。
- 无 `DISPLAY` ⇒ 任何 **Linux 侧** GUI 驱动（含 Cua 的 `linux-x64-gnu` 原生包）没有可绘制的屏幕，
  **它看不见 Windows 桌面**。这是"为什么不用那个插件"的物理依据。

## 3. 工具链（现成，无需安装）

| 工具 | 位置 | 用途 | 实测 |
|---|---|---|---|
| `powershell.exe` | `/usr/local/bin/powershell.exe`（→ `C:\Windows\System32\WindowsPowerShell\v1.0`） | Windows 侧一切 | **5.1.26100.4061** 可调用 |
| `winps` | `/usr/local/bin/winps` | WSL→PS 低 token 桥：`-j` JSON、`-m` 截断、`-` 走 BOM 化临时 ps1、`-f` 跑现成脚本 | 已验证含 `[Console]::OutputEncoding=UTF8`、stderr 归并、超时 |
| Windows Python | `C:\Users\ZYX\AppData\Local\Programs\Python\Python311\python.exe` | 图像处理 | **3.11.9**，`PIL 12.2.0` 可用 |
| Windows pip 包 | — | — | `comtypes` / `pywin32` / `uiautomation` / `pyautogui` / `numpy` **全部缺失** |
| `py.exe` | `C:\Windows\py.exe` | 启动器 | 存在 |
| `/mnt/c` | — | Windows 盘 | 已挂载 |

**推论**：UIA 与输入注入一律走 **PowerShell 内置程序集**
（`UIAutomationClient` / `UIAutomationTypes` + `Add-Type` 编译 C# P/Invoke），
不引入 pip 依赖。这条决定了项目十年后还能跑（PowerShell 5.1 是 Windows 的常驻组件）。

## 4. 已实测可用的三条能力通道（只读）

### 4.1 截屏

```powershell
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$b=[System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp=New-Object System.Drawing.Bitmap $b.Width,$b.Height
$g=[System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Left,$b.Top,0,0,$bmp.Size)
$bmp.Save("C:\Users\Public\dsh_probe_shot.png",[System.Drawing.Imaging.ImageFormat]::Png)
```

结果：**1707×1067，150,560 字节 PNG**，文件立即可读（探测后已删除，未读取像素内容）。

### 4.2 UI Automation（语义定位，不需要视觉模型）

```powershell
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$root=[System.Windows.Automation.AutomationElement]::RootElement
$cond=New-Object System.Windows.Automation.PropertyCondition(
  [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
  [System.Windows.Automation.ControlType]::Window)
$root.FindAll([System.Windows.Automation.TreeScope]::Children,$cond)
```

结果：枚举到 **10 个顶层窗口**（Edge / Notepad / 资源管理器 / 任务管理器 / Windows Terminal 等）。
**注意（已定位并修好，见 `inventory/raw/2026-10-20-fix-verify.txt` V1）**：
中文乱码的真因不是"PS 默认 GBK"这么笼统——是 `winps` 的 PROLOG
（`[Console]::OutputEncoding=UTF8`）**只在 inline 模式注入**；`winps - ` / `-f` 走 `-File`，PROLOG 不生效，
PowerShell 5.1 于是用 OEM 代码页 936 写 stdout。
修法：stdin/-f 脚本**第一行**写 `[Console]::OutputEncoding=[Text.Encoding]::UTF8`，
并统一 `ConvertTo-Json -Compress`。实测窗口名 10/10 完整中文，无乱码。

### 4.3 合成输入（来自既有技能实测，尚未在本项目复测）

`~/.dsh/skills/windows-gui-e2e-testing/SKILL.md` 的实测结论：

| 方法 | 结论 |
|---|---|
| `SetCursorPos(x,y)` | ✅ 可靠（真实注入） |
| `mouse_event(DOWN/UP)` | ✅ 按钮事件可靠 |
| `mouse_event(MOUSEEVENTF_MOVE)` 相对移动 | ❌ 本机完全无效 |
| 拖拽 | ⚠️ 必须按住后**逐步** `SetCursorPos` |

> 本项目 **M2 阶段必须自己复测这三条**，不能直接继承别处的结论（技能是 2026-09 的经验，
> 且当时的目标窗口/DPI 场景不同）。未复测前按"待验"处理。

## 5. 权限与会话模型（现状）

- DSH 本会话运行时声明：文件策略 `danger-full-access`、`approvals disabled`。
- 因此 **Windows 用户 ZYX 能做的事，agent 通过 `winps` 基本都能做**（文件、进程、服务、注册表、网络）。
- 唯一硬墙：**UAC 提权**（安全桌面）与**锁屏后的输入**。前者永久不做，后者检测到即拒绝。
- 结论：安全边界不能靠"权限不够"，只能靠**我们自己的守卫层**（`guard/`）。

## 6. 与目标相关的开放问题

| 编号 | 问题 | 影响 | 何时必须回答 |
|---|---|---|---|
| **Q1** | 当前会话的模型是否支持图像输入（视觉）？ | 决定截屏是"主通道"还是"仅留证据" | ✅ **已答：支持**（2026-10-20 23:47，见 §7.3） |
| Q2 | 锁屏/断开会话的检测口径（`OpenInputDesktop` 失败？`WTSQuerySessionInformation`？） | 决定红线 2 能否实现 | M3 验收前 |
| Q3 | 多显示器将来接入时的坐标模型 | 影响所有原语的坐标系设计 | 出现第二块屏时 |
| Q4 | 全局急停热键（F12）是否与用户既有工具冲突 | 决定急停实现方式 | M3 前问用户 |

## 7. 复现验证记录

### 7.1 环境数字复跑（2026-10-20 23:38）

命令：`bash inventory/scripts/probe-env.sh`，原始输出 `inventory/raw/2026-10-20-probe.txt`。

| 项 | 本文档记录 | 复跑实测 | 一致 |
|---|---|---|---|
| 内核 | 5.15.133.1-microsoft-standard-WSL2 | 同 | ✅ |
| Windows | 10.0.26100 | `10.0.26100`（Build 26100） | ✅ |
| 机型 | TX Gaming FX608LP | `TX Gaming FX608LP_FX608LP`（ASUSTeK） | ✅ |
| 物理分辨率 | 2560×1600 | Intel Graphics 报 2560×1600（NVIDIA 报 null，屏接在集显上） | ✅ |
| 逻辑分辨率 | 1707×1067 | `DISPLAY1 1707x1067@0,0`，VirtualScreen 1707x1067 | ✅ |
| 交互会话 | SessionId=1 | `{"SessionId":1,"ExplorerSession":1}` | ✅ |
| 顶层窗口数 | 10 | `{"count":10}` | ✅ |
| 截图 | 1707×1067 | `{"w":1707,"h":1067}`，137,691 B（画面内容与首测不同，字节数自然不同） | ✅ |
| Python/PIL | 3.11.9 / 12.2.0 | `py 3.11.9 PIL 12.2.0` | ✅ |

### 7.2 两条坑的修复验证（2026-10-20 23:41）

原始输出：`inventory/raw/2026-10-20-fix-verify.txt`

| 验证 | 结论 |
|---|---|
| V1 中文编码 | stdin/-f 脚本首行加 `[Console]::OutputEncoding=[Text.Encoding]::UTF8` 后，10 个窗口标题中文完整（"此电脑 - 文件资源管理器" 等） |
| V2 DPI 感知 | `SetProcessDpiAwarenessContext([IntPtr]-4)` 后 VirtualScreen 由 1707×1067 变为 **2560×1600**，与物理分辨率一致 |

**这两条把 D4（物理像素单坐标）与 D10（UTF-8 强制）从"设计意图"升级为"已实测可执行"。**

### 7.3 Q1 预验：视觉通道可用（2026-10-20 23:47）

做了一次 DPI 感知全屏截图（2560×1600，298,756 B），把 PNG 读回 agent 上下文，
**不看元数据**仅凭图像读出：浏览器标签页标题（"哔哩哔哩 …"、"创作中心 …"、"qq邮箱 - 搜索"）、
地址栏 `127.0.0.1:3080`、右侧搜索框文字、底部模型徽标"DeepSeek-V4.1-Flash"与"完全权限"。
原文证据：`inventory/raw/2026-10-20-q1-vision.txt`。截图用后即删。

**⇒ Q1 = 支持。** L4 视觉语义成立，但 D5 不变：像素精度仍以 UIA rect 为准，视觉管"看全局"。
