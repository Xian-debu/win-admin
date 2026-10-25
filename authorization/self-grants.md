# 自授权清单（append-only）

> 协议见 `docs/12-authorization.md`。每行 = 一次"我替用户做的决定"。
> 只看这一张表就能判断夜间作业的风险面；细节在对应提交与报告里。

## 2026-10-24 夜间批次（v1.1.0）一览

> 用户 m00002 睡前授权：「有自己想法的，我全部授权给你了，你只需在 git 提交时单独增量提交一个自授权清单即可，明早我一并查看」。
> 本批 SG-0016 … SG-0034 共 19 条，按「风险从高到低」读：

**改变能力面（会动到用户桌面）**
- SG-0018 `wwin set` 归入 input 类（需 grant），不新设 scope。
- SG-0019 `ops/click-element` 对「删除/购买/支付/提交/下单/格式化」类名字默认拒绝，`--allow-danger` 才动手。
- SG-0020 `winput hover` 返回落点 UIA 元素（让「悬停生效」可判定）。
- SG-0030 `click-element`/`wait-uia` 默认深度失手自动加深（网页内容在 depth 12–13），输出标 `deepened`。

**改测试判据（影响「什么算通过」）**
- SG-0025 C10 判据 → 「元素矩形包含悬停点（±2 px）」；SG-0026 `check-release` UTF-8 窗口 20→40 行；SG-0027 `build-release` 改 `ls-files -z` + `tar --null`（修中文路径漏打包）；SG-0033 新增 m11 N27；SG-0034 套件串行跑。
- SG-0021→SG-0024 夹具由 WinForms 改 WPF（TextBlock 无 TextPattern，WinForms 验不了 `set-value` 回读）。

**范围与取舍（决定「不做」什么）**
- SG-0016 夜间自主推进 T1–T11；SG-0017 新增 docs/16、docs/17、`scripts/scan-sessions.py`。
- SG-0022 网页实验只起 cdp-hub 的**受管一次性** Edge，不碰用户真实浏览器。
- SG-0031 网页通道定为 **UIA-first**（TextPattern 读正文、Invoke/SetValue 点元素）；CDP 仅用于自起实例——用户真实 Edge 没开调试端口，重启它属红线。
- SG-0023 本轮不改 docs 编号冲突（`12-authorization.md` 与 `12-retro.md`）。

**补充**
- SG-0028 T3+T4 合并提交（同一份 `bin/winput`，拆开会留下跑不起来的中间态）。
- SG-0029 冻结并打 `v1.1.0` 标签 + 推送 GitHub。
- SG-0032 夹具 `web11.html` 入库（1.7 KB 静态页，无凭据）。

| ID | 时间 | 类别 | 决定 | 依据 | 影响面 | 回滚 | 提交 |
|---|---|---|---|---|---|---|---|
| SG-0001 | 2026-10-21T01:05+08:00 | SCOPE | 夜间自主推进 M3→M4→M5，遇到岔路自己定，不阻塞等用户 | 用户 m00805 全权授权 | 项目进度与设计选择 | 逐条回滚；用户可对任一 SG 喊停 | 本提交 |
| SG-0002 | 2026-10-21T01:08+08:00 | TEST | 锁屏/UAC 判据改用 Windows 侧文件钩子 `tmp/force-desktop.txt`，不做真实锁屏 | 锁屏会把我关在门外（无密码），点 UAC 是红线；WSL 环境变量不传给 Windows 进程（K19） | 仅影响测试路径；钩子只能声明更严格的非 Default 桌面 | 删除钩子文件即恢复（D21） | 同一 docs 提交 |
| SG-0003 | 2026-10-21T01:08+08:00 | GUARD | 审计写失败时动作 fail closed（exit 5），而不是继续执行 | S5 的证据价值依赖「每个动作必有一行」；宁可不动也不留无记录动作 | 审计目录不可写时所有输入失效（显式报错，可诊断） | 删除 `lib/audit.sh` 的强制 exit 5 逻辑 | 同一 docs 提交 |
| SG-0004 | 2026-10-21T01:08+08:00 | GUARD | `grant.json` 增加 `sig` 字段（sha256(key+规范化字段)），旧无签名 grant 一律拒绝 | 误编辑/事故/旧版令牌会被静默接受，是真实风险 | 用户手改 grant 将失效，必须经 `guard/grant.sh` 重签 | 删除 sig 校验逻辑并重签 | 同一 docs 提交 |
| SG-0005 | 2026-10-21T09:00+08:00 | TOOL | `wwin` 增加 `focus`/`close` 两个动作（原计划没有这个原语） | 复合操作必须先激活再点（D24）；关闭要优雅（D25/K31）。两者都不产生合成输入，放窗口管理层更内聚 | 新增两个 win32 动作，不改既有语义 | `git revert` 该提交；`wwin list/info` 不受影响 | c21da22 |
| SG-0006 | 2026-10-21T09:05+08:00 | TOOL | 新增 `win/waopen.ps1`：把「启动 + 等窗口」放进一次 PowerShell 调用 | 否则 bash 侧要轮询 700ms 桥调用，open 会慢 2-3 倍 | 新增一个只读启动动作（Start-Process + 轮询），不注入输入 | 删除 waopen.ps1 与 ops/open 调用 | d3e3c17 |
| SG-0007 | 2026-10-21T09:10+08:00 | TEST | `tests/check-m4.sh` 的 N5 移到 C8-1 之后（先开一个窗口再测「找不到控件」） | 无窗口时 ops 先报 ENV_NO_WINDOW，测不到 ENV_NO_NODE；原顺序会得到一个假阴性 | 仅影响测试顺序 | 调整脚本顺序即可复原 | acc56ab |
| SG-0008 | 2026-10-21T09:12+08:00 | SCOPE | M4 的 4.4「真实任务演练」不自己编需求，挂起等用户 | AGENTS.md 禁「假装完成」；没有真实需求时自造演练没有验收价值 | 文档里明确挂起，不虚报里程碑 | 用户给任务后补做 | docs/09 提交 |
| SG-0009 | 2026-10-21T09:14+08:00 | DROP | E8「10 次连跑」本轮只跑 3 次就过 M4 门槛 | docs/07 的 M4 门槛是「3 次连过」，10 次属 M5 全表回归 | 少 7 轮证据，但门槛按冻结文档执行 | M5 补足 10 轮并回填 docs/07 | 待 M5 |
| SG-0010 | 2026-10-21T01:2x+08:00 | TOOL | 把 check-m4 内联的 `c8_once` 提到 `tests/helpers/e2e.sh`（m4/m5 共用，签名为 `c8_once TAG TEXT [PREFIX]`） | 十轮回归若复制一遍，两处逻辑必然漂移；共用一份才好比对 m4 与 m5 的耗时 | 纯重构，m4 重跑仍 13/0 | `git revert` 恢复内联版 | 见 `git log --grep 端到端单轮` |
| SG-0011 | 2026-10-21T01:2x+08:00 | TEST | `tests/check-m5.sh` 增加 `--only-a` / `--only-b`，可只跑回归或只跑十轮 | 排查 K32 时需要在不动桌面/不重跑 6 分钟回归的前提下单独复现 B 段 | 仅测试入口参数，不改判定 | 去掉参数解析即可 | 同 check-m5 提交 |
| SG-0012 | 2026-10-21T01:2x+08:00 | SCOPE | E8 十轮用独立前缀 `m5-c8` 与独立文案，不复用 m4 的临时文件与 `M4 验收第 N 轮` 文本 | 复用会让 m4/m5 的落盘文件互相覆盖，且报告里无法区分是哪一轮产生的文件 | 只影响临时文件名与断言文本 | 改回 m4-c8 前缀即可 | 同 check-m5 提交 |
| SG-0013 | 2026-10-21T01:3x+08:00 | SCOPE | 发布复演用 `dist/*.tar.gz` 解包验证，代替 docs/09 M6 写的 `git clone` | 要证的是「发布物本身可用」，clone 验的是仓库；发布物解包更能暴露漏打包 | 比 clone 更强，非弱化 | 换回 clone 流程 | ac3ed45 |
| SG-0014 | 2026-10-21T01:3x+08:00 | SYS | M5 冻结时立即打 `v1.0.0` 标签，不等 M6 单独一轮 | M5 的判据就是「冻结 v1.0」，冻结却不打标签等于没冻结；M6 剩下的是 GitHub Release 说明 | 仅本地 tag，未推送任何远端 | `git tag -d v1.0.0` | ac3ed45 |
| SG-0015 | 2026-10-21T03:2x+08:00 | TEST | 认定「测试套件跑完不得留下有效令牌」是一条可执行验收项，新增 E5 断言；并修 K34/K35 两处令牌管理缺陷 | K34 实测留下 30 分钟有效令牌（等于跑测试就偷偷授权）；K35 显示阴性用例复用了 cleanup 的备份槽，天然会吃掉自带令牌 | 只动 tests/：cleanup 语义收紧、N1 独立暂存路径、多一条 FAIL 可能 | 回滚该 test: 提交即可，能力面零改动 | 945479b |
| SG-0016 | 2026-10-24T00:4x+08:00 | SCOPE | 夜间自主推进 v1.1.0（docs/17 T1–T11 + M9 研究），遇到岔路自己定，不阻塞等用户；只把决定记进本表 | 用户 m00002 全权授权（"有自己想法的，我全部授权给你了，你只需在git提交时单独增量提交一个自授权清单"） | 项目进度、原语设计与测试面 | 逐条回滚；用户可对任一 SG 喊停 | 本提交 |
| SG-0017 | 2026-10-24T00:4x+08:00 | SCOPE | 新增 `docs/16`（三会话取证）、`docs/17`（v2 计划）、`scripts/scan-sessions.py`（会话日志取证脚本） | 缺口必须可复核，否则"改进计划"是空话；脚本只读本地日志、只输出计数与路径，不提交会话内容 | 仓库多 2 篇文档 + 1 个只读脚本 | `git revert` 该 docs 提交 | 3f6136c |
| SG-0018 | 2026-10-24T00:5x+08:00 | GUARD | 新增 `wwin set`（最大化/移动/置顶）归入**输入类**，要求 grant `scope=input`，不新设 scope | 它改变用户桌面上任意窗口的几何状态，风险等级等同点击；新设 scope 会让既有令牌语义分裂 | 无 grant 时 `wwin set` rc=4；`wwin state/list/info` 仍只读免 grant | 把该动作移出 input 校验 | T1 提交 |
| SG-0019 | 2026-10-24T00:5x+08:00 | GUARD | `ops/click-element` 默认拒绝名字含 `删除|购买|支付|提交|下单|格式化` 的节点，需 `--allow-danger` 才点 | UI 语义点击比坐标点击更容易"一次点中不可逆按钮"；默认拒绝把误触面收窄（S7 的延伸） | 少数合法场景需显式开关；误拒是一行文档就能解释的 | 删除默认拒绝词表 | T7 提交 |
| SG-0020 | 2026-10-24T00:5x+08:00 | TOOL | `winput hover` 的返回必须包含落点处的 UIA 元素（`ElementFromPoint` 的 name/type/rect），而不是只回 cursor 坐标 | "悬停生效"在 Chromium 上无法从坐标判断；元素信息让 hover 变成**可判定**动作（c0 三次手写悬停全失败就是因为没有判据） | hover 多一次 UIA 查询（约 +120 ms） | 返回体去掉 element 字段 | T2 提交 |
| SG-0021 | 2026-10-24T00:5x+08:00 | TEST | 新增 Windows 侧自建测试窗 `win/wa-fixture.ps1`（WinForms：按钮/输入框/下拉/可 hover 菜单/离屏控件），作为新原语验收载体 | 真实站点会被改版、且涉登录态；D18 要求只用自建测试窗。没有 fixture 的 GUI 判据都是脆的 | Windows 侧多一个只读测试脚本（不常驻、不注册） | 删除该 ps1 与引用它的用例 | T5 提交 |
| SG-0022 | 2026-10-24T00:5x+08:00 | SYS | 网页语义实验用 cdp-hub 的**受管一次性实例**（`cdp_launch --ephemeral`）打开示例页读 innerText，不碰用户真实 Edge | 用户 Edge 未开调试端口，重启它=改用户环境（G3）；受管实例用独立 profile，退出即删 | 临时起一个 Edge 进程与临时 profile，用完回收 | `cdp_stop` + `cdp_gc` 回收；实验只是读公开示例页 | T11 提交 |
| SG-0023 | 2026-10-24T00:5x+08:00 | DROP | 本轮不修复 docs 编号冲突（`12-authorization.md` 与 `12-retro.md` 同号） | 改名会打断既有文档互链与 reviewer 的引用习惯；冲突只是编排问题，已在新文档里用全名引用 | 编号仍重号，索引略乱 | 后续一次 `docs:` 提交里统一改名并加索引 | 记于 docs/17 |
| SG-0024 | 2026-10-24T00:5x+08:00 | TOOL | 夹具改为 WPF 而非 SG-0021 计划的 WinForms（`tests/helpers/uiawnd.ps1`、`menutwin.ps1`），并新增 `tests/helpers/imgcmp.ps1` | K17：WinForms TextBox 无 Value/TextPattern，无法验证 `set-value` 回读；WPF 控件同时提供 Invoke/Toggle/Selection/Expand 与 ValuePattern，一套夹具能覆盖全部新原语 | 与 SG-0021 的文件路径/技术栈不同（本行是对 SG-0021 的更正，SG-0021 保留原文不删） | 换回 WinForms 需重写全部 m10 用例 | T5/T9 提交 |
| SG-0025 | 2026-10-24T01:0x+08:00 | TEST | C10 的"元素矩形落在容器矩形内"判据实现为"元素矩形**包含**悬停点（±2 px）" | m7 W3 实测 UIA 元素矩形溢出容器 5–9 px（Chromium/WPF 的 box 与 UIA bounding rect 不同源），容器包含关系不是稳定判据；"探测到光标下元素"的正确含义就是命中点被元素覆盖 | 判据更贴近意图，但比原文宽松（放弃容器约束） | 改回容器包含断言，W3 会红 | T2 提交 |
| SG-0026 | 2026-10-24T01:1x+08:00 | TEST | `scripts/check-release.sh` 的 UTF-8 断言窗口从 `head -20` 放宽到 `head -40` | v1.1 的 param 块变长，`winput.ps1` 的 `OutputEncoding` 落在第 24 行、`wuia.ps1` 第 34 行，原窗口是误报 FAIL；断言意图（"脚本开头就设 UTF-8"）不变 | 断言略宽 20 行，仍早于任何载荷逻辑 | 改回 -20 需把 OutputEncoding 提前（param 必须在首位，做不到） | T10 提交 |
| SG-0027 | 2026-10-24T01:1x+08:00 | TEST | `scripts/build-release.sh` 改用 `git -c core.quotepath=false ls-files -z` + `tar --null -T` | K45：git 默认把中文路径输出成 C 风格引号串，tar 报 `Cannot stat`（实测 missions 里两个 .xlsx 漏打包，发布物少文件） | 修的是漏打包（原发布物不完整），不是格式偏好 | 回滚则该两文件再次漏打包 | T10 提交 |
| SG-0028 | 2026-10-24T01:2x+08:00 | SCOPE | T3（键盘）与 T4（免引号输入）合并为一个提交 | 两者改同一份 `bin/winput` 与 `win/winput.ps1`，拆开会产生"提交了但跑不起来"的中间态；判据仍各自独立（m8/m9 分套件） | 提交粒度略粗，回滚需整体回滚 | 按文件拆分提交不可行（同文件同区域） | 38debdf |
| SG-0029 | 2026-10-24T01:3x+08:00 | SYS | v1.1.0 冻结并打 `v1.1.0` 标签，随后推送 GitHub `Xian-debu/win-admin` | 与 SG-0014 同口径：冻结即打标签；用户 M5 后要求过"推 GitHub"作为交付的一部分 | 本地 tag + 远端推送（公开仓库，仅代码与文档，无凭据/会话内容） | `git tag -d v1.1.0` + 远端删 tag | 见收尾提交 |
| SG-0030 | 2026-10-24T01:1x+08:00 | TOOL | `ops/click-element` / `ops/wait-uia` 在默认深度落空时自动加深一次（10/3000 → 16/8000），输出加 `deepened` | 实测 Chromium 页面内容在 a11y 树 depth 12–13，默认 10 会报 `ENV_NO_NODE`——报错长得像「页面没有这个元素」，正是 c0 绕路的同类静默失败；只在失手路径多花约 1.3 s | 失败路径慢 1.3 s；显式 `--depth` 语义不变 | 删除加深分支即恢复 v1.1 行为 | T11 提交 |
| SG-0031 | 2026-10-24T01:1x+08:00 | SCOPE | 网页通道结论定为 **UIA-first**：正文用 TextPattern、元素用 Invoke/SetValue，CDP 只用于 cdp-hub 自起的受管实例 | 三通道实测 UIA 覆盖更好（含表单值）、延迟仅 1.5 s；CDP 需调试端口，而用户真实 Edge 没开端口，重启它=改用户环境（G3）且丢登录态 | 放弃 13× 速度，换零侵入 | 后续想改主链路需重做对比实验 | T11 提交（docs/18） |
| SG-0032 | 2026-10-24T01:1x+08:00 | TEST | 网页实验夹具 `web11.html` 入库到 `tests/fixtures/`（运行时复制到 Windows tmp） | 没有夹具的对比实验不可复现；文件 1.7 KB、纯静态、无凭据 | 仓库多一个 1.7 KB 静态页 | 删除该文件与 docs/18 引用 | T11 提交 |
| SG-0033 | 2026-10-24T01:1x+08:00 | TEST | m11 增加 N27 锁定 auto-deepen 契约（浅层命中 `deepened=false`；真缺失仍是 `ENV_NO_NODE` rc=3） | 加深逻辑只在失败路径触发，没有用例就会被后续重构静默删掉，退回「误报找不到」 | m11 从 13 项变 14 项，多约 3 s | 删除 N27 | T11 提交 |
| SG-0034 | 2026-10-24T01:3x+08:00 | TEST | 验收套件一律**串行**跑；跑套件期间不在同一 Windows 临时目录做别的操作 | 收尾全表时并行插入一次手动 m1，直接把对方的 winps 临时文件当成「新残留」（E5 FAIL），m9 也出现一次单次 FAIL（复跑 7/0）；污染会伪装成产品缺陷 | 单次回归耗时变长（约 15 min），但结果可判定 | 无（纯流程约束） | 本提交（K47） |
| SG-0035 | 2026-10-24T13:3x+08:00 | SCOPE | 第二轮夜间自主推进 v1.2（docs/20 T12–T19 + 其验收），遇到岔路自己定，不阻塞等用户；只把决定记进本表 | 用户 m01208 全权授权（"同样我全部授权给你了，你只需在 git 提交时单独增量提交一个自授权清单"） | 项目进度、原语设计与测试面 | 逐条回滚；用户可对任一 SG 喊停 | docs/20 提交 |
| SG-0036 | 2026-10-24T13:3x+08:00 | TOOL | `winput --allow-related`（窗口族匹配）**默认关闭**，只在显式开关时放宽 | 放宽匹配等于放宽安全边界；默认必须与 v1.1 一致，否则既有脚本会静默变形（S10）。同族语义靠显式开关表达 | 父子对话框场景需要多打一个 flag | 删除该 flag 的放宽分支 | T13 提交 |
| SG-0037 | 2026-10-24T13:3x+08:00 | TOOL | `winput type --verify` 为 **opt-in**，不默认开启 | 每次 type 多一次 UIA 查询（约 +300 ms），且 Chromium `contenteditable` 读不到 value 会误报；默认不变=不打断既有用法 | 想要闭环需显式 `--verify` | 改成默认开 | T14 提交 |
| SG-0038 | 2026-10-24T13:3x+08:00 | TOOL | `wshot` 保留 `--rect X,Y,W,H` 原语义，另增 `--box X1,Y1,X2,Y2` 与 `--clip`；不改旧参数含义 | F7 的根因是「4 个数有两种合理解释」，直接改 `--rect` 语义会静默破坏既有调用（S10）；加别名是加法 | 多一个参数要记 | 删除 --box/--clip | T15 提交 |
| SG-0039 | 2026-10-24T13:3x+08:00 | GUARD | `ops/map` 归为**只读**（只需 `scope=shot,uia`），且不提供 `--click`：看与点分属两个命令 | 地图的价值是「看哪」，点击的授权语义应由 `ops/click-element` 独立承担；把点击塞进 map 会让一个只读命令悄悄需要 input 授权 | 需要两步（map 看、click-element 点） | 给 map 加 --click 或改 scope | T16 提交 |
| SG-0040 | 2026-10-24T13:3x+08:00 | TEST | 新增夹具 `tests/helpers/dialogwin.ps1`（WPF：主窗 + Owner 子对话框 + 无关窗），用于 T13/C14 正负例 | 没有「父子对话框」的真实结构就验不了 `--allow-related`；D18 要求只用自建测试窗 | Windows 侧多一个只读测试脚本 | 删除该 ps1 与用例 | T13 提交 |
| SG-0041 | 2026-10-24T13:3x+08:00 | DROP | 本轮**不**尝试解决 B 站分区二级菜单不可达（F8）；只把 mismatch 报错补上「命中窗口 title/class/rect」 | 二级菜单不进 UIA 树是站点侧限制，硬点属红线（v1.1 已记 ENV_MENU_NOT_SHOWN）；能修的是「让人一眼看出被谁挡住」 | 该场景仍需回退一级分区 | 后续为 hover-menu 加站点级策略 | T13 提交 |
| SG-0042 | 2026-10-24T13:3x+08:00 | TOOL | 新增 `wclip set --native-path`：写剪贴板前把 `C:/a/b` 规范成 `C:\a\b` | F2 的代价是「操作者必须记得原生对话框只认反斜杠」，技能里已写错过一次；规范成 Windows 形式对任何目标都更安全 | 剪贴板内容与输入字面不同（仅斜杠方向） | 去掉该 flag | T14 提交 |
| SG-0043 | 2026-10-24T13:4x+08:00 | TOOL | T12（焦点不改状态）与 T13（窗口族匹配）合并为一个提交 | 两者改同一份 `win/winput.ps1`（Assert-Target 同一函数）与 `ops/*`，拆开会产生「改了但跑不起来」的中间态；判据仍各自独立（m13 内分组） | 提交粒度略粗 | 按文件拆分不可行（同函数同区域） | b734102 |
| SG-0044 | 2026-10-24T14:0x+08:00 | TEST | E13-2 判据从「最小化窗口 focus 后 `state==normal`」改为「回到最小化**前**的状态」 | 夹具窗口最小化前本来就是最大化态，focus 后回到最大化；原判据把正确行为判成失败 | 判据更准确，但比原文宽松（不再强制 normal） | 改回 `state==normal`，m13 N3 会红 | docs/20 §0.1 |
| SG-0045 | 2026-10-24T14:0x+08:00 | TEST | E15-4 的元素计数口径从 `wuia --find-name . --enabled` 改为 `wuia --find-type . --enabled --on-screen` | K49：`--find-name .` 匹配不到名字为空的 Edit/ComboBox/容器，`ops/map` 的 actionable 数与它差 4，原判据会把正确实现判成不一致 | 判据换了口径（计数对象从「有名字的」变成「全部」） | 改回 --find-name，m15 N3 会红并记 K49 | docs/20 §0.1 |
| SG-0046 | 2026-10-24T14:0x+08:00 | TEST | E13-3 的「被别的进程抢焦点并改状态」负例**不**做成稳定用例，改为「focus 前后签名一致」的正向断言 + op_focus 返回码透传 | 该场景需要另一个进程在我们的动作中途改 placement，验收里无法稳定构造；造假用例比不写更糟 | `ENV_STATE_CHANGED` 分支没有用例覆盖（只有 op_focus 的透传有） | 后续用双窗口抢焦点脚本补 | docs/20 §0.1 |
| SG-0047 | 2026-10-24T14:1x+08:00 | TOOL | `--expect-gone/--expect-alive` 复用既有的 `--verify` 轮询循环，不另写一套等待；两者互斥（rc=2） | 两套轮询必然漂移；复用时失败码需分流（expect→`ENV_EXPECT_FAILED`，verify 仍 `ENV_TIMEOUT`），冲突必须显式拒绝而不是「后写的赢」 | 一个 if 里有四种判据分支 | 删掉 expect 映射，回到只有 --verify | 7fafce0 |
| SG-0048 | 2026-10-24T14:2x+08:00 | TEST | E1 的提交前缀规则允许**复合对象** `A+B`（如 `bin+ops:`），每个部分仍须是已知对象 | 一次改动同时落在 bin 与 ops 时，最诚实的对象就是两个；原正则只认单一前缀，会把合法提交判成违规（m1 E1 实测 FAIL） | 判据放宽为「每个部分合法」，无法再靠前缀判断单一归属 | 改回单一前缀正则，则 b734102 永远红 | tests/check-m1.sh |
| SG-0049 | 2026-10-24T14:3x+08:00 | SYS | v1.2.0 冻结并打 `v1.2.0` 标签，随后推 GitHub `Xian-debu/win-admin` | 与 SG-0014/SG-0029 同口径：冻结即打标签；用户把「推 GitHub」当交付的一部分 | 本地 tag + 远端推送（仅代码与文档，无凭据/会话内容） | `git tag -d v1.2.0` + 远端删 tag | 收尾提交 |
| SG-0050 | 2026-10-24T14:3x+08:00 | DOC | 回填 `/root/gen24-admin/docs/38-win-admin-v2-plan.md`（跨仓提交，该仓默认分支 master） | 用户 m01208 要求「把上面的内容 git 提交到 win-admin 的规划中」；规划索引在 gen24-admin，回填让两个仓的状态一致 | 多一次跨仓提交 | 不回填（gen24-admin 会停在 v1.1 状态） | gen24-admin 提交 |
| SG-0051 | 2026-10-24T14:5x+08:00 | TOOL | `winput type` 的剪贴板恢复改为「先快照焦点值 → 轮询焦点值变化（≤900 ms）→ 再恢复」，JSON 增 `pasteSettled`/`settleMs` | K57：固定 sleep 时目标泵慢会让 `Ctrl+V` 在恢复之后才被翻译，粘出旧剪贴板却仍报 `ok:true`——这是「静默成功」，比报错危险 | 每次 type 最多多等 900 ms；读不到回读值时退化为固定 sleep | 回到固定 sleep（m9 L5 会偶发红） | 本批提交 |
| SG-0052 | 2026-10-24T14:5x+08:00 | TOOL | `key` 的组合键改为「修饰键先按 → ≥60 ms 驻留（JSON `dwellMs`）→ 释放普通键 → 再释放修饰键」 | K59：`Ctrl` 抬起太早会让 `TranslateMessage` 看到无修饰键的按键状态，`ctrl+a` 退化成纯 `a`（m8 `text='aa'`） | 每次组合键至少多驻留 60 ms | 改回三行循环（m8 K1 会偶发红） | 本批提交 |
| SG-0053 | 2026-10-24T14:5x+08:00 | TEST | 新增 `tests/helpers/kill-fixtures.sh` 并在四个 `*-start.sh` 启动前调用；`*-start.sh` 改把夹具 JSON 里的 `pid` 写入 `$STATE_DIR/<name>.pid`；m8/m9 的回读与清空改走 UIA（`wuia --find-type Edit --get-value/--set-value`） | K58（夹具泄漏抢点击）、K60（`ctrl+a/ctrl+c` 回读自己成为噪声源）、K61（清扫误杀同套件夹具：pid 文件存的是启动器 pid，WSL 的 `kill -0` 判不了 Windows pid） | 夹具管理多一层纪律：pid 文件必须是「拥有窗口的进程」；清扫只留 30 分钟内的 pid 文件 | 删除 kill-fixtures 与 pid 刷新逻辑（m11/m13 会重回 15/4 条失败） | 本批提交 |
| SG-0054 | 2026-10-24T14:5x+08:00 | DOC | T18 的改动按「代码修复 / 测试加固 / 文档发布 / 自授权清单」四类**分开提交**；自授权清单一律单独增量提交 | 用户 m01208 明确要求自授权清单单独增量提交；我一度 `git add -A` 把所有东西卷进一个提交（13cdcc0），已 `reset --soft` 撤回重做 | 提交次数变多，历史更碎但可回退粒度更细 | 合并为一个大提交（违反用户要求） | 本批提交 |
| SG-0055 | 2026-10-25T16:0x+08:00 | SCOPE | 第三轮夜间自主推进 v1.3（docs/22 T20–T26 + 验收），遇岔路自己定、不阻塞等用户；只把决定记进本表 | 用户 m02647 全权授权（"这又是一个长任务，我给你所有权限，希望你运行到底"），并要求逐步验证后提交 | 项目进度、原语设计与测试面 | 逐条回滚；用户可对任一 SG 喊停 | docs/22 提交 |
| SG-0056 | 2026-10-25T16:0x+08:00 | TOOL | `wuia` 默认**预热**：树里拿不到页面内容（find 无结果 / tree 里 Document 无页面子节点）时休眠 250 ms 重走，最多 3 遍；`--no-warm` 回到 v1.2 行为 | docs/21 F2：Chromium a11y 树延迟构建，首次查询 279 节点（全 chrome）、二次 561（页面节点齐全）；用户每次调用都是「第一次」，这就是「DOM 不进树」错觉的根因 | 命中即停，正常页面只多走一遍；最坏 +0.75 s | `--no-warm` 或删预热循环 | T20 提交 |
| SG-0057 | 2026-10-25T16:0x+08:00 | TOOL | find/action 的默认深度 3 → **20**，空结果自动加深到 **28** 一次（`deepened:true`）；tree 仍默认 3；`--no-deepen` 关闭 | 实测页面内容在 depth 13–25（docs/21 §3），默认 3/12 让 `--find-name 上传视频` 恒为 0；v1.1 的 click-element 已有同款「失手加深」先例（SG-0030） | 深树遍历更慢（561 节点 2.1 s），但只在需要时加深 | 恢复 depth 3 / 上限 12 | T20 提交 |
| SG-0058 | 2026-10-25T16:0x+08:00 | TOOL | hit-test 定义为「暖树 + 几何包含点」，`FromPoint` 只作快路径；JSON `via:"uia-point"` 或 `"rect-hit"` | docs/21 §3：`AutomationElement.FromPoint` 在 Chromium 页面返回 null 或只有 Document/Pane，靠它做命中判定必然误报「没点到」 | 每次 hit 多一次暖树遍历（约 0.3–2 s） | 只用 FromPoint（回到 F1/F3 的病） | T21 提交 |
| SG-0059 | 2026-10-25T16:0x+08:00 | TOOL | `click` 增 `--expect-change EVENT --timeout MS`（默认 2000），超时 rc=3 `ENV_NO_EFFECT`；**不传该参数时不等待**，行为与 v1.2 一致 | F1 要求「点了没效果要喊」；默认等待会让所有既有调用变慢且可能误判（点击本来就不一定改标题）——所以断言必须是显式 opt-in | 想让效果可见需显式加 flag | 删除该参数 | T22 提交 |
| SG-0060 | 2026-10-25T16:0x+08:00 | TOOL | `type` 的焦点校验**默认开启**（rc=3 `ENV_NO_FOCUS`），`--force` 保留 v1.2 行为；落地校验仍沿用 SG-0037 的 `--verify` | F4 是真实事故（标签输入丢 4 个字符，rc=0 无从发现）；焦点判断只多一次 UIA 查询，且 `--force` 给出逃生 | 无焦点调用从「静默成功」变成「明确报错」，旧脚本需加 `--force` | 加 `--allow-empty-focus` 或改默认 | T23 提交 |
| SG-0061 | 2026-10-25T16:0x+08:00 | TOOL | `wshot --out` 接受非 Windows 路径：先落 `C:/Users/Public/win-admin/tmp/shot-<sha1前8>.png` 再 `cp` 回目标，JSON 增 `wsl_path` | F5：文档示例用 `/tmp/x.png` 而实现只认 Windows 路径，用户照文档做直接失败 | 多一次文件拷贝（<1 MB） | 只认 Windows 路径 + 改文档 | T24 提交 |
| SG-0062 | 2026-10-25T16:0x+08:00 | GUARD | 新增 `ops/read-text` 归**只读**（scope `shot,uia`）；网页走 TextPattern，非 Chromium 回落剪贴板（临时写入并恢复） | F7 需要「读正文」这一等能力；读正文不改状态，不该要 input 授权（与 SG-0039 同口径） | 剪贴板兜底会短暂改动剪贴板 | 删除该 op | T24 提交 |
| SG-0063 | 2026-10-25T16:0x+08:00 | TEST | 新增夹具 `tests/fixtures/web13.html`（deep-button depth 22、文本行列表、改标题按钮、无效果按钮、嵌套可编辑区）用于 m16–m19 | F1/F2/F3 的判据必须在「真实网页结构」上验证；本地静态页可离线复现且不依赖站点改版 | 仓库多一个静态 HTML（<3 KB） | 删除该夹具与用例 | T21 提交 |
| SG-0064 | 2026-10-25T16:0x+08:00 | TEST | `--expect-change` 超时判据取 `elapsedMs >= timeout-500`（容差 500 ms），且必须 `ok:false` + `code:ENV_NO_EFFECT` | 轮询与 UIA 查询自身耗时会吃掉一部分超时预算，严格相等会偶发红；500 ms 远小于默认 2000 ms 的语义差异 | 判据略宽 | 改成严格 `>=timeout`（会偶发红） | T22 提交 |
| SG-0065 | 2026-10-25T16:0x+08:00 | SYS | v1.3.0 冻结并打 `v1.3.0` 标签，随后推 GitHub `Xian-debu/win-admin` | 与 SG-0014/SG-0029/SG-0049 同口径：冻结即打标签；用户把「推 GitHub」当交付的一部分 | 本地 tag + 远端推送（仅代码与文档，无凭据/会话内容） | `git tag -d v1.3.0` + 远端删 tag | 收尾提交 |
| SG-0066 | 2026-10-25T17:0x+08:00 | TEST | T20 的深树夹具改用 WPF `tests/helpers/deepwin.ps1`（22 层 GroupBox + `-Lazy` 延迟插入），`web13.html` 留给 T21+ 的文本行/点击判据 | T20 要验的是「深度/自动加深/预热重试」三条机制，需要**确定性**的深树与可调延迟；Chromium 是否把 generic div 暴露进 ControlView 随站点而异，静态页复现不稳。真实 Chromium 的暖树证据另取（首查 542 节点、页面内容 depth ≥12） | 夹具与真实网页仍有结构差异（WPF vs Blink a11y） | 改用 web13.html + 固定 22 层 div（会不稳） | T20 提交 |
| SG-0067 | 2026-10-25T17:0x+08:00 | TEST | E16-2 的 `--no-warm` 断言从「`passes==1`」改为「`warmRetries==0`」；同时新增 `warmRetries` 字段，tree 输出补 `depthUsed` | `passes` 计遍历次数，**自动加深会多走一遍**，与预热重试是两条独立路径；实测 `--no-warm` 时 `passes=2, warmedRetries=0, deepened=true`，原判据会把正确实现判红 | 判据少了一条「passes 必须 1」的约束 | 改回 `passes==1`（m16 N3 恒红） | docs/22 §5.1 |
| SG-0068 | 2026-10-25T17:0x+08:00 | DOC | 含非 ASCII 的 `.ps1` 在 `tools.edit/write` 之后一律补 UTF-8 BOM；`Start-Process` 的额外参数一律以逗号起始拼进 `-ArgumentList` 数组内部 | 两者都是「看起来改好了、进程却没起」的静默失败：K62（edit 剥 BOM → PS 5.1 按 ANSI 读中文报 `意外的标记"2'"`）、K63（参数在数组外 → `找不到参数名称"Lazy"` 而 rc=0） | .ps1 写盘多一步 BOM 修补 | 不补 BOM（夹具随机启动失败） | K62/K63 |
| SG-0069 | 2026-10-25T17:5x+08:00 | TOOL | hit-test 定为「暖树几何包含点」为主、`FromPoint` 为快路径；rect-hit **排除 Window/Document/Pane/Group** 且要求「有名字或可点」；auto 模式不再把容器当命中 | docs/21 F1/F3 + M17 实测：Chromium 的 `FromPoint` 对页面点返回 Document；不排除容器时深窗空白点会报 `under=Window`（改前实测），用户会以为「空白也点得到东西」 | 每次点探测多一遍暖树（find 档深度，约 0.3–2 s） | 回落到纯 FromPoint（m17 N4/N6 会红） | T21 提交 |
| SG-0070 | 2026-10-25T17:5x+08:00 | TOOL | click-by-text 放在 `winput click --click-text RE [--text-index N]`，必须 `--expect-hwnd`；`wuia` 只保留只读 `--find-text`/`--point` | 点击是注入，必须单独过 `guard/check.sh input`（与 SG-0039「看与点分属两个命令」同口径）；放在 wuia 里会让「查文本」也要求 input 授权 | 多一层命令跳转；`hit` 由 winput 合并进 JSON | 改到 wuia 动作分支 | T21 提交 |
| SG-0071 | 2026-10-25T17:5x+08:00 | TOOL | `--click-text` 解析出行后先比对目标窗口矩形，行中心在窗口外 → rc=3 `ENV_TEXT_OFFSCREEN`，不注入 | K65：Chromium 保留滚动出视口节点（用户 Edge 实测首行 y=-24512），盲点会落到窗口外别的程序上——这是真实危险，而不是精度问题 | 长页面上点远处文本需要显式 `--text-index` | 删除窗口矩形检查（S7「绝不盲点」破功） | T21 提交 |
| SG-0072 | 2026-10-25T17:5x+08:00 | TEST | E17-2 的「页面自报 `document.title`」改判为「夹具窗口标题 `clicked:deep-btn`」；T21 验收套件号定为 **m17**（任务表原写 m16 N9–N14 是估算号） | WPF 夹具没有 document.title，而判据要证明的是「点到了该文本所在控件」；窗口标题由控件 Click 回调改写，证明力等价。套件号必须在验收前钉死，否则报告与回归表对不上 | 真实页面的「点后变化」留到 T25 live 冒烟 | 改用 web13.html + document.title（会引入浏览器依赖） | docs/22 §5.1 + 任务表 |
| SG-0073 | 2026-10-25T17:5x+08:00 | DOC | 新增 K64（点探测的深度档位曾只看 find 条件，导致 rect-hit 恒 null）、K65（视口外节点仍带 rect，盲点危险） | 两者都是「看起来功能坏了 / 看起来成功了」的典型：K64 一度被误判为 rect-hit 实现错误，K65 的 `ok:true` 会掩盖真实误点 | 文档多两条 | 删掉两行 | T21 提交 |
| SG-0074 | 2026-10-25T18:1x+08:00 | TOOL | `hit` 报「可点祖先」：`under` 仍是逐字落点并附 `clickable`，`winput` 在 `actionable:false` 时把 `hit` 换成 clickable，叶节点原件进 `hit.raw` | E18-1 要求 `hit.actionable:true`，但按钮中心 FromPoint 命中的是内部 TextBlock（实测 deepwin「深层按钮」→ ControlType.Text），照实上报会让该字段恒为 false | hit 的语义从「落点元素」变成「点击实际作用的控件」，附 `raw` 保留证据 | 只报落点叶节点（m18 N1 恒红） | T22 提交 |
| SG-0075 | 2026-10-25T18:1x+08:00 | GUARD | `ops/click-element` 坐标路径的 hit-test 在注入之前、且先于 grant 检查；落点为别的窗口 → rc=3 `ENV_HIT_MISMATCH` | 实测把 uiawnd 盖在 deepwin 按钮上，坐标会注入到错误窗口；`--expect-change` 只能发现「没效果」，发现不了「点错地方」。环境判据不改状态，越早拒绝越安全 | 遮挡时会先报 ENV_HIT_MISMATCH 而不是 GUARD_NO_GRANT（m18 N9 需先移开遮挡窗口再验闸门） | 把 hit-test 移到 op_pause_gate 之后（遮挡时会真的点下去） | T22 提交 |
| SG-0076 | 2026-10-25T18:5x+08:00 | TEST | T23 的验收独立为 `tests/check-m19.sh`（N1–N10），不并入 m9；焦点门按「模式可写性」判（`ValuePattern.IsReadOnly=false` → `TextPattern` 只读 → 无模式三级），不看 `ControlType` | (a) docs/22 §4 原写「m19（m9 扩展）」，但把焦点契约塞进 m9 会让「输入通道坏了」与「落点没选好」混在同一份报告里，无法归因；按 m16–m18 先例独立成套件，m9 原样作回归。(b) 只读 `RichTextBox` 是 `ControlType.Document` 且有 TextPattern，按类型判会误判为可编辑；实测 Button 报 `no Value/Text pattern`、只读编辑器报 `text is read-only` | 夹具多一个只读 RichTextBox（且不能是第二个 TextBox，否则 m10 的 `--find-class TextBox total==1` 会红） | 并入 m9 / 按 ControlType 判（m19 N1/N2 会红或断言失去意义） | T23 提交 |
| SG-0077 | 2026-10-25T18:5x+08:00 | TOOL | `ENV_NO_EFFECT` 只在「焦点元素值可回读」时成立（`sawReadable`）；`--no-restore-clip` 与 `--force` 跳过该判定，但 JSON 如实标 `clipRestored:false` / `forced:true`，不假装成功；`--verify` 与 `--force` 相互独立（forced 下 verify 仍会说 `ENV_TEXT_NOT_ENTERED`） | 自绘控件没有 Value/Text pattern，无法回读；若一律判 `ENV_NO_EFFECT` 会把正确实现判红。反过来，跳过判定时若还报 `pasteSettled:true` 就是撒谎——v1.2 的实战缺口正是「输入成功≠文本落地」（docs/21 F4） | 不可回读时没有「落地」的正面证据，需调用方用 `--verify`/截图补证 | 不可回读也判 ENV_NO_EFFECT（自绘控件恒红） | T23 提交 |
| SG-0078 | 2026-10-25T18:5x+08:00 | DOC | 新增 K66：jq 的 `//` 把 `false` 当空，断言助手必须用 `jq -r ".$2"`（缺字段得 "null"）而不是 `// empty` | m19 首轮 9 条假失败，实际 JSON 全部符合判据；根因是 `num()` 用 `// empty` 把每个 `false` 读成空串，幂等重跑仍红，极易被误判成功能缺陷（这类「测试坏了而代码是对的」的坑与 K41 同类，值得留档） | 文档多一条 | 删掉该行 | T23 提交 |
