# 07 · 验收标准（冻结件）

> **本文件是冻结件。** 改任何一条判据 → 单独提交，并在提交信息里写明"原判据为何不成立"。
> 判据分三族：**E** 工程 / **C** 能力 / **S** 安全。
> 每条格式：编号 · 判据 · 验证命令 · 期望 · 实测 · 状态。
> **实测列由执行人在跑通后填入**，未填 `—` 即视为未验收。禁止填"基本可用"。

状态记号：`☐ 未验` / `✅ 通过` / `❌ 不通过` / `⏭ 不适用`

---

## E 族 · 工程判据（每个里程碑都要过）

### E1 · 仓库自洽

- **判据**：`git status` 干净；`git log --oneline` 每条提交 subject 以 `init:|docs:|probe:|bin:|guard:|test:|fix:|chore:` 开头。
- 验证：`cd /root/win-admin && git status --porcelain | wc -l` → `0`；`git log --format=%s | grep -vcE '^(init|docs|probe|bin|guard|test|fix|chore):'` → `0`
- 实测：`—`

### E2 · 文档与代码一致

- **判据**：`docs/05` 里列的每个原语，`bin/` 下都存在同名可执行文件；反之亦然。
- 验证：`tests/check-doc-bin-sync.sh`（M1 建）
- 实测：`—`

### E3 · 原语契约一致（JSON）

- **判据**：每个原语 `--help` 退出码 0；无参调用返回 JSON（`ok` 键存在）；`jq -e . >/dev/null` 成功。
- 验证：`for f in bin/*; do $f >/dev/null; echo $? ; done` + `jq`
- 实测：`—`

### E4 · 退出码语义

- **判据**：成功=0；参数错=2；环境不满足=3；guard 拒绝=4；执行失败=5。造四种情形各验一次。
- 验证：`bin/winput --bad-flag; echo $?` → 2 等
- 实测：`—`

### E5 · 无残留

- **判据**：任一原语执行后，Windows 侧无新增常驻进程；`/mnt/c/Users/Public/win-admin/` 下无本次临时文件残留（截图属正常产物）。
- 验证：执行前后 `Get-Process | Measure-Object` 计数；目录 `ls -lt | head`
- 实测：`—`

### E6 · 单次调用耗时

- **判据**：`wdiag` 端到端 < 3s；`wshot` < 4s；`winput click` < 3s（含 300ms 启动开销）。`wuia` 枚举 1 万节点内 < 8s。
- 验证：`time bin/xxx` × 5 次取中位
- 实测：`—`

### E7 · 编码正确

- **判据**：含中文的窗口标题、`wclip set "中文"` 回读、`wuia` 节点名，全部无乱码（`echo | hexdump` + 人眼比对）。
- 验证：`bin/wclip set "测试中文" && bin/wclip get` → `{"text":"测试中文"}`
- 实测：`—`

### E8 · 可重复

- **判据**：任一验收用例连续跑 10 次，结果一致（允许耗时波动，不允许结果翻转）。
- 验证：`for i in $(seq 10); do ... done | sort | uniq -c`
- 实测：`—`

---

## C 族 · 能力判据（"看得见 / 认得准 / 点得中"）

### C1 · 看得见（M1）

- **判据**：截图像素尺寸 == 物理分辨率 2560×1600（DPI 感知后），文件可打开，内容与屏幕一致（人工确认一次）。
- 验证：`bin/wshot --full` → `{"w":2560,"h":1600}`；`python -c "from PIL import Image;print(Image.open(p).size)"`
- **子项 C1b（Q1）**：若会话模型支持图像 → agent 描述图中 3 处内容，用户核对；
  若不支持 → 明确记录"视觉通道不可用"，L4 降级为存证，**C2/C4 不依赖截图判断**。
- 实测：`—`

### C2 · 认得准（M1）

- **判据**：`wuia --window "记事本"` 能找到记事本窗口，返回 hwnd/title/rect 与 `Get-Process notepad` 的 MainWindowHandle 一致；
  层内能找到 `菜单栏`/`文档` 编辑区（`ControlType=Document`）。中文名无乱码。
- 验证：`bin/wwin list` 与 `bin/wuia --pid <notepad>` 交叉核对
- 实测：`—`

### C3 · 定位精度（M1/M2 交界）

- **判据**：`wuia` 给出的控件物理像素 rect，与截图对应区域**视觉一致**（误差 ≤ 2px，做法：截图叠框后人工看一次，或用 PIL 校验边框颜色）。
- 验证：`tests/rect-vs-shot.py`
- 实测：`—`

### C4 · 点得中（M2）

- **判据**：`winput --dry-run click X,Y` 打印的目标窗口/坐标正确；实点后**目标窗口获得焦点且截图显示点击生效**（例：点记事本编辑区 → 出现光标；点按钮 → 状态改变）。
- 验证：`bin/wshot` → `bin/wuia` 取 rect → `winput --dry-run` → `winput click` → `bin/wshot` 对比
- 实测：`—`

### C5 · 打得进（M2）

- **判据**：`winput type "Hello 世界"` 到记事本，回读文本框内容完全一致（含中文、含空格）。
- 验证：点编辑区 → `winput type` → `wuia` 读 `ValuePattern` 或 `Ctrl+A Ctrl+C` + `wclip get`
- 实测：`—`

### C6 · 拖得动（M2）

- **判据**：拖拽从 (x1,y1) 到 (x2,y2)，终点窗口位置变化符合预期（误差 ≤ 3px）。
- 验证：`wwin layout` 记录前后 rect
- 实测：`—`

### C7 · 等得到（M2）

- **判据**：`wait-for` 在目标出现后 200ms 内返回；超时准确报错（不假成功）。
- 验证：启动耗时 3s 的程序，`wait-for window "X" --timeout 10s`
- 实测：`—`

### C8 · 端到端（M4）

- **判据**：用 `ops/` 完成一个真实任务（例：打开记事本 → 写入指定中文 → 另存为 `C:\Users\Public\win-admin\e2e.txt` → 文件内容与预期完全一致），全程无人工介入，耗时 < 60s。
- 验证：`tests/e2e-notepad.sh`
- 实测：`—`

---

## S 族 · 安全判据（**先验这一族**）

> 原则：安全判据必须在能力判据之前全部通过。理由见 `docs/01` §5 反例优先。

### S1 · 无授权不点（M3）

- **判据**：无 `grant.json` 或已过期或 scope 不含 `input` 时，`winput click` 必须 exit 4，且**实际未注入**（截图前后完全一致，用像素 diff 证明）。
- 验证：`rm -f ~/.dsh/win-admin/grant.json; bin/winput click 100,100; echo $?` → 4；截图 diff = 0
- 实测：`—`

### S2 · 软急停生效（M3）

- **判据**：`touch ~/.dsh/win-admin/pause.flag` 后，所有输入原语 exit 4 且不注入；删除后恢复。
- 验证：同上
- 实测：`—`

### S3 · 锁屏拒绝（M3）

- **判据**：锁屏（`Win+L`）状态下调用 `winput`/`wshot` → exit 3，报 `SESSION_LOCKED`；解锁后恢复。
- 验证：用户手动锁屏 → 调用 → 解锁
- **风险**：若检测方法不成立（Q2），此条记为 ❌ 并升级为阻塞项，不许"估摸着能行"。
- 实测：`—`

### S4 · UAC 拒绝（M3）

- **判据**：屏幕上出现 UAC 提示时，任何输入原语 exit 3 报 `UAC_SECURE_DESKTOP`，且不尝试任何按键。
- 验证：触发一个 UAC（如 `Start-Process -Verb RunAs`），同时调用；用户手动取消
- 实测：`—`

### S5 · 审计完整（M3）

- **判据**：连续执行 20 个输入动作（含 5 个故意失败的），`audit/*.jsonl` 恰好 20 行，每行有 `ts/tool/args/result`，失败行 `result` 非 `ok`。
- 验证：`jq -c . audit/*.jsonl | wc -l` → 20；`jq -r 'select(.result!="ok")' | wc -l` → 5
- 实测：`—`

### S6 · 令牌不可被原语篡改

- **判据**：任何原语都无法写出/延长 `grant.json`（只允许 agent 侧的一次性签发脚本 `guard/grant.sh` 写）；
  `grep -rl 'grant.json' bin/ | xargs grep -l 'write\|Out-File\|Set-Content'` 为空。
- 实测：`—`

### S7 · 误操作面收窄

- **判据**：`winput` 的坐标点击必须要求目标是已枚举过的窗口（`--expect-hwnd` 或前置 `wdiag` 校验），防止"点到了用户正在用的别的东西"。
- 实测：`—`

### S8 · 红线回归

- **判据**：`grep -rniE 'consent\.exe|secure desktop|winlogon|taskkill /f /im explorer' bin/ ops/ guard/` → 空（不发生红线动作的代码痕迹）。
- 实测：`—`

---

## 里程碑 × 判据对照

| 里程碑 | 必须通过的判据 | 门槛 |
|---|---|---|
| **M1 只读** | E1–E7, C1(含 C1b), C2, C3 | 全绿才进 M2；任一红即停 |
| **M2 输入** | C4–C7 + S7（先建最小守卫） | C4 连续 10 次 10 中才算过 |
| **M3 守卫** | **S1–S8 全绿**（先于 M2 的能力判据通过亦可，但不许跳过） | 任一红即停 |
| **M4 组合** | C8 + E8 + 全部 E 族回归 | 端到端 3 次连过 |
| **M5 收尾** | 全表回归 + SKILL.md 与实现一致 | 冻结 v1.0 |

## 验收记录规范

每次验收在 `tests/reports/YYYY-MM-DD-<milestone>.md` 落一份：

```markdown
# M1 验收 · 2026-10-XX
| 编号 | 期望 | 实测 | 状态 |
|---|---|---|---|
| E1 | 0 | 0 | ✅ |
...
结论：M1 通过 / 阻塞于 S3（理由）
```

**没有报告 = 未验收。** 报告本身也要提交进 git。
