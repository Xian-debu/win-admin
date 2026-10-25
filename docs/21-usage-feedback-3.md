# 21 · v1.2 实战反馈（session-c022 取证）

- 日期：2026-10-24（实战）/ 2026-10-25（取证）
- 来源：`session-c022d2c2-3c83-4b23-b593-d5181547b58a`（用户用 v1.2.0 完成「B 站投稿」全流程，结尾要求它给自己打分）。
- 同类证据：`/root/gen24-admin/docs/45-bili-submission.md`（用户侧归档）、`missions/char-bili-2026-10-24/`（本仓库 mission 存档）。
- 结论先行：7 条反馈里 **5 条是真缺陷**（其中 2 条是 v1.1 文档/默认参数造成的系统性误判），2 条是文档漂移；**没有一条需要 CDP**。

## 1 · 实战现场

| 项 | 值 |
|---|---|
| 任务 | 把 494 s / 1080P 的成片投到 B 站（标题/声明/分区/标签/封面/简介/水印/可见范围/提交/取 BV） |
| 浏览器 | 用户**真实 Edge**（无调试端口），SessionId=1 真实交互桌面 |
| 结果 | 投递成功，BV1qyHN6PEQ8；有效操作不到一半时间，其余消耗在「点了没反应、不知道点没点到」 |
| 代价 | 两次误操作（水印复选框点到隔壁可见范围 radio → 「仅自己可见」；分区二级被视口裁切未选中）；字幕最终没上传 |

## 2 · 七条反馈逐条定级

| # | 反馈原文摘要 | 定级 | 根因 |
|---|---|---|---|
| F1 | 点击成功 ≠ 命中控件；「立即投稿」点空 5 次以上，`click` 都返回 `{"ok":true,"injected":true}` | **真缺陷** | `winput click` 只报「按键/鼠标事件已注入」，没有命中对象、没有效果断言 |
| F2 | 页面 DOM 不进 UIA 树，`--depth 20 --max 12000` 只有约 440 节点全是 chrome | **真缺陷（默认参数+冷启动）** | 见 §3：冷进程首查只拿到 chrome；默认 depth 3 / find 上限 12 也够不着页面内容 |
| F3 | 退化成截图+坐标点击；滚动/折叠让坐标失效，建议 `click-by-text` | **真缺陷** | 没有「文本行 → rect → 点中心」这条通道；也没有几何 hit-test |
| F4 | `type` 在 `target:null` 时静默丢字，rc=0 | **真缺陷** | type 只判断「剪贴板粘贴已发」，没判断「落点存在且值变了」 |
| F5 | `wshot --out` 不接受 WSL 路径 | **真缺陷（文档与实现不一致）** | `wa_winpath` 对 `/tmp` 无映射，直接把非法路径丢给 Windows |
| F6 | `wwin focus --yes` 报 unknown arg | **文档漂移** | focus 不需要注入本无需 --yes，但 SKILL 仍在演示 |
| F7 | 弹不出对话框的按钮没有诊断（上传字幕/编辑章节） | **真缺陷（可观测性）** | 点击后没有窗口/对话框/标题/URL 变化检测，无法区分「不可用/被遮罩/需 hover」 |

## 3 · F2 取证：冷启动，不是「DOM 不进树」

装置：`cdp_launch --ephemeral` 起受管 Edge（Edg/155.0.4283.45，临时 profile，不碰用户浏览器），读同一窗口同一参数。

| 页面 | 第 1 次 `wuia --depth 20 --max 12000` | 第 2 次（同一 hwnd、同样参数） |
|---|---|---|
| `https://www.bilibili.com` | 279 节点 / 名字 95 / 无页面节点 | **561 节点 / 名字 194 / 页面节点 depth 13–25** |
| `https://example.com` | 299 / RootWebArea 无子节点 | 313 / 段落与 meta 文本齐全 |
| `--find-name '^直播$'`（B 站首页） | **total 0** | **total 4**（含 rect，depth 17–20） |
| `--find-type ControlType.Edit`（depth 25） | — | 3 个（含页面内 depth 20 的输入框） |

机理：Chromium 的无障碍树**按需延迟构建**。`wuia` 每次都是一个新进程，第一次遍历触发构建但只拿得到浏览器 chrome（约 280 节点），树在随后 1–2 s 内长全；第二次遍历才有页面节点。用户侧每次调用都是「第一次」，于是得到「DOM 从不进树」的稳定错觉，而 `--find-aid RootWebArea --get-text`（TextPattern，单元素属性）不受影响——这正是它的「唯一可靠通道」观察。

补充实测：`--point X,Y` 在 Chromium 页面文本上返回 `under:null` + 只有 Document/Pane 祖先，说明 `AutomationElement.FromPoint` 在该 provider 上不命中页面内元素（F1 的 hover 观察同源）。**hit-test 必须用「暖树 + 几何包含」而不是 FromPoint。**

## 4 · 当场复现的另外三条（v1.2.0 实测输出）

```text
$ bin/wshot --out /tmp/v13-test.png --rect 0,0,200,120
{"ok":false,"code":"EXEC_FAIL","msg":"路径的形式不合法。"}

$ bin/wwin focus --hwnd 726430 --yes
unknown arg: --yes

$ bin/winput type --text 'v13probe'      # 焦点在页面空白（无可编辑控件）
{"ok":true,...,"target":null,...}          # rc=0，一个字符都没落地
```

## 5 · 与 docs/18 的关系（更正，不删档）

docs/18 §3 的结论「页面元素 UIA 能定位、能点」**在暖树 + 显式深度的前提下成立**；它低估了两件事：(a) 文档演示的 `--depth 16` 是必要参数而不是可选参数，而 CLI 默认是 3/12；(b) 每次新进程都是冷启动，docs/18 §3.2 记了「两次 dump 不一样」却没有把它变成默认行为。docs/18 已加更正注记，指向本文与 docs/22 的 T20/T21。

## 6 · 快照数据（供后续对照）

- 321 个 UIA 节点（example.com 暖）/ 561（B 站首页暖）/ 279（B 站首页冷）。
- 暖树整树遍历 561 节点耗时 2.1 s（单次）；冷进程首查 + 二次查询合计 3–4 s。
- 页面内容深度分布：Document 在 11，页面容器 12–19，可交互元素 17–25。
- TextPattern 读全文：web11 夹具 346 字（与 docs/18 的 347 一致）。
