# 19 · 第二轮使用反馈取证（v1.1.0 实战：B 站投稿全流程）

> 取证对象：`session-4f961713-4365-4dde-81c8-36f89f562785`（2026-10-24 08:32–10:10，一轮 turn）。
> 任务背景：给「快速选择（quickselect）」算法讲解片做 B 站投稿（vpb/remotion 出片 → win-admin 上传、填表、选分区、提交）。
> 自述反馈原文：该会话交付报告 `/root/gen24-admin/docs/40-quickselect-film-report.md` §5（8 条，本文逐条复核）。
> 取证方法：`session.v4.jsonl.zstd` 解压为 `/tmp/s-4f.jsonl`（10.7 MB / 4431 行），按 `tool/call` 的 `data.arguments.code` 与 `tool/result` 配对通读；辅以 `scripts/scan-sessions.py` 计数。
> 结论先行：**没有一条失败是被工具报错说清楚的**。8 条里有 6 条是「工具返回成功或语义错误的码，操作者只能绕路」。这正是 v1.1 想消灭、但没消灭干净的那一类。

## 1 · 调用画像（为什么要先看这个）

投稿阶段（seq ~2540–4200）的 win-admin 调用：

| 原语 | 次数 | 说明 |
|---|---|---|
| `bin/wshot` | 68 | 其中带 `--rect` 抓局部 20 次；`>/dev/null` 吞掉失败 JSON 的 4 次 |
| `bin/winput` | 63 | click 41 / type 9 / key 8 / hover 5；**几乎全部靠截图目测坐标** |
| `bin/wuia` | 21 | 多数是 `--find-aid`/`--get-text` 读页面文本，少数 `--find-name` 找按钮 |
| `bin/wwin` | 20 | 其中 3 次是失败后 `set --state max` 抢救窗口 |
| `ops/hover-menu` | 6 | **6 次全失败**（窗口族 mismatch 或弹层遮挡） |

一句话：**v1.1.0 的语义层（wuia find/act、click-element、wait-uia）在这轮实战里基本没被用上**，实际跑的还是 v1.0 的「截图 → 看图 → 猜坐标 → click」。原因不是操作者不知道这些命令，而是

1. 语义层按名字找元素，但 B 站投稿页大量控件的可访问名是空串或「按钮」之类的通用名（`--find-name` 无从下手）；
2.「看图猜坐标」这条路只要有一条命令能把「我看到的图」和「我能点的坐标」对齐，就会一直赢——而现在没有这条命令。

## 2 · 八条反馈：现象、根因、归类

### F1 `#32770` 子消息框点不动（窗口族判据过严）

现场（seq 4092 之后）：「文件名无效」弹层出现，操作者拿父窗口句柄点它，两条命令都失败：

```
bin/winput click 935 509 --expect-hwnd 64229632 --yes
  -> {"ok":false,"code":"ENV_WINDOW_MISMATCH","msg":"point (935,509) hits hwnd 0x4e0e02, expected 0x3d41100"}
bin/winput click 935 509 --expect-hwnd 5115394 --yes   # 换成父窗口
  -> {"ok":false,"code":"ENV_NOT_FOREGROUND","msg":"target 0x4e0e02 is not foreground (foreground 0x3d41100)"}
```

根因：`win/winput.ps1` 的 `Assert-Target` 把两边都用 `GetAncestor(GA_ROOT=2)` 归一化到顶层窗口再**严格相等**比较。子对话框与父对话框是祖先/后代关系（同一窗口族），归一化后仍是两个不同的根，于是永远不等；换父句柄则撞在「前台必须等于目标」的检查上。

=> 操作者唯一出路是 `winput key enter` 盲按。这正是「缺失的操作映射」。

### F2 原生「打开」对话框只认反斜杠路径

现场：`C:/Users/Public/win-admin/tmp/....srt` 粘进文件名框 → 弹「文件名无效」；`C:\Users\Public\win-admin\tmp\....srt` 才成功（seq 3573）。

根因不在 win-admin（那是 Windows 通用对话框 + WSL 侧习惯路径的差异），但**工具完全可以吃掉这个差异**：`wclip set` / `winput type` 拿到的任何 `/mnt/...` 或 `C:/...` 都可以在写入前统一成 `C:\...` 反斜杠形式。目前没有这一步，代价是操作者要记住「原生对话框用反斜杠」这条反直觉规则（技能里还真写错过一次）。

### F3 窗口自己从最大化变回窗口化（**状态副作用**，最严重）

现场：两次都在 `ops/hover-menu` 失败之后，「坐标全失效，只能 `bin/wwin set --state max` 抢救」。

根因（确定性，非推测）：

- `win/lib/wa-core.ps1:167` `Set-WaForeground` 的第一行是 `[void][Wa.Native]::ShowWindow($h, 9)`；**`SW_RESTORE(9)` 会把最大化窗口还原成窗口化**。
- `ops/lib-ops.sh:34` 的 `op_focus()` 调 `bin/wwin focus` → `Set-WaForeground`；`ops/hover-menu:60`、`ops/click-element`、`ops/fill`、`ops/wait-uia` 都必调 `op_focus`。
- `win/winput.ps1:115` 的 `-Focus` 分支同样是 `ShowWindow($target, 9)`。

所以：**任何一句 `ops/*`、任何一次 `winput ... --focus` 都会静默改变窗口状态**，而且没有任何输出提示。操作者看到的是「点了没反应 / 坐标飘了」，根因却在一次 focus 里。这是「操作映射缺失 + 副作用不可见」的叠加。

### F4 `type --text-file` 传 WSL 路径 → `ARG_EMPTY_TEXT`

现场：`--text-file /tmp/title.txt` 报空文本。

根因：`bin/winput:178` 只是 `args+=(-TextFile "$(wa_winpath "$TF")")`，`/tmp/...` 不经 `/mnt` 转换 → Windows 侧 `Test-Path` 失败。而 `ARG_NO_TEXT_FILE` 与 `ARG_EMPTY_TEXT` 两个码在实践里被混着理解（`$text.Length` 为 0 的判据在 win/winput.ps1:376 附近），操作者分不清「文件不存在」与「文件是空的」。

### F5 标签 chip 静默误删 / `type` 焦点丢失仍报成功

现场：删除平台默认标签时，每删一个输入框就左移，按旧坐标点到了相邻的 `×`（误删 C++ 标签后手工补回）；另有一次 `winput type` 返回 `ok:true`，但文本被粘到了别处（焦点已丢）。

根因：`type` 的判据是「按键序列送出去了」，不是「内容进去了」。`ops/fill` 有 readback，`winput type` 没有——同一份能力，两套标准。

### F6 坐标空间混淆（物理像素 vs 缩放预览）

现场：前两次点击全部落空，因为 `wshot` 出的是 2560×1600 物理像素图，而对话里看到的是被 DSH 缩放后的预览图；按预览上的读数去点，偏移 1.5 倍。

根因：JSON 里其实有 `screen.dpi=144, scale=150`，但**没有任何一处告诉操作者「图上的像素 = 物理像素，看图要先换算」**；`--grid` 已经能在图上烧绝对坐标（v1.1 T9），可是知道该用它的人不需要它，需要它的人不知道它。

### F7 `wshot --rect` 参数太松，失败还很安静

现场：`--rect 800,460,1950,150`（按「左上右下」理解的写法）→ `{"ok":false,"code":"ARG_OUT_OF_SCREEN","msg":"rect 800,460 1950x150 outside screen 0,0 2560x1600"}` rc=2；因为命令后面跟着 `>/dev/null`，操作者只看到「文件不存在」。空格分隔的 `--rect 800 460 1900 140` 会掉进 `*) unknown arg`。

根因：`bin/wshot:39-42` 用 `IFS=, read -r rx ry rw rh` 直接当 `X,Y,W,H`，没有「你是想问左上右下吗」的别名，也没有 `--clip` 兜底。

### F8 二级分区「计算机技术」仍未选到（真实站点限制）

现场：`ops/hover-menu --at 954,1576 --pick '计算机技术'` → `ENV_WINDOW_MISMATCH`（命中 hwnd 的 pid 与目标不同：页面上有第三方弹层/captcha 覆盖）；最大化后重试同样失败；最终只选到一级「科技数码」。

这一条**不是**新缺口：v1.1 已把它记成 `ENV_MENU_NOT_SHOWN` 类限制，并且红线是「不硬点」。但它揭示了一个可修的次生问题：**mismatch 报错里没有任何「挡在前面的是谁」的信息**，操作者无法判断是「我算错坐标」还是「有东西盖住」——若报错带上命中窗口的 title/class/rect，就能立刻分辨。

## 3 · 归并成 6 个工具缺口

| # | 缺口 | 覆盖 F | 一句话修法 | 任务 |
|---|---|---|---|---|
| G1 | focus 有状态副作用且不可见 | F3 | 只在最小化时 `SW_RESTORE`；`ops/*` 断言前后状态不变 | T12 |
| G2 | 窗口族判据过严（父子对话框） | F1, F8 | `--allow-related`：祖先/后代视为同一族；mismatch 报错带命中窗口信息 | T13 |
| G3 | 「送出按键」≠「内容进去了」 | F5, F4, F2 | `type --verify` 回读；`--text-file` 在 bash 侧读入（WSL 路径统一）；路径与空文本分开报 | T14 |
| G4 | 坐标与图像的对应关系不可见 | F6, F7 | `wshot --box/--clip`、JSON 增 `scale`/`image`、错误信息给出正确用法 | T15 |
| G5 | 看图估坐标仍是主路径 | 全篇 | `ops/map`：截图 + UIA 框 + 编号，把「看哪」变成「点第几个」 | T16 |
| G6 | 点击后没有「结果断言」 | F5 | `click-element --expect-gone/--expect-alive` | T17 |

## 4 · 与 v1.1 计划的关系（诚实结算）

v1.1 的 T1–T11 解决了「有没有这个命令」；这轮反馈说明真正的门槛是**「命令可不可信、可不可判定」**：

- T1 `wwin state/set` 有了，但没人想到 `focus` 会偷偷改状态（T12 是它的补丁）；
- T5/T6 `wuia find/act` 有了，但页面控件名不可用 → 需要 T16 的「地图 + 编号」绕开命名；
- T7 `click-element` 有了，但缺「点完断言结果」→ T17；
- T9 `wshot --grid` 有了，但缺「参数不会误读 + 失败不安静」→ T15。

## 5 · 复现与判据落点

每条修复的验收判据写进 `docs/20-v1.2-plan.md` §4（冻结），对应测试 `tests/check-m13.sh`（T12/T13）、`check-m14.sh`（T14）、`check-m12.sh` 扩展（T15）、`check-m15.sh`（T16）、`check-m11.sh` 扩展（T17）。

原始会话日志不提交进仓库（含用户操作内容）；本文只保留命令、错误码与代码行号，供复核。