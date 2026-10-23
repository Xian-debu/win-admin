# 18 · 网页语义通道实验（T11 spike）

> 目的：调研会话 c0ace632（B 站投稿）撞上「网页内容读不到 / 元素点不准」后，验证 v1.1 的 UIA 语义层在**网页**（Chromium a11y 树）上到底能走多远，以及 CDP 是否必要。
> 结论先行：**读正文和点元素都不需要 CDP**；UIA 的 Document TextPattern 能取近似全文，`wuia --find-*` + Invoke 能点页面内按钮。CDP 的唯一优势是速度（13×），代价是需要调试端口，而用户真实 Edge 没开端口——重启它属于红线。

## 1 · 装置

| 项 | 值 |
| --- | --- |
| 夹具页 | `C:/Users/Public/win-admin/tmp/web11.html`（1441 B，UTF-8） |
| 页面内容 | h1 / 2 段 p / 3 个 `.item` / 2 个链接 / 按钮甲 `#btn1`（点击改 `document.title='clicked-btn1'`）/ 按钮乙 `#btn2`（无监听）/ `input#inp`（初值 `初始值-abc`）/ `select#sel`（选项一/二）/ `table` / `textarea#ta` / `display:none` 的 `div#hidden` / 结尾标记 `END-OF-PAGE-MARKER` |
| 动态内容 | `setTimeout(…, 1500)` 追加 `[动态插入于 1.5s]` |
| 浏览器 | Edge 155.0.4283.45，由 `cdp_launch --ephemeral` 起的受管实例（profile `C:\Users\Public\cdp-admin\profiles\_ephemeral\wa-web11-*`），端口 9222 |
| 窗口 | hwnd `0x6f1154`，标题「wa-web11 语义试验页 - 个人 - Microsoft Edge」 |

复现：

```bash
# 1) 起受管浏览器（一次性 profile，退出即删）
#    （agent 用 cdp_launch 工具；手工等价：cdpctl run --url file:///C:/Users/Public/win-admin/tmp/web11.html）
# 2) 取 hwnd
bash bin/wwin list | jq -r '.windows[] | select(.title|test("web11")) | .hwnd'
# 3) 三条通道各读一次（见 §2）
bash bin/wuia --find-aid RootWebArea --get-text
bash bin/wuia --find-name '^按钮甲$' --depth 16 --max 6000
bash ops/click-element --hwnd 0x6f1154 --name '^按钮甲$' --yes
```

CDP 侧脚本（零依赖，Node 22 自带 WebSocket）：`/tmp/cdp-eval.mjs`（`Runtime.evaluate` 读 `document.body.innerText`）、`/tmp/cdp-check.mjs`（读 `#inp.value`，用于交叉验证 UIA 写入）、`/tmp/cdp-reload.mjs`（`Page.reload`）。

## 2 · 三通道读数（同一页面、同一时刻）

| 通道 | 字符数 | 延迟 | 含 select 选项文字 | 含 textarea 内容 | 含 input value | 需要调试端口 |
| --- | --- | --- | --- | --- | --- | --- |
| CDP `document.body.innerText` | 316 | **0.11 s** | 是 | **否** | **否** | 是 |
| UIA `--find-aid RootWebArea --get-text`（TextPattern） | 347 | 1.50 s | **否** | 是 | 是 | **否** |
| 剪贴板（`ctrl+a` / `ctrl+c` + `wclip get`） | 353 | 2.00 s | 否 | 是 | 是 | 否 |
| UIA 只扫名字（v1.0 唯一手段） | 正文 **0** | 1.42 s（318 节点 / 1051 名字字符） | 否 | 否 | 否 | 否 |

三通道一致的地方：`display:none` 的 `hidden` 段落**都不**出现（可访问性正确剔除）；1.5 s 后动态插入的文字**都**出现。

读法建议：**要正文 → `--get-text`（TextPattern）；要表单当前值 → `--get-value` 逐个控件取**（innerText 不含 input value，这是 CDP 的坑而不是 UIA 的）。剪贴板只在 TextPattern 缺失（非 Chromium 控件、自绘文本）时兜底，它会污染用户剪贴板、耗时最长。

## 3 · 页面内元素：UIA 能定位、能点、能写值

v1.0 的已知局限里写着「网页里的元素基本不可达」——实测**在 Chromium 上不成立**，a11y 树把 DOM 语义完整暴露了出来：

```jsonc
// bash bin/wuia --find-name '^按钮甲$' --depth 16 --max 6000
{"ok":true,"count":1,"nodes":[{
  "name":"按钮甲", "type":"ControlType.Button", "aid":"btn1",
  "rect":{"x":87,"y":547,"w":102,"h":54}, "depth":13,
  "patterns":["Invoke","ScrollItem"]}]}
```

- **Invoke 可用**：`ops/click-element --hwnd 0x6f1154 --name '^按钮甲$' --yes` → `{"ok":true,"strategy":"invoke"}`，随后 `wwin info` 的标题变成 `clicked-btn1 - …`，可机器判定。
- **写值可用**：`wuia --find-aid '^inp$' --set-value 'UIA 写入测试-OK'` → ok:true；CDP 侧读 `#inp.value` 回读 `UIA 写入测试-OK`，**说明写的是真 DOM 值，不是截图幻觉**。
- **列表可枚举**：`--find-type Hyperlink` 能列出页面里两个链接（名字+rect）。

### 3.1 由此暴露的真缺口（已在 v1.1.0（T11 收尾）修）

`ops/click-element` / `ops/wait-uia` 默认 `--depth 10 --max 3000`，而**网页内容在 depth 12–13**、浏览器 chrome 只占 0–6 层。于是默认参数点网页按钮直接报：

```text
ENV_NO_NODE: no control matched (hwnd=7278932 name=^按钮甲$ type= aid= class= index=0)
```

这个报错**看起来像「页面里没有这个元素」**，实际是「搜得不够深」——正是 c0 里「只能绕路」的那类静默失败。修法（不改变显式 `--depth` 的语义，只在默认值失手时补一次）：

- `ops/click-element`：抽出 `select_node()`；首次查找空 → `DEPTH=16 MAX=8000` 重查一次；输出新增 `deepened:true|false`。
- `ops/wait-uia`：抽出 `build_fargs()`；轮询中 `seen==0 && !DEEPENED && DEPTH<16` → 加深并重试（`--gone` 同样受益：否则浅搜「看不见」会被误判成「已消失」）。
- 实测：默认参数点按钮甲 → `{"ok":true,"strategy":"invoke","deepened":true}`；`wait-uia --name '^按钮甲$' --timeout 4000` → `{"ok":true,"waited_ms":2946}`（含一次加深）；不存在的元素仍 `{"ok":false,"code":"ENV_TIMEOUT","waited_ms":2851}`。

### 3.2 异步 a11y：同一窗口两次 dump 不一样

| 时刻 | 节点数 | 名字字符 | 含页面内容 |
| --- | --- | --- | --- |
| 页面加载后约 1.3 s | 279 | 707 | **否** |
| 稍后（同一 hwnd，未重载） | 318 | 1051 | 是 |

Chromium 的无障碍树是**延迟构建**的：刚出窗口时只有 chrome，页面节点随后才长出来。因此「读不到页面」有两种成因，必须分开处理：**(a) 搜得太浅**（改默认深度）；**(b) 树还没长好**（轮询重试）。`ops/wait-uia` 的「加深 + 轮询」正好同时覆盖两者，读网页应优先用它而不是一次性 `wuia find`。

## 4 · CDP 的定位（不要为了读网页去开端口）

| 维度 | UIA | CDP |
| --- | --- | --- |
| 前提 | 窗口在前台即可，零配置 | 目标进程必须带 `--remote-debugging-port` |
| 用户真实 Edge | 直接可用 | **不可用**（重启带端口 = 关掉用户浏览器，红线） |
| 登录态 | 天然复用 | 新 profile 需重新登录 |
| 速度 | 1.4–2.0 s/次 | 0.11 s/次 |
| 正文完整度 | 高（含表单值） | 中（不含 input value / textarea 文本） |
| 元素动作 | Invoke / SetValue / Toggle（真 DOM 事件） | 任意 JS |

结论：**CDP 只用于我们自己起的受管实例**（cdp-admin 的 `cdpctl`，一次性 profile），用于调试、断言或极端复杂的 SPA 抓取；常规「读页面 / 点按钮 / 填表单」一律走 UIA，这样对用户既有的浏览器零侵入。

## 5 · 对 v1.2 的建议（按优先级）

1. **`ops/read-text`**：`--hwnd` 或 `--title` + `--mode auto|uia|clip`，auto = TextPattern → 剪贴板兜底；`--max-chars` 截断、`--json` 输出 `{text, source, chars, ms}`。这是「投稿时读页面校验」最缺的一条命令。
2. **默认深度策略**：`wuia find` 在 `--depth` 未显式给出时先按 10 搜、空则自动加深一次并在 JSON 里标 `deepened`（click-element/wait-uia 已这么做，`wuia` 本体也应对齐，避免手工两段式）。
3. **网页元素动作的配方**：文档补一节「网页 = 深层 a11y 树」：先 `wait-uia` 等节点出现，再 `click-element --strategy auto`，最后用 `--verify value:RE` / 标题变化判定；不要用坐标盲点。
4. **不做的**：不接管用户真实 Edge 的调试端口、不注入 JS 到用户浏览器、不读 cookie/localStorage。

## 6 · 复现脚本与产物

- 夹具页：仓库内 `tests/fixtures/web11.html`（测试副本放在 `C:/Users/Public/win-admin/tmp/web11.html`，因为浏览器要读 Windows 路径）。
- CDP 脚本与实测输出：`/tmp/cdp-eval.mjs`、`/tmp/cdp-check.mjs`、`/tmp/cdp-reload.mjs`。
- 收尾：`cdp_stop {name:wa-web11}` + `cdp_gc` 已执行——实测收尾后 `counters.edges=0 / sessions=0 / rogue_dirs=0`，一次性 profile 未留在磁盘上（`C:` 余量 70.3 GB / 67.3% 已用）。
