---
name: win-admin
description: >-
  从 WSL2/DSH 一侧接管 Windows 桌面的操作手册（/root/win-admin 工程，v1.3.0）：
  只读侦察（wdiag 环境快照、wshot 物理像素截图/区域/窗口/标尺网格、wuia UIA 树与语义查找、wwin 窗口列表/信息/激活/关闭/状态控制）、
  合成输入（winput 点击/输入/按键/长按/悬停/滚轮/拖拽、wclip 剪贴板）、等待（wwait 窗口、wait-for 控件、wait-uia 谓词）、
  元素级动作（wuia --invoke/--select/--toggle/--expand/--set-value）、复合操作（open、find-and-click、fill、click-element、hover-menu、wait-for）、
  元素地图（ops/map：编号 + 红框图 + 清单）、结果断言（click-element --expect-gone/--expect-alive）、
  坐标契约（wshot --box/--clip/--out 的 WSL 路径映射 + scale 字段）、输入回读（winput type --verify）与焦点门（type --force）、窗口族匹配（--allow-related）、
  页面正文（wuia --read-text / ops/read-text）、文本行与按文本点击（--find-text / winput --click-text）、点击效果断言（--expect-change）、
  以及守卫层（grant.json 限时授权、pause.flag 急停、audit jsonl 逐动作留痕、危险名默认拒绝）。
  当任务需要操作 Windows 图形界面（点击、输入、截图、窗口管理、UIA 自动化）时使用；纯命令行/文件操作不需要它。
user-invocable: true
---

# win-admin：从 WSL 接管 Windows 桌面（v1.3.0）

工程根目录固定在 **/root/win-admin**（WSL 内）。所有命令都在该目录下执行：

```bash
cd /root/win-admin
bash scripts/bootstrap.sh          # 首次；改了 win/*.ps1 之后要 --force
bash tests/check-m1.sh             # 自检，期望 SUMMARY fail=0
```

Windows 侧的 PowerShell 负载在 `C:/Users/Public/win-admin/app/<version>/`（bootstrap 复制），
状态在 `/root/.dsh/win-admin/`（grant.json、pause.flag、audit/YYYY-MM-DD.jsonl）。

## 0. 三条红线（无条件，任何授权都不解除）

1. 绝不在 UAC 安全桌面 / 登录界面 / 锁屏上注入输入或截图（检测到就报 `ENV_UAC_SECURE_DESKTOP` / `SESSION_LOCKED` 并退出，不重试）。
2. 绝不读写凭证、密码、聊天记录、浏览器 cookie 等敏感内容。
3. 绝不在无有效 grant 的情况下注入输入；绝不删除/覆盖用户文件；绝不改系统代理/DNS/防火墙/计划任务/自启动。

## 1. 授权：先拿到 grant，再动手

```bash
bash guard/grant.sh issue --scope shot,uia,input,file:read --minutes 30 --note "用户 m12345 要求导出表格"
bash guard/grant.sh status
bash guard/grant.sh revoke
```

- 无 grant 时：`wshot/wuia find/wuia point/wwin list|info/ops/wait-uia` 只读不拦，`winput/wclip/wwin set/wuia 动作/全部注入类 ops/` 返回 **rc=4 GUARD_NO_GRANT**。
- 用户说「停」= 立刻 `bash guard/grant.sh revoke` + `touch /root/.dsh/win-admin/pause.flag`（`guard/check.sh` 会先看 pause.flag）。
- 每条动作都会写 `audit/YYYY-MM-DD.jsonl`（时间、命令、参数摘要、结果、耗时、grant id）。
- **grant 会过期**：长任务每 1–2 小时 `bash guard/grant.sh status` 一次，过期就重开；测试套件会临时申请并还原。

## 2. 原语（全部一个 JSON 到 stdout，诊断到 stderr）

| 命令 | 用途 | 关键参数 | 成功时关键字段 |
| --- | --- | --- | --- |
| `bin/wdiag` | 环境快照 | `--json` | screen w/h、dpi、scale、session、locked、gui_available、payload version |
| `bin/wshot` | 物理像素截图 | `--out PATH` `--rect X,Y,W,H` `--box X1,Y1,X2,Y2` `--clip` `--hwnd H` `--grid N` | path、wsl_path、w、h、bytes、sha256、scale、rect、clipped |
| `bin/wuia` | UIA 树/语义查找/动作 | `--hwnd H --find-name RE --find-type RE --find-aid RE --find-class RE --enabled --on-screen --index N --limit N`；动作 `--invoke/--select/--toggle/--expand/--collapse/--focus/--get-value/--get-text/--set-value TEXT`；`--point X,Y [--point-mode auto|rect|uia]` 问坐标下是什么、`--find-text RE` 页面文本行索引（行 + rect + depth + clickable）、`--read-text` 整页正文（最长 TextPattern 文档）、预热开关 `--no-warm/--no-deepen/--warm-ms/--warm-passes`；`--depth/--max` 不传时自动（find 20 / tree 3，首次落空自动加深到 28） | nodes[]（name/type/aid/class/rect/enabled/patterns[]）、`lines[]`/`text`/`chars`、`passes/warmMs/depthUsed/deepened/warmRetries`、动作返回回读状态 |
| `bin/wwin` | 窗口表/信息/激活/关闭/状态 | `list` `info --hwnd H` `focus --hwnd H` `close --hwnd H` `state --hwnd H` `set --hwnd H [--state max|restore|min|normal] [--x --y --w --h] [--topmost on|off] [--yes]` | windows[]、before/after placement 与 rect |
| `bin/winput` | 合成输入 | `click X Y` `type --stdin` `type --text-b64` `type --text-file`（WSL/Windows 路径均可）`type --verify [--verify-mode exact|contains]` `key ctrl+s [--hold MS]` `keydown/keyup/releaseall` `hover X Y [--dwell MS]` `wheel --at X Y --delta N` `drag X1 Y1 X2 Y2`、`click --click-text RE [--text-index N]`（按页面文本点）、`--expect-change title|rect [--timeout MS]`（点击效果断言）、`type --force`（越过焦点门，旧行为）；均带 `--expect-hwnd H --yes`，可加 `--allow-related` | ok、point、injected、`hover` 返回落点元素、`verify{}` 回读、`matched` |
| `bin/wclip` | 剪贴板 | `set --text T` `set --text-file F` `set --native-path P`（`/mnt/c/...` → `C:\...`）`get` | text、bytes |
| `bin/wwait` | 等窗口出现 | `--title RE --timeout 10` | hwnd、elapsed_ms |

退出码：**0 成功 / 2 参数错 / 3 环境或前置不满足 / 4 守卫拒绝 / 5 执行失败**，`code` 字段是机器可读原因（`ENV_NO_NODE`、`ENV_WINDOW_MISMATCH`、`ENV_STATE_UNCHANGED`、`ENV_NO_PATTERN`、`ENV_TIMEOUT`、`ENV_ELEMENT_NOT_ACTIONABLE`、`ENV_DANGEROUS_ACTION`、`SESSION_LOCKED` 等）。

## 3. 复合操作（默认 dry-run，`--yes` 才真动手）

```bash
ops/open         --exe notepad --args "C:/Users/Public/win-admin/tmp/a.txt" --title "a.txt" --timeout 10 --yes
ops/find-and-click --hwnd 1234 --name "^保存$" --type Button --yes
ops/fill         --hwnd 1234 --name "文本编辑器" --text "中文 ok" --yes
ops/click-element --hwnd 1234 --name "^展开$" [--strategy invoke|click] [--verify value:RE|gone:RE|alive] \
                 [--expect-gone NAME | --expect-alive NAME] [--expect-timeout MS] [--allow-related] --yes
ops/map          --hwnd 1234 [--out /tmp/m.png] [--text] [--depth 16] [--min-w 20]
ops/wait-uia     --hwnd 1234 --name "^发布$" [--enabled] [--value RE] [--gone] --timeout 8000
ops/hover-menu   --at 640,420 --pick "^二级项$" --dwell 800 --yes
ops/wait-for     --hwnd 1234 --uia-name "^是否要将更改保存" --timeout 5
```

- 不给 `--yes` 时返回 `dryRun:true` 与将要点击的 **point** / 将匹配的控件，先给用户看再执行。
- **点完必须证明有后果**：`winput click X Y --expect-change title --timeout 3000`（EVENT 只支持 `title`/`rect`）。超时 rc=3 `ENV_NO_EFFECT`，JSON 带 `before/after/observed/elapsedMs`；每次 click 都带 `hit{}`（`actionable` 为真时自动换成最近的可点祖先，叶节点原件在 `hit.raw`）。
- **不想猜坐标就按文本点**：`winput click --click-text '^投稿$' --text-index 0`（行来自 `wuia --find-text`，点在行中心；行在视口外会 `ENV_TEXT_OFFSCREEN` 拒绝）。坐标的语义安全校验由 `ops/click-element` 负责：落点属于别的窗口/别的控件时 rc=3 `ENV_HIT_MISMATCH`，不注入。
- `click-element` 优先 **UIA invoke**（不移动光标、被遮挡也能用），没有 Invoke 才回落到「焦点 + 点中心」；**动作后必须校验**（默认 alive，可用 `--verify value:RE` / `gone:RE`）。
- `click-element` 对名字含 `删除|购买|提交|支付|下单|格式化|reset` 的节点**默认拒绝**（`ENV_DANGEROUS_ACTION` rc=3），确属本意才加 `--allow-danger`。
- `hover-menu` 是「悬停 → 等菜单项出现（UIA 名字）→ 点它」；菜单项不出现就是 `ENV_MENU_NOT_SHOWN`，不要靠坐标猜。
- `find-and-click`/`fill`/`click-element` 的 click 分支一定**先 wwin focus 再点**：被遮挡时 winput 的 S7 断言会拒绝点击（`ENV_WINDOW_MISMATCH`），这是设计而非 bug。
- `fill` 的成功判据是 **readback 与输入逐字符相同**（`matches:true`）；只标 injected 不算成功。
- **看图和点坐标之间还差一条命令时用 `ops/map`**：它一次 UIA 枚举把「图上的框 + 编号」和「能点的 rect」对上，编号按 (y,x) 阅读顺序，红框=可操作（有 Invoke/Toggle/SelectionItem/ExpandCollapse/Value/RangeValue/ScrollItem 之一），灰框=只能看。`--text` 零截图，只出清单。**只读**：只需 `--scope shot,uia`。
- `--expect-gone NAME` / `--expect-alive NAME` 把「点完界面该变成什么样」写进命令：不成立即 `ENV_EXPECT_FAILED` rc=3（与 `--verify` 的 `ENV_TIMEOUT` 区分）。两者与 `--verify` 互斥。
- `--allow-related`：目标与命中窗口互为祖先/后代（典型的「文件名无效」子对话框）才算匹配，成功 JSON 标 `matched:"related"`。**默认关**，默认仍是严格相等。
- `ops/*` 成功 JSON 都带 `statePreserved:true`：聚焦只改前台，不改窗口的 placement（最大化窗口不会被 `SW_RESTORE` 打回窗口化）。

## 4. 五步配方（通用任务骨架）

1. **看**：`bin/wshot --out /tmp/s.png`（要看坐标就加 `--grid 100`，`--out` 给 WSL 路径会自动映射并回拷）读图确认桌面；`bin/wdiag` 确认未锁屏、分辨率与 DPI；网页正文用 `ops/read-text --hwnd H` 或 `bin/wuia --hwnd H --read-text`。
2. **定窗**：`bin/wwin list`，或用 `ops/wait-for --title`；需要摆位置就 `bin/wwin set --hwnd H --state max --yes`（回读 before/after）。
3. **定控件**：`bin/wuia --hwnd H --find-name "关键字" --find-type Button --enabled --on-screen`；控件没名字/名字重复就 `ops/map --hwnd H`（拿编号清单或红框图），用 `ops/click-element --find-aid` 按编号对应的 aid/name 点；实在没有语义信息才退化为 `--point X,Y` 或截图坐标。
4. **动**：`ops/click-element`（语义+校验）> `ops/find-and-click` > `bin/winput`（坐标是兜底）。输入文本一律 `--stdin`/`--text-b64`。
5. **验**：`bin/wuia --get-value/--get-text` 读回、`ops/wait-uia --value RE` 等谓词、`winput --expect-change title`（点击有后果）、再截一张图、或检查落盘文件；不验等于没做。

## 5. 踩过的坑（照抄规避）

| 坑 | 规避 |
| --- | --- |
| 改 `win/*.ps1` 后行为不变 | 必须 `bash scripts/bootstrap.sh --force`（负载是复制到 Windows 侧才生效，K28） |
| 中文输出乱码 / 脚本里的中文变 `鍒犻櫎` | PowerShell 5.1 按 ANSI 读**无 BOM** 的 .ps1；含中文的 .ps1 必须存成 **UTF-8 with BOM**（K39） |
| hwnd 传进 jq 报 invalid JSON | 先 `H=$((H))` 转十进制，`jq --argjson` 不认 `0x` |
| 点击被拒 `ENV_WINDOW_MISMATCH` | 目标被遮挡：先 `bin/wwin focus --hwnd H`，再点；不要绕过断言 |
| 点击/输入命令「成功」但页面没反应 | Windows 原生对话框/弹出层可能不在目标窗口线程；用 `ops/wait-uia --gone` 或状态读回证明变化，不要只看 rc=0 |
| 最大化判不出来 | 最大化窗口 `GetWindowRect` 是负偏移越界框，必须看 `GetWindowPlacement().showCmd==3`；用 `wwin state` |
| 记事本「开了新文件」但 hwnd 没变 | Win11 记事本单进程多标签，标题会变；按标题匹配而不是按 pid |
| 等模态对话框等不到窗口 | 保存提示是**子窗口**，用 `ops/wait-for --uia-name` / `ops/wait-uia`；`wwin list` 看不到它 |
| alt+F4 关不掉，弹保存框 | 用 `bin/wwin close --hwnd H`（WM_CLOSE 交给应用自己决定存不存） |
| 坐标差 1.5 倍 | 一律物理像素；payload 首行 `SetProcessDpiAwarenessContext([IntPtr]-4)`，wdiag 的 screen 应与真实分辨率一致 |
| 文本含 `'`/`"`/`$`/反引号，`type --text` 静默失败 | 走 `--stdin`（推荐）或 `--text-b64`；空文本现在会报 `ARG_EMPTY_TEXT` rc=2（K37） |
| 下拉框/二级菜单点不开 | 先 `--expand`（UIA ExpandCollapsePattern），或 `ops/hover-menu --pick 项名`；仍不可达就选一级项并在报告里写明 |
| 点完「成功」但界面没变 / 标签被误删 | 用 `--expect-gone/--expect-alive` 写死预期；chip 增删不要复用上一次坐标，每轮重新 `wuia --find-name` 定位（K49 的口径坑同样适用） |
| 窗口自己从最大化变回窗口化 | v1.1 的 `Set-WaForeground` 无条件 `SW_RESTORE` 干的（K51）；v1.2 已修，旧脚本若自己写 `ShowWindow(9)` 要删掉 |
| 按界面代码里的坐标点，差 1.5 倍 | DIP ≠ 物理像素（K53）：150% 缩放差 1.5 倍；坐标只从 UIA `rect` 或 `wwin state` 取 |
| `--find-name .` 数出来的元素比看见的少 | 名字为空的控件（Edit/ComboBox/容器）不会被 `--find-name` 命中（K49）；数元素用 `--find-type .` |
| 子对话框里的按钮点不动（`ENV_WINDOW_MISMATCH`） | 它是目标的子/父窗口：加 `--allow-related`；报错 JSON 的 `hit` 会告出「挡在前面的是谁」 |

| 页面点了没反应，却报 `ok:true` | v1.3 前 click 不判后果：加 `--expect-change title`（或 `rect`），超时 `ENV_NO_EFFECT`；命中的是谁看 `hit{}`，`hit:null` 表示落点没有元素（`hitReason` 给原因） |
| 焦点在按钮上 `type` 却「成功」了 | v1.3 起 type 先查焦点：不可编辑 → rc=3 `ENV_NO_FOCUS`；可读但值没变 → rc=3 `ENV_NO_EFFECT`。确实要往自绘/只读控件硬塞文本才加 `--force`（JSON `forced:true`） |
| `winps -f` 报 `字符: 21 赋值表达式无效` / 中文乱码 | `win/*.ps1`（winps payload）**不能**带 BOM，否则双 BOM（K68）；需要 BOM 的只有 `tests/helpers/*.ps1`（`powershell -File` 启动，K39） |
| 页面正文 `jq --arg` 报 `Argument list too long` | 大文本（150 KB+）不能进 shell 参数：用 `--rawfile`/`--slurpfile` 从临时文件读（K69）；`--argjson` 也不吃 `0x` 前缀 hwnd |
| 所有 `wwin focus` 都 `ENV_NOT_FOREGROUND` | 前台被自己的探针控制台抢走了（K67）：关掉它（`bin/wwin close --hwnd <控制台>`）后 focus 立刻恢复 |
| `--find-text` 前几行 rect 是 -48412 这种负坐标 | 那是滚出视口的内容（K70）：按 `rect.y` 在窗口内且 `depth>=8` 过滤，`--click-text` 对视口外行会拒绝 |

## 6. 什么时候应该拒绝

- 桌面锁定/断开/黑屏：`wdiag` 报 `locked:true` 或 `gui_available:false` → 停，告诉用户。
- 用户不在、无人确认的批量点击：不做；用户只授权了 scope 之外的动作：不做。
- 需要 UAC 提权：只提示用户手动点，绝不自动点。
- 目标控件需要「理解业务」才能判断对错（如转账、删除、提交订单）：先 dry-run 把 point 与控件名给用户确认，并接受 `ENV_DANGEROUS_ACTION` 的默认拒绝。

## 7. 长任务：用 mission，不要用「记忆里的计划」

任何超过 3 步、可能中途断掉的任务，先用 `bin/wmission` 建可恢复执行单元（`docs/13`）：

```bash
bin/wmission init <id> --title "任务名"
bin/wmission add  <id> --title "步骤 1" --verify "怎么判它成了"
bin/wmission start <id> 1
bin/wmission done  <id> 1 --evidence "实测证据（数字/命令输出）" --file 产物路径
bin/wmission status <id> [--json]      # 断线后第一件事
bin/wmission resume <id>               # 连续失败 3 次返回 ESCALATE rc=3，停下报告用户
```

规则：**done 必须带证据**；没有证据的「完成了」等于没做；每步证据落 `missions/<id>/evidence/`。
mission **不是**新的授权通道——守卫层照旧（grant/pause/audit）。

## 8. 网页数据采集（JS 渲染的页面）

1. **导航走 URL**：`winput key ctrl+l` → `winput type --stdin` → `enter`。坐标点导航链接经常点偏（实测点「购物车」掉进收藏夹）。
2. **不要指望这几条路**：`ctrl+u` 源码只有空壳；F12 控制台收不到 SendInput 打的字；CDP 端口默认不监听（要 CDP 只能走 cdp-hub 的受管实例，见 `docs/18`）。
2b. **整页正文就一条命令**：`ops/read-text --hwnd H`（内部走 `wuia --read-text`：RawView 遍历取最长 TextPattern 文档，实测用户 Edge 156–173 KB 一次拿到），无文本/非 Chromium 才回落剪贴板（`source:'clip'`，可 `--force-clip` 直接验回落通道）。需要局部文本时 `wuia --find-text 'RE'` 拿文本行 + rect；`display:none` 的内容会被正确剔除。
2c. **网页元素在 a11y 树 depth 12–20**：一旦「找不到」，先想「搜得不够深」而不是「页面没有」。v1.3 起 `wuia` 不必手写深度：不传 `--depth` 时 find 默认 20、落空自动加深到 28（JSON `deepened:true`），并且**冷暖树预热**（冷进程首查实测 542 节点 / depth 20；用 `passes/warmRetries` 诊断，`--no-warm` 回到 v1.2 行为）。Chromium 的 a11y 树是**异步**长出来的，刚出窗口时可能只有 chrome——重试预算用 `--warm-passes`/`--warm-ms` 调。
2d. **页面内元素可以真动作**：`wuia --find-aid inp --set-value '文本'` 写的是真 DOM 值（可用 CDP 交叉验证）；`ops/click-element --name '^按钮名$' --yes` 走 Invoke 触发真点击。不要再靠截图猜坐标。
3. **懒加载靠多轮累积**：`ctrl+a` → `ctrl+c` → `wclip get` → `escape` → `pagedown`，重复 20–30 轮；单轮只能拿到视口内的几条。
4. **剪贴板是 CRLF**：`tr -d '\r'` 之后再 grep，否则 `^锚点$` 永远不匹配。
5. **页面文本里的「失效/缺货」字样每行都有**（CSS 隐藏），**不能**用来判状态；状态只能看截图。
6. **缩放会改 DOM 结构**：25% 时操作列整列消失；采集期间固定缩放（`ctrl+0` 复位）。
7. **视觉做第二来源**：50% 缩放下逐屏截图，比对价格/数量；两源不一致时以截图为准并记差异。
8. **注入的是前台窗口**：`winput` 的 `--expect-hwnd` 只断言不重定向，发键前先 `bin/wwin focus`。

完整实例（真实任务，含四个数字对不上的处理方式）：`missions/taobao-cart-2026-10-21/REPORT.md`。

## 9. 投稿类长表单（B 站实测，2026-10-23）

真实绕路记录见 `docs/16-usage-feedback.md`；v1.1 后每条都有对应工具：

1. **窗口先摆好**：`wwin set --hwnd H --state max --yes`，别再写 PowerShell 调 ShowWindow。
2. **标题/简介用安全通道**：`bin/winput type --stdin <<'TXT' … TXT`；含半角单引号的标题一律不要走 `--text`。
3. **上传文件对话框**：`wclip set --native-path "C:/绝对路径"`（自动转反斜杠，原生对话框只认 `\`）→ `winput key ctrl+v` → `enter`（原生对话框只吃粘贴，不吃 type）。若弹「文件名无效」，先看是不是缺了 `--native-path`。
4. **平台默认标签**：先逐个删（选中 + `Delete`），再加自己的（输入 + `Enter`）；每删一个都重新定位、并带 `--expect-gone <标签名>` 断言它真的没了（不要复用上一次坐标，chip 会漂移）。
5. **分区/分类下拉**：`wwin` 摆好窗口后用截图定位一级项（`--grid 100` 读坐标），能 `--expand` 就走 UIA；
   **二级 hover 菜单在 Chromium 里可能不进 UIA 树**：`ops/hover-menu --at X,Y --pick RE` 不行就只选一级项，并在报告里写明「二级不可达」，不要用坐标硬猜（c0 会话在这里耗了 300+ 行）。
6. **提交前**：截图 + `wuia --get-text` 核对标题/分区/封面，再点「立即投稿」；投稿后用进度页 URL 取 BV 号作为证据。

## 10. 已知局限（v1.3.0）

- 单次原语经 `winps` 桥约 600–750 ms，别一步一调，能合并的用 `ops/`。
- 前台锁：Windows 可能拒绝后台进程抢焦点，发键前必须确认前台窗口。
- ~~Edge 的 UIA 树只有 ~53 个节点，页面内容读不到~~（**v1.1.0 已纠正**：那是默认深度 10 的观测；depth 16 下整页正文与页面内按钮都可读可点，见 `docs/18`）。
- `wuia` 的 `--get-text` 对 WPF `TextBlock` 回落到 `Name`（无 TextPattern，K38）。
- Chromium 的二级 hover 菜单不保证进 UIA 树：`hover-menu` 失败即 `ENV_MENU_NOT_SHOWN`，属环境限制不属 bug。
- `ops/map` 的编号只在同一次调用内稳定：界面变了就重新 `map`，别跨图复用 idx。
- `type --verify` 依赖焦点的 Value/Text pattern：Chromium 的 `contenteditable` 富文本读不到会报 `ENV_TEXT_UNVERIFIABLE`（只在校验模式下报，不影响普通 type）。
- `--expect-change` 只认 `title`/`rect`：网页内 DOM 变化不在窗口标题/矩形里体现时，用 `--verify value:RE` 或再读一遍树，别把「title 没变」当成「点击无效」。
- 冷进程首查 Chromium 仍要 2–3 s（预热 1–3 遍）：实时性要求高的循环里尽量复用一次 `find-text` 结果，而不是每次重起进程。
- `--click-text` 的行来自 a11y 树，和屏幕像素不是同一坐标系语义：视口外行会被 `ENV_TEXT_OFFSCREEN` 拒绝，滚动后要重新 `--find-text`。
- 审计账本同用户可改（K22），真隔离未做。
