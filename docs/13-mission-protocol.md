# 13 · Mission 协议：长任务的可恢复执行单元

> 动机：真实任务（例如"去淘宝购物车抓数据做成采购表"）比单条原语长得多 —— 跨多次
> 桥调用、可能卡在登录/风控/加载、中途可能需要换方案。只活在会话上下文里的任务
> 清单，一旦上下文被压缩或会话断开就"失忆"；而把一个 20 分钟的流程塞进一条命令，
> 失败时无法定位、无法复现、无法半路接手。
>
> 协议目标：**任何一个 mission 都能在"只有磁盘"的情况下恢复执行**，且每一步都有
> 可复查的证据。

## 1. 三层结构

| 层 | 载体 | 作用 |
|---|---|---|
| 计划 | `missions/<id>/plan.json` | 步骤清单 + 状态 + 每步的验收命令（可选） |
| 事件 | `missions/<id>/log.jsonl` | append-only：谁在何时开始了哪步、证据是什么、为什么改道 |
| 证据 | `missions/<id>/evidence/` | 截图、JSON 输出、xlsx、读回校验结果，文件名带步骤号 |

`plan.json` 是**唯一真相**；`log.jsonl` 只追加不回写；`evidence/` 是物证。

## 2. CLI 契约（`bin/wmission`）

| 命令 | 语义 | 退出码 |
|---|---|---|
| `init <id> --title T` | 建 mission（已存在则拒绝，避免覆盖证据） | 0 / 2 / 5 |
| `add <id> --title T [--verify CMD] [--note N]` | 追加一步，编号自增 | 0 / 2 |
| `start <id> <n>` | 标记第 n 步为 running（写 log） | 0 / 2 / 3 |
| `done <id> <n> --evidence TEXT [--file F]` | 标记 done；**没有 evidence 拒绝** | 0 / 2 / 3 |
| `fail <id> <n> --reason TEXT` | 标记 failed（保留现场，可 retry） | 0 / 2 / 3 |
| `note <id> --text TEXT` | 往 log 写一条自由备注（改道原因） | 0 |
| `status <id> [--json]` | 人读/机读进度 | 0 / 2 |
| `resume <id>` | 打印"下一步该做什么"（含 running 的超时提示） | 0 / 2 |
| `list` | 所有 mission 的一行摘要 | 0 |

规则：

1. **done 必须带证据**：`--evidence` 是给人看的一句话结论，`--file` 是物证路径（会被拷进 `evidence/`）。
2. **状态机只允许** pending → running → done / failed；failed 可以再 start（重试计数写进 log）。
3. **不改历史**：done/failed 之后不允许回退到 pending；要改就新增一步。
4. **幂等**：`start` 已在 running 的步骤只追加一条 log，不报错（便于断点重入）。
5. `status --json` 的输出是稳定契约，给其它脚本/技能消费。

## 3. 与 win-admin 其它层的关系

- **guard 仍然在底层生效**：mission 不是新的授权通道，注入照样要令牌（S1 不变）。
- **audit 仍然一动作一行**：mission 的 log 是"任务语义层"，audit 是"动作层"，两者不互相替代。
- **每次注入前先 dry-run**：mission 的步骤应优先用 ops 的 dry-run 产出计划，再 `--yes`。
- **失败升级路径**：同一 step 连续 3 次 failed → `resume` 会显式提示"停手，报告用户"（对齐 AGENTS.md 五次失败即停，这里更严）。

## 4. 为什么不用一个 shell 脚本跑到底

1. 脚本中途失败就全灭，没有"第几步、证据是什么、为什么改道"。
2. 真实任务需要人（用户）在中间确认，脚本没有停点。
3. 脚本无法在上下文被压缩后被人（或另一个会话）接手。
4. 验收要求"未运行的都是假设"：mission 强制每步落一条证据，而不是最后一次性声称成功。

## 5. 本次实战（mission `taobao-cart-2026-10-21`）

步骤在 `missions/taobao-cart-2026-10-21/plan.json`，最终产物：
`missions/taobao-cart-2026-10-21/evidence/*.xlsx`，报告见该目录 `REPORT.md`。
