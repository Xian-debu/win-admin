# 16 · 三会话使用反馈：缺失的操作映射（取证）

> 日期：2026-10-24 凌晨。取证对象：v1.0.0 冻结之后，三个真实会话里 win-admin 的**实际用法**。
> 本文只写**可复核的现象**与**它指向的缺口**，不写"感觉"。每条都给出会话 seq 定位。

## 0. 为什么要写这一篇

v1.0.0 的验收（E/C/S 共 24 条）证明的是"原语各自正确"，证明不了"原语够用"。
v1.0.0 发布后，win-admin 又被用了三次真实任务：

| 会话 | 任务 | win-admin 的角色 |
|---|---|---|
| `session-d2ba84f9` | 淘宝购物车 → 采购表 Excel（M6 真实演练） | 纯 GUI 采集 63 行 |
| `session-c0ace632` | ARC 论文解读片 → B 站投稿 | 表单填写 + 上传 + 提交，产出 BV1ojnt6oE79 |
| `session-fc2c1970` | mascot 桌宠（Qt 自绘窗） | 窗口定位 + 截图验证 |

三次任务**没有一次报错到底**，但三次都出现了同一种现象：
**工具里没有这个动作 → agent 现场手写 PowerShell / 换工具 / 放弃功能。**
这种"绕路"不会出现在退出码里，只出现在会话的工具调用里——所以必须去日志取证。

复现命令（本文所有数字的来源）：

```bash
python3 scripts/scan-sessions.py --session d2ba84f9-76ef-404b-b9ca-9a8fc54752b1
python3 scripts/scan-sessions.py --session c0ace632-8b18-4955-87c1-cd96752f4ebd --from 3800
python3 scripts/scan-sessions.py --session fc2c1970-16b2-46ad-98d5-c6fd1edd94d9
```

## 1. 现象清单（按缺口归并）

### 1.1 缺口 A：窗口状态没有原语 → c0 手写 ShowWindow

- c0 seq 4216：B 站投稿页需要更大窗口。`bin/wuia` 找不到"最大化"按钮，于是**在会话里现写** PowerShell：

  ```powershell
  Add-Type @"
  using System; using System.Runtime.InteropServices;
  public class W {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  }
  "@
  [W]::ShowWindow([IntPtr]593116, 3)   # SW_MAXIMIZE
  [W]::SetForegroundWindow([IntPtr]593116)
  ```

  写完存成 `C:/Users/Public/win-admin/tmp/maxwin.ps1`，再用 `winps -r -m 4000000 -t 60 -f` 执行。
  seq 4691 的脚本里又把这套 ShowWindow(3)+SetForegroundWindow 抄了一遍。
- `bin/wwin` 现有子命令只有 `list|info|focus|close`；`docs/04` 能力矩阵"窗口激活/最大化/移动"一行标 ✅，
  但代码里只有 `ShowWindow(h,9)`（SW_RESTORE）用于置前台，**没有最大化/最小化/移动/改尺寸/置顶的入口**。
- 缺口动作：**`wwin set --state max|restore|min|normal --x --y --w --h --topmost on|off` + `wwin state --hwnd`**（含回读校验）。

### 1.2 缺口 B：没有 hover / wheel / 按住不放 → c0 三次手写鼠标脚本

B 站"分区"是一级下拉 + **hover 才展开**的二级浮层。为了展开它，c0 依次尝试并**全部失败**：

| seq | 手段 | 结果 |
|---|---|---|
| 4532 | 点一级条目 | 菜单直接关掉 |
| 4572 | 列表内 `key right/down` | 高亮不动 |
| 4547 | 手写 `SetCursorPos(924,371)` 单点悬停 + 200 ms | 无浮层 |
| 4602 | 手写**分段渐进移动** `@(@(900,300),@(910,320),@(918,340),@(920,355),@(922,365),@(924,371),@(930,373))`，每段 120 ms，末尾停 1200 ms | 无浮层 |
| 4691 | 手写 `ShowWindow+SetForegroundWindow+SetCursorPos×4+mouse_event(0x0001)` 相对抖动 | 无浮层 |
| 4634 | 转去 `cdp_status` 想用 CDP 绕过 GUI | 端口未监听 |
| 4723 | **放弃二级分区**，只选一级"科技数码"并提交 | 平台接受，无报错 |

- `bin/winput` 现有动作：`move|click|dclick|drag|key|type`。
  **没有 `hover`（移动+驻留+可判定）**、**没有 `wheel`（滚轮）**、**没有 `keydown/keyup`（按住）**。
- 载荷 `win/winput.ps1:119` 的越界检查里**已经列了 `'wheel'`**，但 `switch` 里没有对应分支 →
  今天调用 `wheel` 会得到 `ARG_BAD_ACTION`。这是"预留了但没实现"的半成品。
- 缺口动作：**`winput hover X Y --dwell MS --steps N`（返回落点处 UIA 元素，让"悬停生效"可判定）**、
  **`winput wheel --at X Y --delta N --times N`**、**`winput key --hold MS` / `keydown` / `keyup`**。

### 1.3 缺口 C：UIA 只能"看"，不能"按名字找 + 按名字动"

| seq | 现象 |
|---|---|
| 4285 | 为找表单控件，先 `wuia --depth 10 --max 600` 全树 dump，再**用 python 自己解析 JSON** 找节点和 rect |
| 4186 | 想用"按名字找按钮"，实际 CLI 根本没有 `--name`；`--filter` 只是输出过滤，且不返回"可动作"信息 |

`win/wuia.ps1` 只有三种模式：`--list`（顶层窗口）、树 dump、`--value`（**只读第一个** ValuePattern 元素）。
没有：按 name/type/aid 检索、返回匹配节点的矩形、探测该节点支持哪些 Pattern、`Invoke/SelectionItem/ExpandCollapse/Value` 的**动作**。
`docs/04` 把"语义点击（找到控件直接 Invoke）"标为 🧪 未测，原话"需要 wuia 输出 aid 后按 aid 定位"——一年过去仍是缺口。

- 缺口动作：**`wuia --find --name RE --type RE --aid RE [--enabled] [--index] [--limit]`**（返回 rect+patterns）、
  **`wuia --invoke | --select | --set-value | --expand | --collapse | --focus`**、**`wuia --point X Y`**（取屏幕坐标处元素）。

### 1.4 缺口 D：定位全靠"截图 + 目测 + 手填坐标"

c0 全程（seq 3953–4753）的定位环路是：
`wshot → read_image 目测 → 手填坐标 → winput click --expect-hwnd → 再截图`，
30+ 张截图、多次 PIL 裁图；fc 里同样出现"点一下 → 截图 → 放大裁剪 → 挪几像素"的循环。

- 缺口动作：**`ops/click-element`（按 UIA 名字找到 rect → 点中心 → 校验）**、
  **`wshot --rect x,y,w,h` / `--hwnd` / `--grid N`（网格标尺，读数不再猜）**。

### 1.5 缺口 E：等待只有"等窗口出现"

`bin/wwait` 只能等窗口出现；页面/控件状态变化只能靠 `sleep`。
c0 里出现 `sleep 0.8 / 1.0 / 2.5 / 3.0 / 60`（上传等待 60 s 硬睡）。
缺口动作：**`wwait --uia --name RE [--enabled] [--value RE] [--timeout MS]` 谓词等待**。

### 1.6 缺口 F：`type` 在 shell 引号上静默失败（最坏的一种失败）

c0 seq 4337：标题含半角单引号 `FAST'03`，`winput type --text "…"` 被 shell 截断，
**工具不打印 JSON、不报错、退出码也没有异常**（表现为"什么都没发生"）。
最终把文本写进 `/tmp/title.txt` 走 `--text-file` 才成功（seq 4953 复盘原话）。

- 缺口动作：**`winput type --stdin`**（从标准输入读，天然免引号）、
  **空文本/缺参数必须 `ARG_EMPTY_TEXT` 非零退出并输出 JSON**（杜绝静默）。

### 1.7 缺口 G：网页语义通道缺失（结构性）

淘宝演练（`missions/taobao-cart-2026-10-21/REPORT.md` §4）与 B 站投稿都撞上同一堵墙：

| 路线 | 结果 |
|---|---|
| `ctrl+u` 看源码 | 19 KB 空壳，商品由 XHR 渲染 |
| DevTools 控制台打 `document.title` | 控制台能开，**SendInput 打的字进不去** |
| CDP 9222/9223/9229/9333 | 全部未监听（Edge 以 `--no-startup-window /prefetch:5` 启动） |
| 地址栏 `javascript:` | Edge 剥 scheme，变必应搜索 |
| 兜底：`ctrl+a/ctrl+c` 循环 | 淘宝购物车 **25 轮**才拿全 62 行文本 |

这是 v2 的**路线级**问题，不是补一个原语能解决的：需要"网页正文/控件的语义读取"通道
（Edge 无障碍树，或受管 CDP 实例），否则 GUI 剪贴板循环永远是 O(屏数)。

## 2. 量化：这些绕路值多少钱

用 `scripts/scan-sessions.py` 统计三会话里的"手写 Win32"调用：

| 会话 | Add-Type | ShowWindow | SetCursorPos | mouse_event | cdp_status | 性质 |
|---|---|---|---|---|---|---|
| d2 | 43 | 11 | 15 | 17 | 0 | 多数是**开发 `win/*.ps1` 本身**（正常） |
| c0 | 5 | 3 | 7 | 1 | 2 | **全部是运行时绕路**（异常） |
| fc | 1 | 1 | 0 | 0 | 0 | 一次窗口状态探查 |

结论（方法论）：**失败不表现为错误码，而表现为"没有这个动作，于是改用别的手段"。**
所以以后评估定位缺口，不能只看 `rc!=0`，要扫"手写 powershell / 换工具 / 放弃功能"这三种行为。

## 3. 与已有 K 清单的关系

- K17（WinForms TextBox 无 ValuePattern）→ 归入缺口 C 的 `--set-value` 兜底设计。
- K24（显示器配置会变）→ 缺口 A 的 rect 回读必须动态取，不缓存。
- K30（模态保存框是子窗口）→ 缺口 C 的 `--find` 必须能扫 UIA 子窗口，而不是 `wwin list`。
- 新增（本文取证）：**K36 `wwin` 无状态控制**、**K37 `winput` 无 hover/wheel/hold（wheel 半实现）**、
  **K38 `wuia` 无语义检索与动作**、**K39 `type` 静默失败（shell 引号）**、**K40 网页语义通道缺失**。

## 4. 一句话总结

v1.0.0 把"看得见、点得中、打得进"做对了；三次真实任务证明**"够用"是另一回事**：
缺的是一组**把绕路消灭在工具里**的原语——窗口状态、悬停/滚轮/按住、按名字找并动作、谓词等待、
免引号输入、以及网页语义通道。升级计划见 `docs/17-v2-plan.md`。
