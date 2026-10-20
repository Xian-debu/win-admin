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

| 原语 | 职责 | 输入 | 输出（stdout，单 JSON） | 状态 |
|---|---|---|---|---|
| `wdiag` | 前置体检 | — | `{ok,version,host,user,os,session,desktop,screen,dpiMode,foreground,powershell,guard,wsl}` | ✅ M1 |
| `wshot` | 截图 | `--rect x,y,w,h` / `--out PATH` | `{ok,path,wsl_path,x,y,w,h,bytes,screen,dpiMode}` | ✅ M1 |
| `wuia` | 窗口/控件树/取值 | `--list` / `--hwnd H` / `--title REGEX` / `--depth N` / `--max N` / `--filter S` / `--value`（读文本框内容：ValuePattern 优先，退化 TextPattern） | `{ok,mode,hwnd,depth,maxNodes,count,truncated,nodes:[{depth,name,type,aid,class,rect{x,y,w,h},enabled,offscreen}]}` | ✅ M1 |
| `wwin` | 窗口查询/操作 | `list` / `info --hwnd 0x...`（focus 与 layout 分别合入 `winput --focus` 和 `drag`） | `{ok,action:"info",window:{hwnd,title,class,pid,process,visible,minimized,rect}}`；list 同 M1 | ✅ M1(list) / M2(info) |
| `winput` | 合成输入 | `move` / `click` / `dclick` / `drag` / `key` / `type`；默认 dry-run，`--yes` 才注入；点击类强制 `--expect-hwnd` | `{ok,action,dryRun,injected,point:{x,y},target:{hwnd,title}}` | ✅ M2 2026-10-21 |
| `wclip` | 剪贴板 | `get` / `set --text T` / `set --text-file F` / `clear` | `{ok,action,text,len}` | ✅ M2 2026-10-21 |
| `wwait` | 等待窗口出现 | `--title REGEX` / `--hwnd 0x...`，可选 `--timeout S` `--interval MS` | `{ok,mode:"wait",window{hwnd,hwnd_dec,title},elapsed_ms,polls,interval_ms,at_epoch_ms}`；超时 exit 3 `ENV_WAIT_TIMEOUT` | ✅ M2 2026-10-21 |

**实现细节（M1 实测踩到，写在这里免得后人再踩）：**

1. `bin/*` 是 bash 薄壳，真正干活的是 Windows 侧 `win/<name>.ps1`；经 `lib/common.sh` 的
   `wa_run` 用 `winps -r -f <WSL 路径> -Core <Windows 路径>` 调起。
2. **`winps -f` 收的是 WSL 路径**（它自己 `cat` 后再转交给 `powershell.exe -File`），
   不是 `C:\...`；传错会得到 `cat: no such file`。
3. 因为落点是 Windows 临时目录，**`$PSScriptRoot` 是 temp 目录而不是载荷目录**，
   所以载荷不能靠 `$PSScriptRoot` 找 `wa-core.ps1`，必须由 `-Core` 显式传入。
4. 载荷脚本第一件事是 `[Console]::OutputEncoding=[Text.Encoding]::UTF8`（或 dot-source 已设好的
   `wa-core.ps1`），末尾 `ConvertTo-Json -Compress`；否则 PS 5.1 按 OEM 936 输出（K1）。
5. 所有 Win32 `*W` 系列 DllImport 必须写 `CharSet = CharSet.Unicode`，缺了会把 UTF-16 缓冲按
   ANSI 读，表现为标题乱码 + 类名只剩一个字母（M1 的 B2）。
6. `EnumWindows` 在本机命中 474 个顶层窗口，逐个 `Get-Process` 会让 `wwin` 慢到 12 s；
   必须先做廉价预筛（`IsWindowVisible` + 标题非空）再构造信息 → 743 ms。

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

- **谁签发**：只允许 `guard/grant.sh issue` 写；`note` 必填，必须摘用户原话（`调研 ≠ 授权`）。
- **谁校验**：每个输入类原语启动时第一件事读它；过期 / `revoked` / scope 不含 → exit 4。
- **签名（M3）**：`sig = sha256(`~/.dsh/win-admin/.grantkey` + `jq -cS '{issued,expires,scope,note,revoked}'`)`；
  缺 key / 缺 sig / 不匹配 → `GUARD_TAMPERED` exit 4。挡误改与事故，**不**挡同用户恶意进程（D23）。
- **为什么不用系统权限**：本会话已是 `danger-full-access`，系统层拦不住任何东西；
  令牌的意义是**留痕 + 给用户一个真能拧的旋钮**（删文件即撤销）。

### 5.2 急停双通道

| 通道 | 机制 | 生效范围 |
|---|---|---|
| 软（随时可用） | 存在 `pause.flag` 就拒绝执行输入 | 每个原语读一次；用户/agent 都能建这个文件 |
| 硬 | **不做**（用户确认「急停就按你说的」，D7 / Q4 关闭） | — |

**软通道是唯一通道**：用户在终端敲一句 `touch ~/.dsh/win-admin/pause.flag`，
或 agent 自己触发，下一个原语立刻停。代价是"手离开键盘时停不了"——这是用户明确选择。

### 5.3 审计 `~/.dsh/win-admin/audit/YYYY-MM-DD.jsonl`

一次动作一行，只追加（实现见 `lib/audit.sh`）：

```json
{"ts":"2026-10-21T00:58:03+08:00","ts_epoch_ms":1792515483210,"tool":"winput",
 "args":["click","1200","880","--yes"],"result":"GUARD_NO_GRANT","exit":4,"duration_ms":112,
 "grant":{"expires":null,"note":null},"pid":40231,"version":"0.1.0"}
```

- `bin/winput` 的**每条退出路径**都落一行（ok / dryrun / ARG_* / ENV_* / GUARD_*），用 EXIT trap 保证。
- **fail closed**：审计写失败且动作原本成功 → 退出码强制 5（`EXEC_AUDIT_FAILED`），宁可不动。
- `guard/grant.sh` 的 issue/revoke/pause/resume 也各记一行（`tool:"grant"`）。
- 限制：账本是事后证据，同用户可删改（D22）。

### 5.4 测试钩子（只让系统更严格）

`C:/Users/Public/win-admin/tmp/force-desktop.txt`：内容非空且 ≠ `Default` 时，
`Get-WaDesktopInfo` 直接判为"已锁定/安全桌面"（`reason:"test-hook"`）。
只能声明一个**非 Default** 桌面名，永远不能把真实锁屏覆盖成可用；仅 `tests/check-m3.sh` 使用（D21 / SG-0002）。

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

## 10. M4 落地形态（2026-10-21 实现）

`ops/` 四件与 `SKILL.md` 已按 §6/§7 的契约落地，实际形态与本设计一致的部分：

| 契约 | 实现 |
|---|---|
| 单 JSON 到 stdout，诊断到 stderr | 全部 ops 一致；`jq` 直接消费 |
| 退出码 0/2/3/4/5 | `lib-ops.sh:wa_exit_for` + 各脚本显式 code |
| 默认 dry-run | `ops/open|fill|find-and-click` 无 `--yes` 只输出计划（含 point/node） |
| 全部过 guard | `op_pause_gate input|write` 在每个真实动作前调用 |
| 全部写审计 | `wa_audit_init ops-<name>` + `WA_AUDIT_RESULT` |
| 先证后动 | 点击前 `wwin focus`；注入后 UIA 读回（fill.matches）或落盘检查 |

与原设计的三处偏差：

1. **新增 `win/waopen.ps1`**：启动程序并等窗口这件事放进 PowerShell 一次完成（避免 bash 轮询 + 多次 700ms 桥调用）。
2. **`wwin` 扩了 focus/close**：不是原计划的独立原语，但两者都不产生合成输入，属于"窗口管理层"，放 `wwin` 更内聚。
3. **L4 从"计划"变成"已安装"**：`SKILL.md` + `scripts/install-skill.sh`，安装到 `~/.dsh/skills/win-admin` 后立即进入会话技能目录（实测）。
