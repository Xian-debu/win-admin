---
name: win-admin
description: >-
  从 WSL2/DSH 一侧接管 Windows 桌面的操作手册（/root/win-admin 工程，v1.1.0）：
  只读侦察（wdiag 环境快照、wshot 物理像素截图/区域/窗口/标尺网格、wuia UIA 树与语义查找、wwin 窗口列表/信息/激活/关闭/状态控制）、
  合成输入（winput 点击/输入/按键/长按/悬停/滚轮/拖拽、wclip 剪贴板）、等待（wwait 窗口、wait-for 控件、wait-uia 谓词）、
  元素级动作（wuia --invoke/--select/--toggle/--expand/--set-value）、复合操作（open、find-and-click、fill、click-element、hover-menu、wait-for）、
  以及守卫层（grant.json 限时授权、pause.flag 急停、audit jsonl 逐动作留痕、危险名默认拒绝）。
  当任务需要操作 Windows 图形界面（点击、输入、截图、窗口管理、UIA 自动化）时使用；纯命令行/文件操作不需要它。
user-invocable: true
---

# win-admin：从 WSL 接管 Windows 桌面（v1.1.0）

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
| `bin/wshot` | 物理像素截图 | `--out PATH` `--rect X,Y,W,H` `--hwnd H` `--grid N` | path、wsl_path、w、h、bytes、sha256、grid |
| `bin/wuia` | UIA 树/语义查找/动作 | `--hwnd H --find-name RE --find-type RE --find-aid RE --find-class RE --enabled --on-screen --index N --limit N`；动作 `--invoke/--select/--toggle/--expand/--collapse/--focus/--get-value/--get-text/--set-value TEXT`；`--point X,Y` 问坐标下是什么 | nodes[]（name/type/aid/class/rect/enabled/patterns[]）、动作返回回读状态 |
| `bin/wwin` | 窗口表/信息/激活/关闭/状态 | `list` `info --hwnd H` `focus --hwnd H` `close --hwnd H` `state --hwnd H` `set --hwnd H [--state max|restore|min|normal] [--x --y --w --h] [--topmost on|off] [--yes]` | windows[]、before/after placement 与 rect |
| `bin/winput` | 合成输入 | `click X Y` `type --stdin` `type --text-b64` `type --text-file` `key ctrl+s [--hold MS]` `keydown/keyup/releaseall` `hover X Y [--dwell MS]` `wheel --at X Y --delta N` `drag X1 Y1 X2 Y2`，均带 `--expect-hwnd H --yes` | ok、point、injected、`hover` 返回落点元素 |
| `bin/wclip` | 剪贴板 | `set --text T` `get` | text、bytes |
| `bin/wwait` | 等窗口出现 | `--title RE --timeout 10` | hwnd、elapsed_ms |

退出码：**0 成功 / 2 参数错 / 3 环境或前置不满足 / 4 守卫拒绝 / 5 执行失败**，`code` 字段是机器可读原因（`ENV_NO_NODE`、`ENV_WINDOW_MISMATCH`、`ENV_STATE_UNCHANGED`、`ENV_NO_PATTERN`、`ENV_TIMEOUT`、`ENV_ELEMENT_NOT_ACTIONABLE`、`ENV_DANGEROUS_ACTION`、`SESSION_LOCKED` 等）。

## 3. 复合操作（默认 dry-run，`--yes` 才真动手）

```bash
ops/open         --exe notepad --args "C:/Users/Public/win-admin/tmp/a.txt" --title "a.txt" --timeout 10 --yes
ops/find-and-click --hwnd 1234 --name "^保存$" --type Button --yes
ops/fill         --hwnd 1234 --name "文本编辑器" --text "中文 ok" --yes
ops/click-element --hwnd 1234 --name "^展开$" [--strategy invoke|click] [--verify value:RE|gone:RE|alive] --yes
ops/wait-uia     --hwnd 1234 --name "^发布$" [--enabled] [--value RE] [--gone] --timeout 8000
ops/hover-menu   --at 640,420 --pick "^二级项$" --dwell 800 --yes
ops/wait-for     --hwnd 1234 --uia-name "^是否要将更改保存" --timeout 5
```

- 不给 `--yes` 时返回 `dry_run:true` 与将要点击的 **point** / 将匹配的控件，先给用户看再执行。
- `click-element` 优先 **UIA invoke**（不移动光标、被遮挡也能用），没有 Invoke 才回落到「焦点 + 点中心」；**动作后必须校验**（默认 alive，可用 `--verify value:RE` / `gone:RE`）。
- `click-element` 对名字含 `删除|购买|提交|支付|下单|格式化|reset` 的节点**默认拒绝**（`ENV_DANGEROUS_ACTION` rc=3），确属本意才加 `--allow-danger`。
- `hover-menu` 是「悬停 → 等菜单项出现（UIA 名字）→ 点它」；菜单项不出现就是 `ENV_MENU_NOT_SHOWN`，不要靠坐标猜。
- `find-and-click`/`fill`/`click-element` 的 click 分支一定**先 wwin focus 再点**：被遮挡时 winput 的 S7 断言会拒绝点击（`ENV_WINDOW_MISMATCH`），这是设计而非 bug。
- `fill` 的成功判据是 **readback 与输入逐字符相同**（`matches:true`）；只标 injected 不算成功。

## 4. 五步配方（通用任务骨架）

1. **看**：`bin/wshot --out /tmp/s.png`（要看坐标就加 `--grid 100`）读图确认桌面；`bin/wdiag` 确认未锁屏、分辨率与 DPI。
2. **定窗**：`bin/wwin list`，或用 `ops/wait-for --title`；需要摆位置就 `bin/wwin set --hwnd H --state max --yes`（回读 before/after）。
3. **定控件**：`bin/wuia --hwnd H --find-name "关键字" --find-type Button --enabled --on-screen`；拿不到再退化为 `--point X,Y` 或截图坐标。
4. **动**：`ops/click-element`（语义+校验）> `ops/find-and-click` > `bin/winput`（坐标是兜底）。输入文本一律 `--stdin`/`--text-b64`。
5. **验**：`bin/wuia --get-value/--get-text` 读回、`ops/wait-uia --value RE` 等谓词、再截一张图、或检查落盘文件；不验等于没做。

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
2b. **正文优先走 UIA 的 TextPattern**（比剪贴板快、不污染剪贴板）：`bin/wuia --hwnd H --find-aid RootWebArea --get-text --depth 16` 拿到整页文本（实测 347 字符 vs 剪贴板 353，含 textarea/input 当前值；`document.body.innerText` 反而不含表单值）。`display:none` 的内容会被正确剔除。
2c. **网页元素在 a11y 树 depth 12–13**：一旦「找不到」，先想「搜得不够深」而不是「页面没有」。`ops/click-element` / `ops/wait-uia` 默认会在首次落空时自动加深一次（JSON 里 `deepened:true`）；直接调 `wuia` 时要显式 `--depth 16 --max 6000`。Chromium 的 a11y 树是**异步**长出来的，刚出窗口时可能只有 chrome——读页面用 `ops/wait-uia` 轮询，别一次性 find。
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
3. **上传文件对话框**：`wclip set --text "C:/绝对路径"` → `winput key ctrl+v` → `enter`（原生对话框只吃粘贴，不吃 type）。
4. **平台默认标签**：先逐个删（选中 + `Delete`），再加自己的（输入 + `Enter`）；删完用 `wuia --get-text` 或截图确认。
5. **分区/分类下拉**：`wwin` 摆好窗口后用截图定位一级项（`--grid 100` 读坐标），能 `--expand` 就走 UIA；
   **二级 hover 菜单在 Chromium 里可能不进 UIA 树**：`ops/hover-menu --at X,Y --pick RE` 不行就只选一级项，并在报告里写明「二级不可达」，不要用坐标硬猜（c0 会话在这里耗了 300+ 行）。
6. **提交前**：截图 + `wuia --get-text` 核对标题/分区/封面，再点「立即投稿」；投稿后用进度页 URL 取 BV 号作为证据。

## 10. 已知局限（v1.1.0）

- 单次原语经 `winps` 桥约 600–750 ms，别一步一调，能合并的用 `ops/`。
- 前台锁：Windows 可能拒绝后台进程抢焦点，发键前必须确认前台窗口。
- ~~Edge 的 UIA 树只有 ~53 个节点，页面内容读不到~~（**v1.1.0 已纠正**：那是默认深度 10 的观测；depth 16 下整页正文与页面内按钮都可读可点，见 `docs/18`）。
- `wuia` 的 `--get-text` 对 WPF `TextBlock` 回落到 `Name`（无 TextPattern，K38）。
- Chromium 的二级 hover 菜单不保证进 UIA 树：`hover-menu` 失败即 `ENV_MENU_NOT_SHOWN`，属环境限制不属 bug。
- 审计账本同用户可改（K22），真隔离未做。
