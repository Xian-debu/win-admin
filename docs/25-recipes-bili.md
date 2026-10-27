# 25 · B 站投稿配方（v1.4 实战总结）

- 日期：2026-10-27
- 来源：`docs/23-usage-feedback-4.md`（session-dd79939d 一天内 7 集投稿的取证）、`/root/gen24-admin/docs/53-loongarch-series-plan.md` §9.4、`docs/45-bili-submission.md`、`docs/49-publish-copy.md`
- 定位：**配方 = 顺序 + 判据 + 已知坑**。这里不写站点专用选择器，也不写死坐标；机制在 `ops/*`，坐标每次现取（滚动会让旧坐标失效）。
- 与文档的关系：判据编号见 `docs/24-v1.4-plan.md` 的 F19–F22 / S20；命令细节见 `SKILL.md` 与各命令 `--help`。

## 0 · 通用前提

```bash
cd /root/win-admin
bash guard/grant.sh status            # 需要 shot,uia,input,file:read 四项
H=$(bin/wwin list | jq -r '[.windows[] | select(.title|test("创作中心|投稿"))][0].hwnd')
bin/wwin focus --hwnd "$H" --yes      # 前台是后续所有注入的前提（K67）
```

- 每个动作前**重新查一次**元素（`wuia --find-*` / `ops/reveal` 返回的 rect 都是当次快照）。
- 每个动作后**读回证据**：标题变、chip 数变、`toggleState` 变、正文前缀匹配——`ok:true` 只代表「注入了」，不代表「生效了」。
- 默认 dry-run：`ops/reveal`、`ops/select-option`、`ops/chip-add`、`ops/rich-write`、`ops/open` 都要 `--yes` 才真注入。
- 零副作用纪律：无法复原的动作不做（切换用户的标签页、提交、上传大文件都算）。真站点冒烟见 `tests/check-m27.sh`。

## 1 · 上传视频：两条路径

两条路径都验证过，选择依据是「上传控件会不会弹 Windows 原生对话框」：

### 1.1 路径 A：页内 Ctrl+V 粘贴文件（首选）

创作中心投稿页的上传区接受**文件粘贴**，不需要点原生对话框：


```bash
# 1) 把 Windows 原生路径放进剪贴板（WSL 路径会自动转成 C:\... 形状）
bin/wclip set --native-path 'E:\aigen_out\loongarch\ep1.mp4'

# 2) 让页面拿到焦点：点一下上传区（点之前先证明落点是对的）
bin/winput click --click-text '上传视频|点击上传' --expect-hwnd "$H" --yes

# 3) 粘贴
bin/winput key ctrl+v --expect-hwnd "$H" --yes
```

判据：上传开始后页面上会出现进度/文件名文本；用等待原语证明「真内容到位」而不是 `sleep`：

```bash
ops/wait-ready --hwnd "$H" --require '上传完成|转码中|视频上传中|ep1\.mp4' --timeout 120000
```

`ops/wait-ready` 的就绪口径是「元素存在 **且** 已布局（`rect.w/h > 2` 且 `offscreen != true`）」，超时给 `ENV_TIMEOUT` 并用 `lastCount` 区分「从未出现（0）」与「出现了但没布局（>0）」。

### 1.2 路径 B：原生打开框

有些入口点下去会弹 Windows 的「打开」对话框（class `#32770`）。此时窗口族变了，注入要 `--allow-related` 或直接切到对话框 hwnd：

```bash
# 1) 点「上传视频」后等对话框出现（它是主窗的 owned 窗，title 通常为空）
bin/wwin list --owned-by "$H" --include-empty

# 2) 把路径放进剪贴板，在对话框里粘贴（原生框只认 C:\... 反斜杠路径，见 docs/19 F2）
bin/wclip set --native-path 'E:/aigen_out/loongarch/ep1.mp4'   # 斜杠会被归一
D=$(bin/wwin list --owned-by "$H" --include-empty | jq -r '.windows[0].hwnd')
bin/winput key ctrl+v --expect-hwnd "$D" --yes
bin/winput key enter   --expect-hwnd "$D" --yes
```

坑（docs/23 §4）：原生框里粘贴路径后必须回车确认；只粘贴不回车等于没选文件。对话框关闭后再回到主窗做后续步骤。

## 2 · 分区：两级下拉

分区是一级 + 二级的级联下拉，选项列表**高于视口**——这正是 v1.3 卡死人的地方（16 次盲滚、最后人工兜底）。v1.4 用一条命令：

```bash
# 一级：展开后选「科技数码」（ops/select-option 内部会点 trigger → 找项 → 需要时 reveal → 点 → 校验）
ops/select-option --hwnd "$H" --trigger '^分区$|选择分区' --option '^科技数码$' \
  --expect-value 'region:科技数码' --yes

# 二级：展开一级后列表变长，靠 reveal 滚到目标项
ops/select-option --hwnd "$H" --trigger '^科技数码$' --option '^计算机技术$' \
  --expect-value 'region:计算机技术' --yes
```

- `--expect-value` 必给：它读的是**见证元素**（默认窗口标题，可用 `--value-aid` 指定元素 name），值没变就是 `ENV_NO_EFFECT`，不是「大概成了」。
- 弹层是独立顶层窗（`GW_OWNER` 指向主窗、标题为空）时走 `native` 路径，页内展开则走 `panel`，`mode:"auto"` 按 native → panel 顺序发现；成功 JSON 里的 `mode` 就是实证。
- 选项在容器外时内部会调 `ops/reveal`，`steps` 记滚动步数；`ENV_SCROLL_NOT_MOVED` 表示「指针没在容器里或需要先 hover」，此时不要再盲滚，先查 `wuia --point` 的 `under`。

## 3 · 标签：吞字与并字

手工输入会被吞（`科LoongArch技史` 这种并字），必须「输入 → Enter → 复核 chip 数**和**内容」：

```bash
ops/chip-add --hwnd "$H" --input '^标签输入框$' --list '^标签列表$' \
  --value 'LoongArch' --timeout 3000 --yes
# 成功：chipsBefore=7 chipsAfter=8 added=LoongArch inputCleared=true
```

- 判据是「chip 数 +1 **且** 存在 name 完全等于 value 的 chip **且** 输入框已清空」；三者缺一就 `ENV_CHIP_MISMATCH`（带 `chips/glued/attempts`），不会静默成功。
- Enter 被吞会自动重试一次：输入框还留着 value → 只补按 Enter（`enter-again`）；已被清空 → `ctrl+a` 重打（`retype`）。
- 平台默认标签（`传说之下/RPG/音乐`）要先删：删一个用 `winput click --click-text <标签名> --expect-change title` 之类的方式验证删掉了，批量删前先数一遍。

## 4 · 简介：Quill 编辑器

简介是 Quill contenteditable，**不暴露 Value**，只能整段粘贴；计数器随滚动隐藏：

```bash
# 1) 定位编辑器（用 a11y 名或 class 锚定，不要用裸 TextBox —— 会命中 RichTextBox，K71）
bin/wuia --hwnd "$H" --find-class '^(Edit|Document)$' --limit 5 --on-screen

# 2) 点进编辑器 + 全选 + 粘贴文件内容 + 回读前缀校验，一条命令
ops/rich-write --hwnd "$H" --point 1280,696 --text-file /tmp/jianjie.txt \
  --verify-aid '^简介编辑器$' --timeout 2000 --yes
# 成功：matched=true expectedChars=544 gotChars=546 verdict=prefix
```

- 回读用**前缀比较**：编辑器会追加换行/占位符，exact 比较必然假红；`--verify-aid/--verify-name` 指定目标时**不会**退回整窗正文（否则窗口里本来的字会骗过校验）。
- 2000 字上限按 `expectedChars` 自己算，别指望页面计数器（它会随滚动隐藏）。

## 5 · 封面

封面弹层有三件事要防：点「添加封面」可能触发 AI 生成、弹层里要等「完成」才落盘、坐标随滚动漂移。

```bash
# 1) 点「添加封面」并证明弹层起来了（弹层是 owned 窗或页内 modal）
bin/winput click --click-text '^添加封面$' --expect-hwnd "$H" --yes
bin/wwin list --owned-by "$H" --include-empty        # 原生弹层
bin/wuia --hwnd "$H" --find-name '^完成$|^上传封面$' --on-screen   # 页内 modal

# 2) 上传封面图：优先页内 ctrl+v 路径（同 §1.1），或在弹层里走原生框（同 §1.2）
bin/wclip set --native-path 'E:\aigen_out\loongarch\cover.png'
bin/winput key ctrl+v --expect-hwnd "$H" --yes

# 3) 「完成」必须等它就绪再点（弹层里元素位置会变）
bin/winput click --reveal --reveal-name '^完成$' --expect-hwnd "$H" --yes --expect-change title
```

- 封面 1920×1080 是安全尺寸（4:3 与 16:9 预览都正常）；比例不符时页面会要求裁剪。
- 坐标漂移的对策不是重算偏移，而是**每次动作前 reveal 再点**（`winput click --reveal` 一条命令完成「滚到位 + 证明命中 + 注入」）。

## 6 · 水印：默认开启

「添加水印」默认是**开**的，每次投稿都要在「更多设置」里关掉；展开后整个面板下移，旧坐标全部作废。

```bash
# 1) 展开「更多设置」（展开本身也要证明发生：面板里的元素从无到有）
bin/winput click --click-text '^更多设置$' --expect-hwnd "$H" --yes
ops/wait-ready --hwnd "$H" --require '^添加水印$|^可见范围$' --timeout 5000

# 2) 读当前状态（只读，不注入）
bin/wuia --hwnd "$H" --find-name '^添加水印$' --index 0 --on-screen

# 3) 只有开着才切，切完读回状态确认（幂等，不靠「点一次」赌）
bin/wuia --hwnd "$H" --toggle --find-name '^添加水印$' --index 0 --yes
bin/wuia --hwnd "$H" --find-name '^添加水印$' --index 0 --on-screen   # toggleState 应为 off
```

判据：`toggleState` 从 `on` 变 `off`（或本来就 `off` 则不动）；`wuia --toggle` 之后**必须**读回一次，不看状态就算成功等于盲操作。

## 7 · 可见范围与创作声明

- 「可见范围」是单选组，误点成「仅自己可见」是最贵的手误（要重新过审）：用 `ops/select-option` 或 `wuia --select`，并用 `--expect-value` 读回标题，**不要**用坐标点。
- 「创作声明」是原生/页内弹层，选「含AI生成内容」后要确认弹层关闭（`closed:true`）。
- 提交按钮只点一次，且**不要**放进自动流程做「零副作用冒烟」——提交不可撤销。

## 8 · 提交前复核清单

| # | 复核项 | 命令 |
| --- | --- | --- |
| 1 | 视频已上传完 | `ops/wait-ready --require '上传完成\|转码'` |
| 2 | 标题/简介非空且长度合规 | `ops/read-text` 或 `wuia --get-text` |
| 3 | 分区一级+二级都已选 | `ops/select-option --expect-value` 两次 |
| 4 | 标签数正确、无并字 | `ops/chip-add` 的 `chipsAfter` / 逐个 `--find-name` |
| 5 | 封面已落盘（不是 AI 生成中） | 弹层已关 + 封面元素出现 |
| 6 | 水印 = off | `toggleState` 读回 |
| 7 | 可见范围 = 公开 | 标题/单选框状态读回 |

## 9 · 失败错误码 → 处置

| 错误码 | 含义 | 处置 |
| --- | --- | --- |
| `ENV_NO_CONTAINER` | 目标没有可滚祖先（或不可滚） | 检查是不是被 `ClipToBounds` 裁掉的自绘控件；改用 `--point` 直接定位 |
| `ENV_SCROLL_NOT_MOVED` | 滚了但容器 `ScrollPercent` 没变 | 指针没在容器里 / 需要先 hover / 滚错容器；先 `wuia --point` 看 `under` |
| `ENV_NOT_REVEALED` | 步数用尽仍未滚到可见 | 目标不在这个容器里，或列表是虚拟列表（要边滚边重查） |
| `ENV_HIT_MISMATCH` | 证明不了落点属于目标 | 目标被遮挡或坐标过期；重新 reveal |
| `ENV_NO_TRIGGER` / `ENV_NO_OPTION` | 触发器/选项没找到 | 面板没展开、或文案变了；`tried` 会列出试过的路径 |
| `ENV_NO_EFFECT` | 动作生效了但见证值没变 | 选错项 / 见证元素选错（换 `--value-aid`） |
| `ENV_SCROLL_NOT_MOVED` / `ENV_CHIP_MISMATCH` / `ENV_TEXT_NOT_ENTERED` | 录入没落地 | 看 `attempts/glued/gotChars`，已注入多少次、卡在哪 |
| `ENV_TIMEOUT` | 等不到就绪 | `lastCount` 0 = 从未出现（入口点错/壳路由未渲染），>0 = 出现没布局 |

## 10 · 已知限制

- **壳路由**：稿件管理入口（`upload-manager/ep`）是 SPA 壳，直链会白屏，必须从创作中心点进去，并等真内容（`ops/wait-ready`）。
- **表单无 API**：投稿表单没有可用的 HTTP 接口，全程 UIA + 坐标 + 剪贴板，所以「每次动作前重新定位」是硬约束。
- **canvas / 自绘控件**：封面裁剪器这类 canvas 内容不进 a11y 树，`hit` 拿不到，只能截图目检。
- **虚拟列表**：分区二级、标签候选这类长列表可能是虚拟列表，`wuia` 一次只能看到当前渲染的子集——必须边滚边重查，不能一次性枚举。
- **只读口径**：真实站点冒烟不切用户的标签页、不提交表单（`tests/check-m27.sh` 的 S20-1..4 就是这个边界）。
