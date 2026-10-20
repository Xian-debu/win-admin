# 05 · 架构设计

> 目标：把"四层能力"落成一套**可从 WSL 调用、可被 agent 组合、可被用户审计**的工具集。
> 约束来源：`AGENTS.md` §1 写入边界 / §4 只读优先；`docs/04` 的能力现状。

## 1. 分层图

```
┌──────────────────────────────────────────────────────────┐
│ L4  DSH skill (SKILL.md)   告诉 agent：什么时候能用、怎么组合 │
├──────────────────────────────────────────────────────────┤
│ L3  guard/   授权令牌 · 急停 · 审计 · 前置体检               │
├──────────────────────────────────────────────────────────┤
│ L2  ops/     组合操作（打开并点击、填表、等变化）             │
├──────────────────────────────────────────────────────────┤
│ L1  bin/     原语：wshot / wuia / winput / wwin            │
├──────────────────────────────────────────────────────────┤
│ L0  transport  winps（PowerShell 5.1）+ Windows Python     │
└──────────────────────────────────────────────────────────┘
        WSL2 (Linux)                    Windows 桌面
   ← 所有原语都是"一次调用、无状态、退出即净" →
```

## 2. 为什么是"无状态原语"而不是"常驻服务"

| 方案 | 优点 | 缺点 | 决定 |
|---|---|---|---|
| 常驻 Windows 侧 bridge（HTTP/命名管道） | 延迟低、可持有 UIA 缓存 | 常驻进程 = G4；崩了要人管；多一套攻击面 | ❌ M4 前不做 |
| 每次启动 `powershell.exe` | 简单、可审计、崩了不影响下一次 | 每次 ~300ms 启动开销 | ✅ **本方案** |
| Python 常驻 | 同上问题 + 依赖 pip | 环境漂移 | ❌ |

**代价可接受**：一次"点按钮"的端到端延迟里，人眼等待本来就在 200ms 级；
300ms 启动换"永远不需要清理残留进程"，划算。

> 唯一例外：M3 的急停守卫可能需要常驻（`RegisterHotKey` 要求消息循环）。
> 届时单独走 G4，并设计成"独立小进程 + 可一键杀掉"，不与主链路耦合。

## 3. L0 · 传输层

### 3.1 选路规则

| 场景 | 走 | 理由 |
|---|---|---|
| 命令式、短、结构化输出 | `winps -c '...' -j` | 一条命令搞定，输出 JSON |
| 需要循环 / 多行 / 引号嵌套 | `winps -f script.ps1` | 脚本落 `/mnt/c/Users/Public/win-admin/` 再执行 |
| 图像处理、二进制、字符串算法 | Windows Python `python.exe` | PIL 现成；避免 PS 里折腾字节 |
| 两者协作 | PS 抓屏存盘 → Python 处理 → 打印 JSON | 各用所长 |

### 3.2 编码与输出协议（**所有原语的统一契约**）

```
stdout : 恰好一个 JSON 对象（UTF-8），无日志、无进度条
stderr : 人类可读的诊断（中文），仅供调试
exit   : 0 成功 / 2 参数错误 / 3 环境不满足（如锁屏） / 4 权限被拒（guard） / 5 执行失败
```

成功样例：
```json
{"ok":true,"data":{"w":2560,"h":1600,"path":"/mnt/c/Users/Public/win-admin/shots/20261020-2355.png","scale":1.5}}
```

失败样例：
```json
{"ok":false,"code":"SESSION_LOCKED","msg":"输入桌面不可访问，疑似锁屏","ts":"2026-10-20T23:55:01+08:00"}
```

**为什么必须严格**：agent 解析 stderr 的信息量极低；JSON 一个键就能让它精确分支。

## 4. L1 · 原语清单（bin/）

| 原语 | 职责 | 输入 | 输出（data） | 里程碑 |
|---|---|---|---|---|
| `wshot` | 截图 | `--monitor N` / `--rect x,y,w,h` / `--full` | `{path,w,h,scale}` | M1 |
| `wuia` | 控件树 | `--window "#标题" `/` --pid N` / `--depth N` / `--filter type=Button` | `{nodes:[{name,type,rect,invokable,...}]}` | M1 |
| `wwin` | 窗口操作 | `list` / `focus --hwnd H` / `layout x,y,w,h` / `state max|min|restore` | `{hwnd,title,rect,state}` | M1(list)/M2(改) |
| `winput` | 输入注入 | `move x,y` / `click x,y[,btn] `/ `dclick` / `drag x1,y1,x2,y2` / `key ctrl+s` / `type "文本"` | `{injected:true}` | M2 |
| `wclip` | 剪贴板 | `get` / `set "文本"` | `{text}` | M2（中文输入依赖） |
| `wdiag` | 前置体检 | — | `{locked,foreground,session,dpi,guard}` | M1 |

**原语设计三原则：**

1. **只要一种坐标**：全部物理像素。内部若需要逻辑像素，自己换算，绝不让调用方感知。
2. **不猜**：找不到窗口/控件就报错，不做"最像的那个"。agent 宁可重试也不要盲点。
3. **可 dry-run**：`winput` 支持 `--dry-run`，只打印"我会点到 (x,y)，目标窗口 = X"，不真点。
   这是 M2 验收（和用户建立信任）的关键工具。

## 5. L3 · 守卫层（guard/）

### 5.1 授权令牌 `~/.dsh/win-admin/grant.json`

```json
{"issued":"2026-10-20T23:00:00+08:00","expires":"2026-10-20T23:30:00+08:00",
 "scope":["shot","uia","win","input"],"confirm_by":"lead-agent",
 "note":"用户当场说：帮我把 Edge 里那个表格导出来","revoked":false}
```

- **谁签发**：agent 在**用户当次明确同意后**写这个文件，把用户原话摘进 `note`。
- **谁校验**：每个输入类原语启动时第一件事读它；过期 / `revoked` / scope 不含 → exit 4。
- **为什么不用系统权限**：本会话已是 `danger-full-access`，系统层拦不住任何东西；
  令牌的意义是**留痕 + 给用户一个真能拧的旋钮**（删文件即撤销）。

### 5.2 急停双通道

| 通道 | 机制 | 生效范围 |
|---|---|---|
| 软（随时可用） | 存在 `pause.flag` 就拒绝执行输入 | 每个原语读一次；用户/agent 都能建这个文件 |
| 硬（M3，需 G4/G3） | 全局热键 `F12` → 写 `pause.flag` | 常驻小进程；热键冲突需先问用户（Q4） |

**软通道已足够应急**：用户在终端敲一句 `touch ~/.dsh/win-admin/pause.flag`，
或 agent 自己触发，下一个原语立刻停。硬通道只是为了"手离开键盘也能停"。

### 5.3 审计 `~/.dsh/win-admin/audit/YYYY-MM.jsonl`

一次动作一行，只追加：

```json
{"ts":"...","tool":"winput.click","args":{"x":512,"y":300},"target":{"hwnd":1234,"title":"Edge"},
 "grant":"...","result":"ok","dur_ms":412}
```

- 输入类动作 **必写**（含被拒的，`result:"denied"`）。
- 只读类动作写"秒级折叠"摘要（避免每张截图一行刷爆）。
- 拒写：审计文件本身不允许被原语修改，只能追加。

## 6. L2 · 组合操作（M4）

原语之上需要一层"意图级"API，否则 agent 每次都要手写 20 行序列。计划最小集：

| 组合 | 语义 |
|---|---|
| `open <路径/URL>` | 启动并用 UIA 等到窗口出现（超时即失败） |
| `find-and-click <控件名>` | 在目标窗口里 UIA 搜索 → Invoke 或坐标点击 → 校验状态变化 |
| `fill <字段标签> <值>` | 定位输入框 → 聚焦 → 剪贴板粘贴 → 校验回读 |
| `wait-for <条件> <超时>` | 轮询 UIA/像素，条件成立即返回 |
| `screenshot-to-me` | 截图 + 返回路径，供 agent 用视觉通道看（若 Q1 支持） |

## 7. L4 · DSH 技能（SKILL.md）

技能只解决三件事，不重复架构细节：

1. **什么时候必须拒绝**（锁屏、UAC、无 grant、用户没明确说要动桌面）；
2. **标准配方**（截图→UIA→dry-run→执行→复检 的五步闭环）；
3. **失败信号解读**（exit 3/4/5 各自该怎么退）。

## 8. 数据流示例：'把 Edge 里的表格导出'

```
用户同意 → agent 写 grant.json (scope=["shot","uia","input"], 30min)
  ↓
wdiag          → {locked:false, foreground:"Edge", dpi:1.5, guard:"ok"}
wshot          → 存图（证据 + 供视觉判断）
wuia --pid E   → 找到"导出"按钮 rect=[1200,340,90,32]（物理像素）
winput --dry-run click 1245,356 → 打印"将点击 导出"
[agent 确认目标无误]
winput click 1245,356          → 写审计
wait-for 文件存在 / 对话框出现  → 成功
wshot          → 复检截图（终态证据）
  ↓
agent 汇报："已导出到 C:\...\x.csv"，附两张截图路径
```

## 9. 明确不做的架构选择

| 不做 | 原因 |
|---|---|
| 第二套 DSH / Electron 客户端 | 需要用户在 Windows 再装一遍环境，且与现有会话割裂（见 D2） |
| MCP server 形态 | 多一层协议，收益仅是"看起来标准"；纯 CLI JSON 已足够 |
| 视觉坐标系（以截图像素为准） | DPI 一变全歪；语义优先，像素兜底 |
| 跨机器远程接管 | 超出"接管我这台 PC"的需求，且安全面爆炸 |
