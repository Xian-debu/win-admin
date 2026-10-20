---
name: win-admin
description: >-
  从 WSL2/DSH 一侧接管 Windows 桌面的操作手册（/root/win-admin 工程）：
  只读侦察（wdiag 环境快照、wshot 物理像素截图、wuia UIA 树与控件搜索、wwin 窗口列表/信息/激活/关闭）、
  合成输入（winput 点击/输入/按键/拖拽、wclip 剪贴板）、等待（wwait 窗口、wait-for 控件）、
  复合操作（open 启动并等窗口、find-and-click 按语义找控件并点击、fill 点击+全选+粘贴+读回校验、wait-for），
  以及守卫层（grant.json 限时授权、pause.flag 急停、audit jsonl 逐动作留痕）。
  当任务需要操作 Windows 图形界面（点击、输入、截图、窗口管理、UIA 自动化）时使用；
  纯命令行/文件操作不需要它。
user-invocable: true
---

# win-admin：从 WSL 接管 Windows 桌面

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

- 无 grant 时：`wshot/wuia/wwin` 属只读不拦，`winput/wclip/wait-for --uia-name` 与全部 `ops/` 会返回 **rc=4 GUARD_NO_GRANT**。
- 用户说「停」= 立刻 `bash guard/grant.sh revoke` + `touch /root/.dsh/win-admin/pause.flag`（`guard/check.sh` 会先看 pause.flag）。
- 每条动作都会写 `audit/YYYY-MM-DD.jsonl`（时间、命令、参数摘要、结果、耗时、grant id）。

## 2. 原语（全部一个 JSON 到 stdout，诊断到 stderr）

| 命令 | 用途 | 关键参数 | 成功时关键字段 |
| --- | --- | --- | --- |
| `bin/wdiag` | 环境快照 | `--json` | screen w/h、dpi、scale、session、locked、gui_available、payload version |
| `bin/wshot` | 物理像素截图 | `--out PATH` `--hwnd H`(可选) | out、w、h、bytes、hwnd |
| `bin/wuia` | UIA 树/控件搜索 | `--hwnd H --name RE --type RE --depth 8 --max 2000` `--value`(读文本) | nodes[]（name/type/rect/automation_id/enabled/offscreen）或 value |
| `bin/wwin` | 窗口表/信息/激活/关闭 | `list` `info --hwnd H` `focus --hwnd H` `close --hwnd H` | windows[]、foreground、requested |
| `bin/winput` | 合成输入 | `click X Y` `type --text T` `key ctrl+s` `drag X1 Y1 X2 Y2`，均带 `--expect-hwnd H --yes` | ok、point、injected |
| `bin/wclip` | 剪贴板 | `set --text T` `get` | text、bytes |
| `bin/wwait` | 等窗口出现 | `--title RE --timeout 10` | hwnd、elapsed_ms |

退出码：**0 成功 / 2 参数错 / 3 环境或前置不满足 / 4 守卫拒绝 / 5 执行失败**，`code` 字段是机器可读原因（`ENV_NO_NODE`、`ENV_WINDOW_MISMATCH`、`SESSION_LOCKED` 等）。

## 3. 复合操作（默认 dry-run，`--yes` 才真动手）

```bash
ops/open      --exe notepad --args "C:/Users/Public/win-admin/tmp/a.txt" --title "a.txt" --timeout 10 --yes
ops/find-and-click --hwnd 1234 --name "^保存$" --type Button --yes
ops/fill      --hwnd 1234 --name "文本编辑器" --text "中文 ok" --yes
ops/wait-for  --hwnd 1234 --uia-name "^是否要将更改保存" --timeout 5
ops/wait-for  --title "Chrome" --timeout 10
```

- 不给 `--yes` 时返回 `dry_run:true` 与将要点击的 **point** / 将匹配的控件，先给用户看再执行。
- `find-and-click`/`fill` 一定**先 wwin focus 再点**：被遮挡时 winput 的 S7 断言会拒绝点击（`ENV_WINDOW_MISMATCH`），这是设计而非 bug。
- `fill` 的成功判据是 **readback 与输入逐字符相同**（`matches:true`）；只标 injected 不算成功。

## 4. 五步配方（通用任务骨架）

1. **看**：`bin/wshot --out /tmp/s.png` 读图确认当前桌面状态；`bin/wdiag` 确认未锁屏、分辨率与 DPI。
2. **定窗**：`bin/wwin list`，或用 `ops/wait-for --title`。
3. **定控件**：`bin/wuia --hwnd H --name "关键字" --type Button --depth 8`；拿不到就退化为「截图上找坐标 + `--expect-hwnd` 守卫」。
4. **动**：`ops/find-and-click` / `ops/fill` / `bin/winput`（优先语义定位，坐标点击是兜底）。
5. **验**：`bin/wuia --hwnd H --value` 读回、或再截一张图比对、或检查落盘文件；不验等于没做。

## 5. 踩过的坑（照抄规避）

| 坑 | 规避 |
| --- | --- |
| 改 `win/*.ps1` 后行为不变 | 必须 `bash scripts/bootstrap.sh --force`（负载是复制到 Windows 侧才生效） |
| 中文输出乱码 | stdin/`-f` 模式的 PS 脚本第一行必须 `[Console]::OutputEncoding=[Text.Encoding]::UTF8` |
| hwnd 传进 jq 报 invalid JSON | 先 `H=$((H))` 转十进制，`jq --argjson` 不认 `0x` |
| 点击被拒 `ENV_WINDOW_MISMATCH` | 目标被遮挡：先 `bin/wwin focus --hwnd H`，再点；不要绕过断言 |
| 记事本「开了新文件」但 hwnd 没变 | Win11 记事本单进程多标签，标题会变；按标题匹配而不是按 pid |
| 等模态对话框等不到窗口 | 保存提示是**子窗口**，用 `ops/wait-for --uia-name`；`wwin list` 看不到它 |
| alt+F4 关不掉，弹保存框 | 用 `bin/wwin close --hwnd H`（WM_CLOSE 交给应用自己决定存不存） |
| 坐标差 1.5 倍 | 一律物理像素；脚本首行 `SetProcessDpiAwarenessContext([IntPtr]-4)`，wdiag 的 screen 应与真实分辨率一致 |

## 6. 什么时候应该拒绝

- 桌面锁定/断开/黑屏：`wdiag` 报 `locked:true` 或 `gui_available:false` → 停，告诉用户。
- 用户不在、无人确认的批量点击：不做；用户只授权了 scope 之外的动作：不做。
- 需要 UAC 提权：只提示用户手动点，绝不自动点。
- 目标控件需要「理解业务」才能判断对错（如转账、删除、提交订单）：先 dry-run 把 point 与控件名给用户确认。
