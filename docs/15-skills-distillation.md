# 技能沉淀：这次实战把经验落到了哪里

> 依据用户 m01860 第三阶段要求：把新控制范式的经验提炼成技能——能追加的追加、该修的修、
> 该合并的合并、该提优先级的提、能打包的打包、够格升级成插件的升级。

## 1. 盘点：先看已有的，避免造重复

| 已有技能 | 判定 | 动作 |
|---|---|---|
| `win-admin`（本仓库 SKILL.md 安装） | 主技能，缺两块：长任务、网页采集 | **追加** §7 §8 §9（99 → 136 行） |
| `windows-gui-e2e-testing` | 前作，测的是"无框架 GUI 测试"，与本项目职责不重叠 | **不动**（正文已互链） |
| `wsl-windows-token-bridge` | 只管跨侧调用（winps/wslrun） | **不动** |
| `cross-session-handoff` | 已讲跨会话续接，但**没有**可恢复执行单元 | **追加** §十二 mission 模式 |
| `gui-web-data-harvest` | 不存在；本次遇到的是"没有 API 的 JS 渲染页面"这一类 | **新建** |
| `memory-forest` / `environment-info` | 与本主题无关 | 不动 |

## 2. 追加了什么（都有实测出处）

### win-admin §7 长任务：用 mission
本次任务长到必须中断可续 —— 于是把 `bin/wmission` 的用法、三步状态机、`done` 必须带证据、
连败 3 次 `ESCALATE`、以及"mission 不是新的授权通道"写进主技能。

### win-admin §8 网页数据采集（四条死路的结论）
`Ctrl+U` 只有空壳、F12 控制台吞 SendInput、CDP 端口不开、`javascript:` 被 Edge 变成搜索 ——
四条路全部实测走死；有效路径是"URL 导航 + 20–30 轮剪贴板累积 + 截图第二来源"。
同时写进两条硬规则：剪贴板 CRLF 必须先 `tr -d '\r'`；`--expect-hwnd` 只做断言，不搬焦点。

### win-admin §9 已知局限
UIA 对 Chromium 几乎无用（53 个节点、无 TabItem）、文本层状态字样被模板污染、
角标数字与条目数可能根本不同源。

### cross-session-handoff §十二 mission 模式
把"做到第几步只活在对话里"这个问题解决掉：`plan.json` + `log.jsonl` + `evidence/`，
交接时只说 mission id，接手方 `wmission resume` 即知下一步。

## 3. 新建：gui-web-data-harvest

职责边界很清楚：**从 GUI 抓网页数据**（不是操作桌面，也不是接口对接）。八节：
值不值得走 GUI → 双来源 → 剪贴板六条硬规则 → 截图规约 → 解构模板 → 交叉校验与差异登记 →
六条反面教材 → 交付清单。与 `win-admin` 是"方法论 / 执行器"的分工。

## 4. 合并与优先级

- **没有可合并的重复**：四条候选里，两个是执行层（win-admin、wsl-windows-token-bridge），
  两个是方法层（gui-web-data-harvest、cross-session-handoff），职责不重叠，合并会稀释触发精度。
- **分组归位**：两个技能都落在 `~/.dsh/skill-packs.json` 的 `win-wsl`（WSL2 / Windows）组，
  用 `match.names` 精确匹配（`win-admin` 不匹配任何 prefix，不加就会落到默认组）；
  另补 `gui / 截图 / 剪贴板 / 采集 / 购物车 / 浏览器` 六个搜索别名。
  该组在 packs 数组第 3 位，先匹配先赢，符合"桌面操作类请求优先级"。

## 5. 打包与插件化：判定**不升级**

| 判据 | 结论 |
|---|---|
| 能否打包 | 能：`scripts/install-skill.sh` 一条命令装到 `~/.dsh/skills/win-admin`，已实测 |
| 是否需要插件 | **不需要**。插件解决的是"给 Web GUI 加界面/工具注册"；本能力是 CLI 工具链 + 提示词手册，DSH 侧通过 bash 调用即可 |
| 升级成插件的代价 | 要维护 host/client 两半、esbuild 构建、HMR 矩阵；还得把"退出码 + 单 JSON"契约藏进插件层，降低可审计性 |
| 结论 | **保持 skill + 可执行仓库**，插件形态留到"需要 GUI 里点按钮触发桌面操作"时再评估 |

## 6. 落盘位置

```
/root/win-admin/SKILL.md                              ← 主技能（136 行，随仓库版本化）
/root/win-admin/scripts/install-skill.sh              ← 安装/卸载
~/.dsh/skills/win-admin/SKILL.md                      ← 安装副本
~/.dsh/skills/gui-web-data-harvest/SKILL.md           ← 新技能
~/.dsh/skills/cross-session-handoff/SKILL.md          ← 追加 §十二
~/.dsh/skill-packs.json                               ← 分组与关键词
```

`~/.dsh` 本身是 git 仓库，技能改动已单独提交（避免与其它未提交改动混在一起）。
