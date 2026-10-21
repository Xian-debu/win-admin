# 08 · 工程规范

> 目的：让"三个月后的我"和"此刻的我"共享同一套肌肉记忆。
> 与本文件冲突的临时决定，一律先改文件再动手。

## 1. 目录归属

| 目录 | 归谁 | 内容规则 |
|---|---|---|
| `docs/` | 文档 | 编号 `NN-topic.md`，一个主题一份；`07` 冻结，其余可迭代 |
| `bin/` | 原语交付物 | 一个原语一个文件，可独立执行；**M1 通过前不许有输入类原语** |
| `ops/` | 组合操作 | 调用 `bin/` 的脚本，不直接写 PowerShell 细节 |
| `guard/` | 安全边界 | 令牌签发、审计、pause 检查、体检 |
| `tests/` | 验收 | `check-*.sh`（工程自检）、`*-e2e.sh`（端到端）、`reports/`（验收报告） |
| `inventory/scripts/` | 探测脚本 | 只读，可反复跑，输出落 `inventory/raw/` |
| `inventory/raw/` | 探测原始输出 | 带日期文件名，**只增不改** |

## 2. 提交规范

**粒度**：一个文档 / 一个原语 / 一个修复 = 一个提交。禁止"顺手一起改了"。

**subject**：`<type>: <中文，说清做了什么>`

| type | 用于 |
|---|---|
| `init:` | 骨架、初始结构 |
| `docs:` | 文档 |
| `probe:` | 探测脚本或探测结论 |
| `bin:` | 原语实现 |
| `ops:` | 复合操作层 |
| `guard:` | 安全层 |
| `test:` | 测试与验收报告 |
| `fix:` | 修 bug |
| `chore:` | 杂务（gitignore、目录调整） |
| `release:` | 版本冻结、构建产物与标签 |
| `auth:` | 自授权清单（`authorization/self-grants.md`） |
| `missions:` | 任务实录（`missions/<id>/`：plan / 解析脚本 / 产物 / REPORT） |

**body 必须写"为什么 + 实测数字"**。示例（真实提交）：

```
docs: 03 插件审计结论 —— 不采纳的三条理由与可借鉴项

- 静态逐行审计（一行未执行），SHA256 固定，危险模式零命中
- 核心发现：admin 档 == 内置 danger-full-access+never（零增益）
```

## 3. 证据规则

文档里每一条"结论"必须能指向三种东西之一：

1. **命令 + 输出片段**（最短、最优先）；
2. **文件:行号**（`lib/index.js:151-155`）；
3. **字节数 / 尺寸 / 耗时** 这类硬数字。

拿不到证据的，写成 `假设` 或 `待验`，并注明"何时能验"。
**禁止**："一般来说""应该没问题""基本可用"。这三句出现过一次，这份文档就不可信了。

## 4. 坐标与编码（两条铁律）

### 4.1 坐标

- 对外**只用物理像素**。
- 任何脚本的第一步（若涉及坐标）：声明 DPI 感知。

```powershell
Add-Type @"
using System.Runtime.InteropServices;
public class D { [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v); }
"@
[D]::SetProcessDpiAwarenessContext([IntPtr]-4)   # -4 = PER_MONITOR_AWARE_V2
```

- 调试时用 `wdiag` 回显 `{screen_w, screen_h, scale}`，与 `docs/02` §2 对照。

### 4.2 编码

- PS 脚本首行：`[Console]::OutputEncoding = [Text.Encoding]::UTF8`。
- 含中文或多层引号的脚本 → 落 `/mnt/c/Users/Public/win-admin/ps1/` 后 `winps -f`。
- bash 里只允许单行 ASCII `powershell.exe -Command`。
- 输出一律 `ConvertTo-Json -Depth 5 -Compress`。

## 5. 原语开发模板

新增一个原语（以 `bin/wfoo` 为例），五个步骤缺一不可：

1. **先在 `docs/04` 能力矩阵登记一行**（状态 🧪，写明里程碑）——没登记就先写代码，视为越界。
2. 写 `bin/wfoo`，实现四件事：参数解析、`--help`、JSON 输出、退出码。
3. 建 `tests/check-wfoo.sh`：>=3 条断言（正常 + 参数错 + 一个反例）。
4. 更新 `docs/05` §4 原语表（输入/输出字段）。
5. `git add` 分开提交：`bin: 添加 wfoo 原语` + `test: wfoo 三断言`。

### 原语骨架

Shell 脚本统一头：

```bash
#!/usr/bin/env bash
# bin/wfoo — <一句话职责>
# 输出：{"ok":bool,"data":{...}} 或 {"ok":false,"code":"...","msg":"..."}
set -euo pipefail
```

失败走统一出口（`die <code> <中文msg>`），内部调用 `guard/check.sh` 校验授权，
然后 `winps -j` 取 JSON，最后用 `jq -c` 归一化输出。**禁止**在 bash 里手拼 JSON 字符串。

## 6. 测试规范

- 每条测试断言必须**能独立失败**（不依赖前一条的副作用）。
- 反例测试优先写：`test-*.sh` 里安全反例排在最前。
- 测试输出格式：`PASS <编号>` / `FAIL <编号> <实测> != <期望>`，最后一行 `SUMMARY pass=N fail=M`。
- 不做 mock：这是本机集成测试，mock 掉 Windows 就失去意义。

## 7. 文档写作规范

- 开头一句"本文回答什么问题"。
- 表格优先于段落（密度高、可扫读）。
- 数字必带单位；时间必带时区。
- 中英混排：专有名词保留原文（`SetCursorPos`、`UIA`），不要硬译。
- 不用 emoji 装饰，除非它承载语义（如验收状态 ✅/❌）。

## 8. 完成的定义（DoD）

一个任务**不算完成**，除非：

- [ ] 代码/文档已提交（工作区干净）
- [ ] 有可重跑的验证命令，且当场跑过
- [ ] 实测结果写进 `docs/07` 的实测列或 `tests/reports/`
- [ ] 相关的 `docs/04` 状态已更新（🧪 → ✅）
- [ ] 没有引入新的 `待验` 却不在文档里标注
